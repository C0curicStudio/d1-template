import SwiftUI

/// 画板作答的统一接口：几何函数板 / 光学力学板 / 电路图板 / 计算板
@MainActor
protocol BoardAnswer: AnyObject {
    var isEmpty: Bool { get }
    var hasPen: Bool { get }
    /// 交卷时的文字描述前缀（和网页版一致：[作图] / [电路] / [计算]）
    var tag: String { get }
    func describe() -> String
    func image(full: Bool) -> UIImage?
}

private func toolButton(_ title: String, on: Bool = false, _ action: @escaping () -> Void) -> some View {
    Button { Haptic.select(); action() } label: {
        Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : Color.ink)
            .background(on ? Color.brand : Color.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: on ? 0 : 0.6))
    }
    .buttonStyle(.plain)
}

extension GeoBoard: BoardAnswer {
    var tag: String { "[作图]" }

    func image(full: Bool) -> UIImage? {
        let sz = size
        guard sz.width > 10, sz.height > 10 else { return nil }
        let r = ImageRenderer(content: GeoCanvas(board: self, live: false).frame(width: sz.width, height: sz.height))
        r.scale = full ? 2 : 1
        guard let img = r.uiImage else { return nil }
        if full { return img }
        // 发给老师的小图：只裁出画了东西的区域
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func take(_ q: P2) { let p = px(q); minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        for o in objs {
            switch o.t {
            case "circle": let r = dist(o.a, o.b) * CELL, c = px(o.a); minX = min(minX, c.x - r); maxX = max(maxX, c.x + r); minY = min(minY, c.y - r); maxY = max(maxY, c.y + r)
            case "fn", "line", "ray": minX = 0; maxX = sz.width; minY = 0; maxY = sz.height
            default: ([o.a, o.b, o.p, o.at] + o.pts).forEach(take)
            }
        }
        guard minX.isFinite else { return img }
        let m = 36.0
        let rect = CGRect(x: max(0, minX - m), y: max(0, minY - m), width: 0, height: 0)
            .union(CGRect(x: min(sz.width, maxX + m), y: min(sz.height, maxY + m), width: 0, height: 0))
        let scale = img.scale
        guard let cg = img.cgImage?.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)) else { return img }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}

/// 几何函数板 / 光学力学板 / 计算板手写：画布 + 工具栏
struct GeoBoardPanel: View {
    @ObservedObject var board: GeoBoard
    var canvasHeight: CGFloat = 360
    @State private var started = false
    @State private var askText = ""
    @State private var plotAsk = false
    @State private var plotText = "y = "

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(board.tools, id: \.key) { t in toolButton(t.name, on: board.tool == t.key) { board.pick(t.key) } }
                    if board.mode == .geo { toolButton("𝑓函数") { plotText = "y = "; plotAsk = true } }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(GCOLORS, id: \.self) { c in
                        Button { board.color = c } label: { Circle().fill(Color(hex: c)).frame(width: 26, height: 26).overlay(Circle().strokeBorder(Color.brand, lineWidth: board.color == c ? 2.5 : 0).padding(-3)) }.buttonStyle(.plain)
                    }
                    toolButton(board.width > 2 ? "粗" : "细") { board.width = board.width > 2 ? 2 : 4 }
                    if board.mode != .calc {
                        toolButton("虚线", on: board.dash) { board.dash.toggle() }
                        toolButton("吸附格点", on: board.snap) { board.snap.toggle() }
                        if board.mode == .geo { toolButton("坐标轴", on: board.axes) { board.axes.toggle() } }
                    }
                    toolButton("清空") { board.clear() }
                }
            }
            HStack(spacing: 8) {
                Text(board.tip).font(.caption).foregroundStyle(Color.mute).lineLimit(2)
                Spacer(minLength: 4)
                if board.pendPts != nil { toolButton("完成", on: true) { board.finish() }; toolButton("取消") { board.reset() } }
                Button { board.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold)).frame(width: 36, height: 32) }.buttonStyle(.plain).foregroundStyle(Color.brand)
                Button { board.redo() } label: { Image(systemName: "arrow.uturn.forward").font(.body.weight(.semibold)).frame(width: 36, height: 32) }.buttonStyle(.plain).foregroundStyle(Color.brand)
            }
            GeoCanvas(board: board)
                .frame(maxWidth: .infinity).frame(height: canvasHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.8))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in if !started { started = true; board.down(v.location) } else { board.move(v.location) } }
                    .onEnded { v in started = false; board.up(v.location) })
        }
        .onChange(of: board.ask?.id) { _ in askText = board.ask?.def ?? "" }
        .alert(board.ask?.title ?? "", isPresented: Binding(get: { board.ask != nil }, set: { if !$0 { board.ask = nil } })) {
            TextField("", text: $askText)
            Button("确定") { let f = board.ask?.done; board.ask = nil; f?(askText.trimmingCharacters(in: .whitespaces)) }
            Button("取消", role: .cancel) { board.ask = nil }
        }
        .alert("函数解析式", isPresented: $plotAsk) {
            TextField("例如 y = x^2 - 2x - 3", text: $plotText)
            Button("画出来") { board.plot(plotText) }
            Button("取消", role: .cancel) {}
        } message: { Text("例如：y = x^2 - 2x - 3、y = 2x + 1、y = 6/x、y = sqrt(x)") }
        .alert("提示", isPresented: Binding(get: { board.message != nil }, set: { if !$0 { board.message = nil } })) { Button("好") { board.message = nil } } message: { Text(board.message ?? "") }
    }
}

