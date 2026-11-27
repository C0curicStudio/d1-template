import SwiftUI
import PDFKit

/// 导出：整份 PDF，或每一页一张图片（弹出系统分享面板：存到「文件」/ 存储图像到相册 / AirDrop / 发给别人）
enum Exporter {
    static func pdf(_ doc: PDFDocument, name: String) {
        guard let data = doc.dataRepresentation() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe(name) + ".pdf")
        do { try data.write(to: url, options: .atomic) } catch { return }
        share([url])
    }

    /// 每页渲染成 JPEG（约 150dpi 的 A4，清楚又不太大）
    static func images(_ doc: PDFDocument, name: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox), scale: CGFloat = 1240 / max(box.width, 1)
            let size = CGSize(width: box.width * scale, height: box.height * scale)
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                let g = ctx.cgContext
                g.translateBy(x: 0, y: size.height); g.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: g)
            }
            if let d = img.jpegData(compressionQuality: 0.9) {
                let u = dir.appendingPathComponent("\(safe(name))-\(i + 1).jpg")
                if (try? d.write(to: u)) != nil { files.append(u) }
            }
        }
        if !files.isEmpty { share(files) }
    }

    private static func safe(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "练习卷" : t
    }

    private static func share(_ items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let top = Web.top() else { return }
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 60, width: 1, height: 1)
        top.present(vc, animated: true)
    }
}
