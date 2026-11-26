import SwiftUI
import UIKit
import WebKit

enum ImageUtil {
    /// 压到最长边 maxSide、JPEG 体积不超过 maxBytes（服务器单张照片上限约 1.4MB）
    static func jpeg(_ img: UIImage, maxSide: CGFloat = 1280, maxBytes: Int = 1_100_000) -> Data? {
        let s = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let r = UIGraphicsImageRenderer(size: size)
        let small = r.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        var q: CGFloat = 0.75
        var d = small.jpegData(compressionQuality: q)
        while let x = d, x.count > maxBytes, q > 0.3 { q -= 0.1; d = small.jpegData(compressionQuality: q) }
        return d
    }
    static func dataURL(_ d: Data) -> String { "data:image/jpeg;base64," + d.base64EncodedString() }
}

/// 拍照 / 从相册选一张
struct ImagePicker: UIViewControllerRepresentable {
    var camera: Bool
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = camera && UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ p: ImagePicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// 题图：复用网页的画图代码（几何 / 函数 / 电路），在题目下面显示
struct FigView: View {
    let fig: Any
    @State private var h: CGFloat = 150
    var body: some View { FigRep(fig: fig, height: $h).frame(height: h).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) }
}

private struct FigRep: UIViewRepresentable {
    let fig: Any
    @Binding var height: CGFloat

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(WeakHandler(context.coordinator), name: "maxnote")
        cfg.userContentController = uc
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.isScrollEnabled = false
        v.scrollView.backgroundColor = .clear
        if let d = try? JSONSerialization.data(withJSONObject: fig, options: [.fragmentsAllowed]) {
            let b64 = d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            if let u = URL(string: Site.text + "/figview#" + b64) { v.load(URLRequest(url: u)) }
        }
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {}

    final class Coord: NSObject, WKScriptMessageHandler {
        let parent: FigRep
        init(_ p: FigRep) { parent = p }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let d = m.body as? [String: Any], d["type"] as? String == "height", let h = d["h"] as? Double, h > 20 else { return }
            DispatchQueue.main.async { self.parent.height = CGFloat(min(h, 420)) }
        }
    }
}