extension Color {
    init(hex: String) {
        switch hex {
        case "#d64545": self = Color(red: 0.84, green: 0.27, blue: 0.27)
        case "#2f6fed": self = Color(red: 0.18, green: 0.44, blue: 0.93)
        default: self = Color(red: 0.07, green: 0.07, blue: 0.07)
        }
    }
}

// MARK: 计算板：横线纸手写 + 「＝算式」自动出得数 + 计算器 + 打字整理步骤
@MainActor
final class CalcBoard: ObservableObject, BoardAnswer {
    let pad = GeoBoard(mode: .calc)
    let subject: String
    @Published var steps: [String] = [""]
    @Published var expr = ""
    init(subject: String) { self.subject = subject }

    var tag: String { "[计算]" }
    var isEmpty: Bool { pad.isEmpty && !steps.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    var hasPen: Bool { !pad.isEmpty }
    func image(full: Bool) -> UIImage? { pad.image(full: full) }
    func describe() -> String {
        let st = steps.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.enumerated().map { "\($0.offset + 1)) \($0.element)" }
        return [pad.isEmpty ? "" : "画板：" + pad.describe(), st.isEmpty ? "" : "步骤：\n" + st.joined(separator: "\n")].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

private let PHYS_FORMULAS = ["v = s/t", "ρ = m/V", "G = mg", "p = F/S", "p = ρgh", "F浮 = ρ液gV排", "F浮 = G − F示", "W = Fs", "P = W/t", "P = Fv",
    "η = W有/W总", "F₁L₁ = F₂L₂", "Q = cmΔt", "Q = mq", "I = U/R", "P = UI", "W = UIt", "Q = I²Rt", "P = U²/R", "串：I = I₁ = I₂", "并：U = U₁ = U₂"]
private let CALC_KEYS = ["7", "8", "9", "÷", "(", ")", "4", "5", "6", "×", "√", "x²", "1", "2", "3", "−", "^", "π", "0", ".", "x", "+", "=", "⌫", "y", "，", "<", ">", "≥", "≤"]
private let SYMBOLS = ["÷", "×", "√", "²", "³", "^", "π", "°", "≠", "≈", "≤", "≥", "±", "∵", "∴", "⇒", "∠", "△", "⊥", "∥", "≌", "∽", "x₁", "x₂", "|", "%"]

struct CalcBoardPanel: View {
    @ObservedObject var calc: CalcBoard
    @State private var showCalc = false
    @State private var showForms = false
    @FocusState private var focusStep: Int?

    private var result: String {
        let v = calc.expr.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return "" }
        let r = calcText(v)
        return r == v ? "…" : String(r.dropFirst(v.count))
    }

    var body: some View {
        VStack(spacing: 10) {
            GeoBoardPanel(board: calc.pad, canvasHeight: 320)
            HStack(spacing: 8) {
                toolButton("计算器", on: showCalc) { showCalc.toggle() }
                if calc.subject == "物理" { toolButton("公式", on: showForms) { showForms.toggle() } }
                Spacer()
            }
            if showForms {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(PHYS_FORMULAS, id: \.self) { f in toolButton(f) { calc.pad.pasteLine(f) } } } }
            }
            if showCalc {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("x²-5x+6=0、2x+y=5，x-y=1、2x-1>3", text: $calc.expr).textInputAutocapitalization(.never).autocorrectionDisabled().padding(10).background(Color.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text(result.isEmpty ? " " : result).font(.body.weight(.semibold)).foregroundStyle(Color.brand).frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(CALC_KEYS, id: \.self) { k in
                            Button { put(k) } label: { Text(k).font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 36).background(Color.card, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).foregroundStyle(Color.ink)
                        }
                        Button { calc.expr = "" } label: { Text("C").frame(maxWidth: .infinity, minHeight: 36).background(Color.card, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).foregroundStyle(Color.brand)
                    }
                    Button("贴到画板") { let v = calc.expr.trimmingCharacters(in: .whitespaces); if !v.isEmpty { calc.pad.pasteLine(calcText(v)) } }.buttonStyle(BrandButtonStyle(filled: true))
                }
                .card(12)
            }
            // 打字整理步骤（交卷时是文字，批改更准更省）
            VStack(alignment: .leading, spacing: 8) {
                Text("打字整理步骤").font(.footnote.weight(.semibold)).foregroundStyle(Color.mute)
                ForEach(Array(calc.steps.indices), id: \.self) { i in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.footnote.weight(.bold)).foregroundStyle(Color.mute).frame(width: 18)
                        TextField("第 \(i + 1) 步", text: Binding(get: { calc.steps[i] }, set: { calc.steps[i] = $0 }), axis: .vertical)
                            .focused($focusStep, equals: i).padding(10).background(Color.card, in: RoundedRectangle(cornerRadius: 10))
                        Button { calc.steps.remove(at: i); if calc.steps.isEmpty { calc.steps = [""] } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.mute) }.buttonStyle(.plain)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(SYMBOLS, id: \.self) { s in toolButton(s) { insert(s) } } } }
                Button("＋ 下一步") { calc.steps.append(""); focusStep = calc.steps.count - 1 }.buttonStyle(BrandButtonStyle())
            }
        }
    }

    private func put(_ k: String) {
        switch k {
        case "⌫": if !calc.expr.isEmpty { calc.expr.removeLast() }
        case "√": calc.expr += "√("
        case "x²": calc.expr += "²"
        default: calc.expr += k
        }
    }
    private func insert(_ s: String) {
        let i = focusStep ?? max(0, calc.steps.count - 1)
        if calc.steps.indices.contains(i) { calc.steps[i] += s }
    }
}
