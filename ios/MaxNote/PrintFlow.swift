import SwiftUI
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct PItem {
    let subject: String, topic: String, stem: String, type: String, tag: String, explanation: String
    let options: [String], answer: [String]
}

struct PrintOptions {
    var title = "MAX NOTE 练习"
    var cols = 1
    var size = 2            // 1 小 2 中 3 大
    var answers = 2         // 0 不带 1 题后 2 末页答案
    var lines = 4           // 解答题留白行数
    var nameLine = true

    /// 上次用的版式记在本机
    static func load() -> PrintOptions {
        let u = UserDefaults.standard
        var o = PrintOptions()
        guard u.object(forKey: "po.cols") != nil else { return o }
        o.title = u.string(forKey: "po.title") ?? o.title; o.cols = u.integer(forKey: "po.cols"); o.size = u.integer(forKey: "po.size")
        o.answers = u.integer(forKey: "po.answers"); o.lines = u.integer(forKey: "po.lines"); o.nameLine = u.bool(forKey: "po.name")
        return o
    }
    func save() {
        let u = UserDefaults.standard
        u.set(title, forKey: "po.title"); u.set(cols, forKey: "po.cols"); u.set(size, forKey: "po.size"); u.set(answers, forKey: "po.answers"); u.set(lines, forKey: "po.lines"); u.set(nameLine, forKey: "po.name")
    }
}

/// A4 排版：把选好的题排成真正的 A4 页面（PDF），再交给 AirPrint / 蓝牙打印机 / 分享
enum PDFMaker {
    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)

    static func make(_ items: [PItem], _ o: PrintOptions) -> PDFDocument? {
        let margin: CGFloat = 40, gap: CGFloat = 22
        let cols = CGFloat(o.cols)
        let colW = (page.width - margin * 2 - gap * (cols - 1)) / cols
        let base: CGFloat = [1: 10.5, 2: 12, 3: 14][o.size] ?? 12
        let body = UIFont.systemFont(ofSize: base), bold = UIFont.boldSystemFont(ofSize: base), small = UIFont.systemFont(ofSize: base - 2.5)
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3; para.lineBreakMode = .byWordWrapping

        func attr(_ s: String, _ f: UIFont, _ c: UIColor = .black) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: para])
        }
        func height(_ a: NSAttributedString, _ w: CGFloat) -> CGFloat {
            ceil(a.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        }

        var blocks: [(NSAttributedString, Int)] = []
        let numW: CGFloat = 22
        for it in items {
            let m = NSMutableAttributedString()
            m.append(attr([it.subject, it.topic].filter { !$0.isEmpty }.joined(separator: " · ") + "\n", small, .gray))
            m.append(attr(plain(it.stem), body))
            if !it.options.isEmpty { m.append(attr("\n" + it.options.map { plain($0) }.joined(separator: "\n"), body)) }
            if o.answers == 1 { m.append(attr("\n答案：" + plain(it.answer.joined(separator: " / ")) + (it.explanation.isEmpty ? "" : "　解析：" + plain(it.explanation)), small, .darkGray)) }
            let drawTag = ["作图", "函数", "电路", "光路", "受力"].contains(it.tag)
            let lines = (it.type == "short" && !drawTag) ? o.lines : (drawTag ? 6 : 0)
            blocks.append((m, lines))
        }
        var ans: [NSAttributedString] = []
        if o.answers == 2 {
            for (i, it) in items.enumerated() {
                ans.append(attr("\(i + 1). " + plain(it.answer.joined(separator: " / ")) + (it.explanation.isEmpty ? "" : "\n    解析：" + plain(it.explanation)), body))
            }
        }

        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = [kCGPDFContextTitle as String: o.title]
        let r = UIGraphicsPDFRenderer(bounds: page, format: fmt)
        let data = r.pdfData { ctx in
            var pageNo = 0, col = 0
            var y: CGFloat = margin
            var pageTop: CGFloat = margin
            func newPage(first: Bool = false) {
                ctx.beginPage(); pageNo += 1; col = 0
                pageTop = margin
                if first {
                    let t = attr(o.title, UIFont.boldSystemFont(ofSize: base + 8))
                    t.draw(at: CGPoint(x: margin, y: margin))
                    let d = attr(o.nameLine ? "姓名：__________　日期：__________" : "", small, .darkGray)
                    let dw = d.size().width
                    d.draw(at: CGPoint(x: page.width - margin - dw, y: margin + base + 2))
                    let g = ctx.cgContext
                    g.setStrokeColor(UIColor.black.cgColor); g.setLineWidth(1.2)
                    g.move(to: CGPoint(x: margin, y: margin + base + 22)); g.addLine(to: CGPoint(x: page.width - margin, y: margin + base + 22)); g.strokePath()
                    pageTop = margin + base + 34
                }
                y = pageTop
                // 页脚
                let f = attr("\(pageNo)", small, .gray)
                f.draw(at: CGPoint(x: (page.width - f.size().width) / 2, y: page.height - margin + 10))
            }
            func place(_ text: NSAttributedString, numLabel: String?, extraLines: Int = 0) {
                let w = colW - (numLabel == nil ? 0 : numW)
                let h = height(text, w) + CGFloat(extraLines) * 24 + 12
                if y + h > page.height - margin - 6 {
                    if col + 1 < o.cols { col += 1; y = pageTop } else { newPage() }
                }
                let x = margin + CGFloat(col) * (colW + gap)
                if let n = numLabel { attr(n, bold).draw(at: CGPoint(x: x, y: y)) }
                text.draw(with: CGRect(x: x + (numLabel == nil ? 0 : numW), y: y, width: w, height: height(text, w) + 2), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                var yy = y + height(text, w) + 4
                if extraLines > 0 {
                    let g = ctx.cgContext
                    g.setStrokeColor(UIColor.lightGray.cgColor); g.setLineWidth(0.6)
                    for _ in 0..<extraLines { yy += 24; g.move(to: CGPoint(x: x + (numLabel == nil ? 0 : numW), y: yy)); g.addLine(to: CGPoint(x: x + colW, y: yy)); g.strokePath() }
                }
                y += h
            }
            newPage(first: true)
            for (i, b) in blocks.enumerated() { place(b.0, numLabel: "\(i + 1).", extraLines: b.1) }
            if !ans.isEmpty {
                newPage()
                place(attr("参考答案与解析", UIFont.boldSystemFont(ofSize: base + 3)), numLabel: nil)
                for a in ans { place(a, numLabel: nil) }
            }
        }
        return PDFDocument(data: data)
    }
}

