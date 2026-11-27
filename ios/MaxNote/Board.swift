import SwiftUI
import PencilKit
import UIKit

// 原生画板：PencilKit（手指或 Apple Pencil 都能画；系统工具盘有笔、荧光笔、橡皮、撤销重做、颜色），
// 背景按题型：函数 = 坐标系，作图 / 电路 / 光路 / 受力 = 方格，计算 / 解答 / 证明 = 横线纸。
enum BoardKind {
    case grid, coord, ruled, blank
    static func forTag(_ tag: String) -> BoardKind {
        switch tag {
        case "函数": return .coord
        case "计算", "解答", "证明", "简答": return .ruled
        default: return .grid
        }
    }
}

/// 要交给老师批改的画板题（画出来就是答案）；其余题的画板只是草稿纸
let drawnTags: Set<String> = ["作图", "函数", "电路", "光路", "受力", "证明"]
let boardSize = CGSize(width: 1100, height: 1500)

final class GridBackground: UIView {
    var kind: BoardKind = .grid { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .white; isOpaque = true }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        UIColor.white.setFill(); g.fill(bounds)
        let w = bounds.width, h = bounds.height
        let line = UIColor(red: 0.89, green: 0.86, blue: 0.80, alpha: 1)
        g.setStrokeColor(line.cgColor); g.setLineWidth(0.6)
        switch kind {
        case .grid, .coord:
            let s: CGFloat = 32
            var x: CGFloat = 0
            while x <= w { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: h)); x += s }
            var y: CGFloat = 0
            while y <= h { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: w, y: y)); y += s }
            g.strokePath()
            if kind == .coord {
                let ox = (w / 2 / s).rounded() * s, oy = (360 / s).rounded() * s
                g.setStrokeColor(UIColor(white: 0.25, alpha: 1).cgColor); g.setLineWidth(1.6)
                g.move(to: CGPoint(x: 8, y: oy)); g.addLine(to: CGPoint(x: w - 8, y: oy))
                g.move(to: CGPoint(x: ox, y: h - 8)); g.addLine(to: CGPoint(x: ox, y: 8)); g.strokePath()
                // 箭头
                g.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
                g.move(to: CGPoint(x: w - 8, y: oy)); g.addLine(to: CGPoint(x: w - 22, y: oy - 6)); g.addLine(to: CGPoint(x: w - 22, y: oy + 6)); g.fillPath()
                g.move(to: CGPoint(x: ox, y: 8)); g.addLine(to: CGPoint(x: ox - 6, y: 22)); g.addLine(to: CGPoint(x: ox + 6, y: 22)); g.fillPath()
                let font = UIFont.systemFont(ofSize: 11), attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 0.4, alpha: 1)]
                for k in -16...16 where k != 0 {
                    let tx = ox + CGFloat(k) * s
                    if tx > 20 && tx < w - 24 { ("\(k)" as NSString).draw(at: CGPoint(x: tx - 4, y: oy + 3), withAttributes: attrs) }
                }
                for k in -10...10 where k != 0 {
                    let ty = oy - CGFloat(k) * s
                    if ty > 24 && ty < h - 10 { ("\(k)" as NSString).draw(at: CGPoint(x: ox + 4, y: ty - 7), withAttributes: attrs) }
                }
                ("O" as NSString).draw(at: CGPoint(x: ox + 4, y: oy + 3), withAttributes: attrs)
                ("x" as NSString).draw(at: CGPoint(x: w - 20, y: oy + 6), withAttributes: attrs)
                ("y" as NSString).draw(at: CGPoint(x: ox + 8, y: 10), withAttributes: attrs)
            }
        case .ruled:
            let s: CGFloat = 44
            var y: CGFloat = s
            g.setStrokeColor(UIColor(red: 0.75, green: 0.82, blue: 0.92, alpha: 1).cgColor)
            while y <= h { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: w, y: y)); y += s }
            g.strokePath()
            g.setStrokeColor(UIColor(red: 0.92, green: 0.65, blue: 0.62, alpha: 1).cgColor)
            g.move(to: CGPoint(x: 56, y: 0)); g.addLine(to: CGPoint(x: 56, y: h)); g.strokePath()
        case .blank:
            break
        }
    }
}

