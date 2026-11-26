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

/// 打印流程：选题 → 版式 → 预览 → AirPrint / 蓝牙 / 分享 PDF
struct PrintFlow: View {
    let preselect: [Int]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bank = Feed("/api/bank")
    @StateObject private var wrong = Feed("/api/wrong?tab=active")
    @StateObject private var bt = BTPrinter()
    @State private var selection = Set<Int>()
    @State private var opt = PrintOptions()
    @State private var doc: PDFDocument?
    @State private var busy = false
    @State private var error: String?
    @State private var showPrinter = false
    @State private var source = 0

    private var items: [J] { (source == 0 ? bank : wrong).obj.arr("items") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("来源", selection: $source) { Text("题库").tag(0); Text("错题本").tag(1) }.pickerStyle(.segmented)
                    DisclosureGroup("选题（已选 \(selection.count) 题）") {
                        HStack {
                            Button("全选") { items.forEach { selection.insert($0.int("id")) } }
                            Spacer()
                            Button("清空") { selection.removeAll() }
                        }.font(.footnote)
                        ForEach(Array(items.enumerated()), id: \.offset) { _, q in
                            let id = q.int("id")
                            Button { Haptic.select(); if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selection.contains(id) ? Color.brand : .secondary)
                                    VStack(alignment: .leading) {
                                        Text(q.str("subject") + (q.str("topic").isEmpty ? "" : " › " + q.str("topic"))).font(.caption).foregroundStyle(.secondary)
                                        Text(plain(q.str("stem").replacingOccurrences(of: "^[^·]*·", with: "", options: .regularExpression))).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                } header: { Text("选题") }

                Section("版式") {
                    TextField("标题", text: $opt.title)
                    Picker("分栏", selection: $opt.cols) { Text("单栏").tag(1); Text("双栏").tag(2) }.pickerStyle(.segmented)
                    Picker("字号", selection: $opt.size) { Text("小").tag(1); Text("中").tag(2); Text("大").tag(3) }.pickerStyle(.segmented)
                    Picker("答案", selection: $opt.answers) { Text("不带").tag(0); Text("题后").tag(1); Text("末页").tag(2) }.pickerStyle(.segmented)
                    Picker("解答留白", selection: $opt.lines) { Text("不留").tag(0); Text("3 行").tag(3); Text("5 行").tag(5); Text("8 行").tag(8) }.pickerStyle(.segmented)
                    Toggle("姓名 / 日期栏", isOn: $opt.nameLine)
                }

                Section {
                    Button { Task { await build() } } label: { Label(busy ? "排版中…" : "生成 A4 预览", systemImage: "doc.text.magnifyingglass") }
                        .disabled(selection.isEmpty || busy)
                    if let e = error { Text(e).font(.footnote).foregroundStyle(Color.brand) }
                } footer: { Text("公式在打印稿里用文字形式，带题图的题在网页版打印排版里更完整。") }
            }
            .navigationTitle("A4 排版打印")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .navigationDestination(isPresented: Binding(get: { doc != nil }, set: { if !$0 { doc = nil } })) { if let d = doc { preview(d) } }
            .task {
                selection = Set(preselect)
                await bank.load(); await wrong.load()
            }
        }
        .sheet(isPresented: $showPrinter) { if let d = doc { PrinterSheet(pdf: d, bt: bt) } }
    }

    @ViewBuilder private func preview(_ d: PDFDocument) -> some View {
        PDFPreview(doc: d)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(d.pageCount) 页 A4")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if let data = d.dataRepresentation() {
                        ShareLink(item: PDFFile(data: data, name: opt.title), preview: SharePreview(opt.title + ".pdf")) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button { airPrint(d) } label: { Label("AirPrint", systemImage: "printer") }.buttonStyle(GlassButtonStyle(prominent: true))
                    Button { showPrinter = true } label: { Label("蓝牙打印机", systemImage: "dot.radiowaves.left.and.right") }.buttonStyle(GlassButtonStyle())
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
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
            guard let d = PDFMaker.make(all, opt) else { error = "排版失败"; return }
            doc = d
            Haptic.ok()
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
}

struct PDFFile: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
    }
}