struct PDFPreview: UIViewRepresentable {
    let doc: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .clear
        v.document = doc
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) { v.document = doc }
}

/// 打印流程：选题 → 版式（A4 预览直接显示、随改随变）→ AirPrint / 蓝牙 / 分享；写完后可拍照让 Max 检查
struct PrintFlow: View {
    let preselect: [Int]
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bank = Feed("/api/bank")
    @StateObject private var wrong = Feed("/api/wrong?tab=active")
    @StateObject private var bt = BTPrinter()
    @State private var selection = Set<Int>()
    @State private var opt = PrintOptions.load()
    @State private var doc: PDFDocument?
    @State private var busy = false
    @State private var error: String?
    @State private var showPrinter = false
    @State private var source = 0
    @State private var picking = false
    @State private var checking = false
    @State private var report: CheckReport?
    @State private var full = false

    private var items: [J] { (source == 0 ? bank : wrong).obj.arr("items") }
    private var signature: String { "\(selection.sorted())|\(opt.title)|\(opt.cols)|\(opt.size)|\(opt.answers)|\(opt.lines)|\(opt.nameLine)" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewArea
                Form {
                    Section("选题") {
                        Picker("来源", selection: $source) { Text("题库").tag(0); Text("错题本").tag(1) }.pickerStyle(.segmented)
                        DisclosureGroup("选题（已选 \(selection.count) 题）") {
                            HStack {
                                // 同一行里有两个按钮：必须用 borderless，否则点一个会同时触发两个（「全选」会被「清空」抵消）
                                Button("全选") { items.forEach { selection.insert($0.int("id")) } }.buttonStyle(.borderless)
                                Spacer()
                                Button("清空") { selection.removeAll() }.buttonStyle(.borderless)
                            }
                            .font(.footnote)
                            ForEach(Array(items.enumerated()), id: \.offset) { _, q in
                                let id = q.int("id")
                                Button { Haptic.select(); if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selection.contains(id) ? Color.brand : Color.mute)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(q.str("subject") + (q.str("topic").isEmpty ? "" : " › " + q.str("topic"))).font(.caption).foregroundStyle(Color.mute)
                                            Text(plain(q.str("stem").replacingOccurrences(of: "^[^·]*·", with: "", options: .regularExpression))).font(.subheadline).foregroundStyle(Color.ink).lineLimit(2).multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowBackground(Color.card)

                    Section("版式") {
                        TextField("标题", text: $opt.title)
                        Picker("分栏", selection: $opt.cols) { Text("单栏").tag(1); Text("双栏").tag(2) }.pickerStyle(.segmented)
                        Picker("字号", selection: $opt.size) { Text("小").tag(1); Text("中").tag(2); Text("大").tag(3) }.pickerStyle(.segmented)
                        Picker("答案", selection: $opt.answers) { Text("不带").tag(0); Text("题后").tag(1); Text("末页").tag(2) }.pickerStyle(.segmented)
                        Picker("解答留白", selection: $opt.lines) { Text("不留").tag(0); Text("3 行").tag(3); Text("5 行").tag(5); Text("8 行").tag(8) }.pickerStyle(.segmented)
                        Toggle("姓名 / 日期栏", isOn: $opt.nameLine).tint(Color.brand)
                    }
                    .listRowBackground(Color.card)

                    if let e = error { Section { Text(e).font(.footnote).foregroundStyle(Color.brand) }.listRowBackground(Color.card) }
                }
                .scrollContentBackground(.hidden)
            }
            .background(WarmBackground())
            .navigationTitle("A4 排版打印")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let d = doc, let data = d.dataRepresentation() {
                        ShareLink(item: PDFFile(data: data, name: opt.title), preview: SharePreview(opt.title + ".pdf")) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .task { selection = Set(preselect); await bank.load(); await wrong.load() }
            .task(id: signature) {
                // 选题 / 版式一变，预览自动重排（稍等一下，避免连点时反复排版）
                opt.save()
                guard !selection.isEmpty else { doc = nil; return }
                try? await Task.sleep(nanoseconds: 450_000_000)
                if !Task.isCancelled { await build() }
            }
            .fullScreenCover(isPresented: $picking) { ImagePicker(camera: true) { img in Task { await check(img) } }.ignoresSafeArea() }
            .sheet(item: $report) { CheckReportView(report: $0).environmentObject(router) }
            .sheet(isPresented: $showPrinter) { if let d = doc { PrinterSheet(pdf: d, bt: bt) } }
            .fullScreenCover(isPresented: $full) { if let d = doc { NavigationStack { PDFPreview(doc: d).background(Color.cream).navigationTitle("\(d.pageCount) 页 A4").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { full = false } } } } } }
        }
    }