/// 嵌在页面里的画布：大小跟着所在位置走（一个手指画、两个手指移动 / 缩放），背景是方格 / 坐标系 / 横线纸
final class InlineCanvas: PKCanvasView {
    let bg = GridBackground(frame: .zero)
    var onSize: ((CGSize) -> Void)?
    private var last = CGSize.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != last, bounds.width > 10 {
            last = bounds.size
            contentSize = bounds.size
            bg.frame = CGRect(origin: .zero, size: bounds.size)
            onSize?(bounds.size)
        }
    }
}

struct SketchCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let kind: BoardKind
    var onSize: ((CGSize) -> Void)? = nil
    var onTouch: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> InlineCanvas {
        let c = InlineCanvas()
        c.drawingPolicy = .anyInput
        c.overrideUserInterfaceStyle = .light // 墨水颜色和导出的图保持一致，不随深色模式反色
        c.backgroundColor = .clear
        c.isOpaque = false
        c.isScrollEnabled = false              // 嵌在题目里：页面自己滚动，画布只负责画
        c.bg.kind = kind
        c.onSize = onSize
        c.insertSubview(c.bg, at: 0)
        c.drawing = drawing
        c.delegate = context.coordinator
        let picker = PKToolPicker()
        context.coordinator.picker = picker
        picker.setVisible(true, forFirstResponder: c)
        picker.addObserver(c)
        DispatchQueue.main.async { c.becomeFirstResponder() }
        return c
    }

    func updateUIView(_ c: InlineCanvas, context: Context) {
        context.coordinator.parent = self
        if c.drawing != drawing { c.drawing = drawing }
        if c.bg.kind != kind { c.bg.kind = kind }
    }

    final class Coord: NSObject, PKCanvasViewDelegate {
        var parent: SketchCanvas
        var picker: PKToolPicker?
        init(_ p: SketchCanvas) { parent = p }
        func canvasViewDrawingDidChange(_ c: PKCanvasView) { parent.drawing = c.drawing }
        func canvasViewDidBeginUsingTool(_ c: PKCanvasView) { parent.onTouch?(true) }
        func canvasViewDidEndUsingTool(_ c: PKCanvasView) { parent.onTouch?(false) }
    }
}

enum BoardRender {
    /// 画板导出成图：full = 整张纸（自己看）；否则只裁出画了东西的部分（发给老师，小而清楚）
    static func image(_ d: PKDrawing, kind: BoardKind, full: Bool, size: CGSize = boardSize) -> UIImage? {
        guard !d.bounds.isEmpty else { return nil }
        let all = CGRect(origin: .zero, size: size)
        let rect = full ? all : d.bounds.insetBy(dx: -30, dy: -30).intersection(all)
        guard rect.width > 1, rect.height > 1 else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let r = UIGraphicsImageRenderer(size: rect.size, format: fmt)
        return r.image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: rect.size))
            let g = ctx.cgContext
            g.saveGState()
            g.translateBy(x: -rect.minX, y: -rect.minY)
            let bg = GridBackground(frame: all); bg.kind = kind
            bg.layer.setNeedsDisplay(); bg.layer.displayIfNeeded()
            bg.layer.render(in: g)
            g.restoreGState()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                d.image(from: rect, scale: 1).draw(in: CGRect(origin: .zero, size: rect.size))
            }
        }
    }
}

struct SketchSpec: Identifiable {
    let id = UUID()
    let idx: Int
    let title: String
    let kind: BoardKind
    let scratch: Bool
}

struct SketchBoard: View {
    let title: String
    let kind: BoardKind
    let scratch: Bool
    @Binding var drawing: PKDrawing
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            SketchCanvas(drawing: $drawing, kind: kind)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("清空", role: .destructive) { confirmClear = true } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
                .confirmationDialog("清空整张画板？", isPresented: $confirmClear, titleVisibility: .visible) { Button("清空", role: .destructive) { drawing = PKDrawing() } }
                .safeAreaInset(edge: .top) {
                    Text(scratch ? "草稿纸：不会交给老师" : "画出来的就是你的答案，交卷后交给 Claude 看图批改").font(.caption).foregroundStyle(Color.mute).padding(.vertical, 4).frame(maxWidth: .infinity).background(.ultraThinMaterial)
                }
        }
    }
}
