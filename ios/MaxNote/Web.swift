import SwiftUI
import WebKit
import PDFKit
import UIKit

/// 网页容器：WKWebView + 和网页的桥（震动、打印、蓝牙打印机）+ 原生弹窗 + 下拉刷新
final class Web: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let view: WKWebView
    @Published var progress: Double = 0
    @Published var failed: String?
    @Published var showPrinter = false
    @Published var showSettings = false
    private var obs: NSKeyValueObservation?
    private let refresh = UIRefreshControl()

    // 注入：给网页加 native 标记（样式可据此微调）
    private static let boot = "document.documentElement.classList.add('native');window.MAXNOTE_NATIVE=true;"

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.applicationNameForUserAgent = "MaxNoteApp/1.0"
        let uc = WKUserContentController()
        uc.addUserScript(WKUserScript(source: Web.boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = uc
        view = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        uc.add(WeakHandler(self), name: "maxnote")
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.keyboardDismissMode = .interactive
        if #available(iOS 16.4, *) { view.isInspectable = true }
        refresh.addTarget(self, action: #selector(pull), for: .valueChanged)
        view.scrollView.refreshControl = refresh
        obs = view.observe(\.estimatedProgress, options: [.new]) { [weak self] v, _ in
            DispatchQueue.main.async { self?.progress = v.estimatedProgress }
        }
        load()
    }

    func load() {
        failed = nil
        view.load(URLRequest(url: Site.url))
    }

    @objc private func pull() { view.reload() }

    // MARK: 导航
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "blob" || scheme == "data" { return decisionHandler(.allow) }
        if scheme == "http" || scheme == "https" {
            if url.host == Site.url.host { return decisionHandler(.allow) }
            if action.navigationType == .linkActivated || action.targetFrame == nil {
                UIApplication.shared.open(url) // 外链（Notion、claude.ai）交给系统打开
                return decisionHandler(.cancel)
            }
            return decisionHandler(.allow)
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refresh.endRefreshing()
        failed = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        refresh.endRefreshing()
        if (error as NSError).code == NSURLErrorCancelled { return }
        failed = error.localizedDescription
    }

    // MARK: 新窗口、JS 弹窗（网站里用了 confirm / alert）
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { UIApplication.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        Web.top()?.present(a, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        Web.top()?.present(a, animated: true)
    }

    static func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    // MARK: 网页 → 原生
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any], let type = d["type"] as? String else { return }
        switch type {
        case "haptic":
            Haptics.play(gaps: (d["gaps"] as? [Double]) ?? [0])
        case "print":
            printSheets()
        case "bluetooth":
            DispatchQueue.main.async { self.showPrinter = true }
        default:
            break
        }
    }

    // MARK: 把排好版的 A4 页面截成 PDF（每张 .sheet 一页，所见即所得）
    func sheetsPDF(_ done: @escaping (PDFDocument?) -> Void) {
        let js = """
        (function(){var p=document.getElementById('paper');if(p){p.style.zoom='1';}
        return Array.from(document.querySelectorAll('#paper .sheet')).map(function(e){var r=e.getBoundingClientRect();return [r.left+scrollX,r.top+scrollY,r.width,r.height];});})()
        """
        view.evaluateJavaScript(js) { [weak self] res, _ in
            guard let self = self else { return }
            let rects = ((res as? [[Double]]) ?? []).filter { $0.count == 4 }.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
            let doc = PDFDocument()
            var i = 0
            func next() {
                if i >= rects.count {
                    self.view.evaluateJavaScript("window.dispatchEvent(new Event('resize'))", completionHandler: nil) // 恢复预览缩放
                    return done(doc.pageCount > 0 ? doc : nil)
                }
                let cfg = WKPDFConfiguration()
                cfg.rect = rects[i]
                self.view.createPDF(configuration: cfg) { result in
                    if case .success(let data) = result, let page = PDFDocument(data: data)?.page(at: 0) {
                        doc.insert(page, at: doc.pageCount)
                    }
                    i += 1
                    next()
                }
            }
            next()
        }
    }

    /// AirPrint：系统会自动发现同一 Wi-Fi 下的打印机
    func printSheets() {
        sheetsPDF { doc in
            DispatchQueue.main.async {
                let pc = UIPrintInteractionController.shared
                let info = UIPrintInfo(dictionary: nil)
                info.jobName = "MAX NOTE"
                info.outputType = .general
                pc.printInfo = info
                if let data = doc?.dataRepresentation() {
                    pc.printingItem = data
                } else {
                    pc.printFormatter = self.view.viewPrintFormatter()
                }
                pc.present(animated: true, completionHandler: nil)
            }
        }
    }
}

/// 避免 WKUserContentController 强引用造成循环引用
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

struct WebViewHost: UIViewRepresentable {
    let web: Web
    func makeUIView(context: Context) -> WKWebView { web.view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

enum Haptics {
    static func play(gaps: [Double]) {
        var t = 0.0
        for (i, g) in gaps.enumerated() {
            t += g
            DispatchQueue.main.asyncAfter(deadline: .now() + t / 1000) {
                let gen = UIImpactFeedbackGenerator(style: i == 0 ? .light : .soft)
                gen.impactOccurred()
            }
        }
    }
}