    /// 顶部：A4 预览直接显示
    @ViewBuilder private var previewArea: some View {
        ZStack(alignment: .topTrailing) {
            if let d = doc {
                PDFPreview(doc: d)
                    .frame(height: 330)
                    .background(Color.card)
                Button { full = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.footnote.weight(.bold)).foregroundStyle(Color.ink).padding(9).background(.ultraThinMaterial, in: Circle()) }
                    .padding(10)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 30)).foregroundStyle(Color.mute.opacity(0.6))
                    Text(busy ? "排版中…" : "选几道题，这里直接显示 A4 预览").font(.subheadline).foregroundStyle(Color.mute)
                }
                .frame(maxWidth: .infinity).frame(height: 330).background(Color.card)
            }
        }
        .overlay(Rectangle().fill(Color.hairline).frame(height: 0.6), alignment: .bottom)
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if checking { HStack(spacing: 8) { ProgressView(); Text("Max 正在看照片、对照答案批改…").font(.footnote).foregroundStyle(Color.mute) } }
            HStack(spacing: 8) {
                Button { if let d = doc { airPrint(d) } } label: { Label("AirPrint", systemImage: "printer").lineLimit(1) }.buttonStyle(GlassButtonStyle(prominent: true))
                Button { showPrinter = true } label: { Label("蓝牙", systemImage: "dot.radiowaves.left.and.right").lineLimit(1) }.buttonStyle(GlassButtonStyle())
                Menu {
                    Button { if let d = doc { Haptic.tap(); Exporter.pdf(d, name: opt.title) } } label: { Label("导出 PDF", systemImage: "doc.richtext") }
                    Button { if let d = doc { Haptic.tap(); Exporter.images(d, name: opt.title) } } label: { Label("导出图片（每页一张）", systemImage: "photo.on.rectangle") }
                } label: { Label("导出", systemImage: "square.and.arrow.up").lineLimit(1) }
                    .buttonStyle(GlassButtonStyle())
            }
            .disabled(doc == nil).opacity(doc == nil ? 0.5 : 1)
            Button { picking = true } label: { Label("写完了：拍照让 Max 检查", systemImage: "camera.viewfinder").lineLimit(1) }
                .buttonStyle(BrandButtonStyle(small: false))
                .disabled(doc == nil || checking).opacity(doc == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func build() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let ids = Array(selection).sorted()
            var all: [PItem] = []
            for chunk in stride(from: 0, to: ids.count, by: 50) {
                let part = ids[chunk..<min(chunk + 50, ids.count)].map(String.init).joined(separator: ",")
                let r = try await API.shared.obj("/api/print?ids=" + part)
                all += r.arr("items").map { PItem(subject: $0.str("subject"), topic: $0.str("topic"), stem: $0.str("stem"), type: $0.str("type"), tag: $0.str("tag"), explanation: $0.str("explanation"), options: $0.strs("options"), answer: $0.strs("answer")) }
            }
            doc = PDFMaker.make(all, opt)
            if doc == nil { error = "排版失败" }
        } catch { self.error = error.localizedDescription }
    }

    private func airPrint(_ d: PDFDocument) {
        guard let data = d.dataRepresentation() else { return }
        let pc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = opt.title; info.outputType = .general
        pc.printInfo = info; pc.printingItem = data
        pc.present(animated: true, completionHandler: nil)
    }

    /// 拍下写完的练习卷 → Max 转写作答、对照参考答案逐题批改
    private func check(_ img: UIImage) async {
        guard let d = ImageUtil.jpeg(img, maxSide: 1600, maxBytes: 1_900_000) else { error = "照片处理失败"; return }
        checking = true; error = nil
        defer { checking = false }
        do {
            let r = try await API.shared.obj("/api/max/check", method: "POST", json: ["ids": Array(selection).sorted(), "image": ImageUtil.dataURL(d)])
            report = CheckReport(report: r.str("report"), transcript: r.str("transcript"))
            Haptic.ok()
        } catch { self.error = error.localizedDescription; Haptic.bad() }
    }
}

struct CheckReport: Identifiable { let id = UUID(); let report: String; let transcript: String }

struct CheckReportView: View {
    let report: CheckReport
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var showTranscript = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) { MaxLogo(size: 24); Text("Max 的检查结果").font(.headline).foregroundStyle(Color.ink) }
                    Text(md(report.report)).foregroundStyle(Color.ink).lineSpacing(5).textSelection(.enabled).card()
                    DisclosureGroup("Max 看到的你的作答（转写）", isExpanded: $showTranscript) {
                        Text(plain(report.transcript)).font(.footnote).foregroundStyle(Color.mute).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                    .tint(Color.mute)
                    Text("转写来自照片，可能有识别错误；有疑问可以接着问 Max。").font(.caption).foregroundStyle(Color.mute)
                    Button("接着问 Max") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { router.ask("我刚做完一份练习卷，你检查的结果是：\n" + String(report.report.prefix(600)) + "\n帮我讲讲错的题该怎么改、最该先补什么。", study: true) } }
                        .buttonStyle(BrandButtonStyle(filled: true, small: false))
                }
                .padding(16)
            }
            .background(WarmBackground())
            .navigationTitle("检查结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct PDFFile: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
    }
}
