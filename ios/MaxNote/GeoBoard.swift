import SwiftUI

// 几何函数板 / 光学力学板 / 计算板手写：方格常驻、格点吸附、几何与函数作图。
// 图形坐标以「格」为单位（y 向上），原点在画板中心附近的格点。describe() 生成文字描述 + 算好的几何信息交给批改。
// 移植自网页版画板（board.js）。

typealias P2 = [Double]
let CELL: Double = 24

struct GObj: Equatable {
    var t: String
    var a: P2 = [0, 0]
    var b: P2 = [0, 0]
    var pts: [P2] = []
    var p: P2 = [0, 0]
    var s = ""
    var name = ""
    var expr = ""
    var c = "#111111"
    var w = 2.0
    var d = false
    var at: P2 = [0, 0]
    var u: P2 = [0, 0]
    var v: P2 = [0, 0]
}

struct ToolDef { let key: String; let name: String; let tip: String }
let ALL_TOOLS: [ToolDef] = [
    .init(key: "seg", name: "／线段", tip: "拖动画线段，两端吸附格点"),
    .init(key: "line", name: "⟷直线", tip: "拖出两点，自动延长到边缘"),
    .init(key: "ray", name: "↗射线", tip: "从端点拖向方向，延长到边缘"),
    .init(key: "circle", name: "◯圆", tip: "从圆心拖到圆上一点"),
    .init(key: "poly", name: "△多边形", tip: "依次点顶点，点回起点或按「完成」"),
    .init(key: "curve", name: "∿曲线", tip: "依次点经过的点，按「完成」连成平滑曲线"),
    .init(key: "point", name: "⊙标点", tip: "点一下放点：起名并自动标坐标，如 A(1,-4)"),
    .init(key: "text", name: "T文字", tip: "点一下，在那里打字"),
    .init(key: "perp", name: "⊥垂线", tip: "先点一个点，再点一条线"),
    .init(key: "para", name: "∥平行线", tip: "先点一条线，再点一个点"),
    .init(key: "pen", name: "✎画笔", tip: "自由手绘"),
    .init(key: "calc", name: "＝算式", tip: "点一下写算式出得数；方程、方程组（逗号隔开）、不等式自动解"),
    .init(key: "erase", name: "⌫橡皮", tip: "点或划过删除"),
    .init(key: "force", name: "力", tip: "从作用点拖向力的方向，松手起名（F、G、F浮…）"),
    .init(key: "light", name: "⇢光线", tip: "沿光的传播方向拖动，中间自动画箭头"),
    .init(key: "normal", name: "┆法线", tip: "拖动画法线（自动虚线）"),
    .init(key: "mirror", name: "▨平面镜", tip: "拖动画镜面：从左往右拖斜线在下方，反着拖换一面"),
    .init(key: "lens", name: "⇕凸透镜", tip: "拖动画凸透镜（一般竖着拖）"),
    .init(key: "lens2", name: "⇳凹透镜", tip: "拖动画凹透镜"),
]
let PHYS_NAME = ["force": "力", "light": "光线", "normal": "法线", "mirror": "平面镜", "lens": "凸透镜", "lens2": "凹透镜"]
let SEGS: Set<String> = ["seg", "force", "light", "normal", "mirror", "lens", "lens2"]
let GCOLORS = ["#111111", "#d64545", "#2f6fed"]

// ---------- 几何小工具 ----------
func dist(_ a: P2, _ b: P2) -> Double { hypot(a[0] - b[0], a[1] - b[1]) }
func lerp(_ a: P2, _ b: P2, _ k: Double) -> P2 { [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k] }
func proj(_ p: P2, _ a: P2, _ b: P2, _ kind: String) -> P2 {
    let dx = b[0] - a[0], dy = b[1] - a[1], L = dx * dx + dy * dy
    var k = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (L == 0 ? 1 : L)
    if kind == "seg" { k = min(1, max(0, k)) }
    if kind == "ray" { k = max(0, k) }
    return lerp(a, b, k)
}
func xy(_ p: P2) -> String { "(\(num1(p[0])),\(num1(p[1])))" }
func edges(_ o: GObj) -> [(P2, P2, String)] {
    if o.t == "poly" { return o.pts.enumerated().map { (i, q) in (q, o.pts[(i + 1) % o.pts.count], "seg") } }
    if o.t == "line" || o.t == "ray" { return [(o.a, o.b, o.t)] }
    if SEGS.contains(o.t) { return [(o.a, o.b, "seg")] }
    return []
}

struct AskReq: Identifiable { let id = UUID(); let title: String; let def: String; let done: (String) -> Void }

@MainActor
final class GeoBoard: ObservableObject {
    enum Mode { case geo, calc, phys }
    let mode: Mode
    @Published var objs: [GObj] = []
    @Published var tool: String
    @Published var color = "#111111"
    @Published var width = 2.0
    @Published var dash = false
    @Published var snap = true
    @Published var axes: Bool
    @Published var drag: GObj?
    @Published var tapAt: (P2, P2)?
    @Published var pendPts: [P2]?     // 多边形 / 曲线 正在点的顶点
    @Published var pendPoint: P2?     // 垂线：已选的点
    @Published var pendDir: P2?       // 平行线：已选的线方向
    @Published var hover: P2?
    @Published var ask: AskReq?
    @Published var message: String?
    private var hist: [[GObj]] = [], fut: [[GObj]] = []
    private var rub = false
    var ver = 0
    var size = CGSize(width: 360, height: 360) { didSet { relayout() } }
    private(set) var ox = 180.0, oy = 180.0
    private var fns: [String: ((Double) -> Double)?] = [:]

    init(mode: Mode = .geo, axes: Bool = false) {
        self.mode = mode
        self.axes = axes
        tool = mode == .calc ? "pen" : mode == .phys ? "force" : "seg"
    }

    var tools: [ToolDef] {
        switch mode {
        case .calc: return ["pen", "calc", "text", "erase"].compactMap { k in ALL_TOOLS.first { $0.key == k } }
        case .phys: return ["force", "light", "normal", "mirror", "lens", "lens2", "seg", "perp", "point", "text", "pen", "erase"].compactMap { k in ALL_TOOLS.first { $0.key == k } }
        case .geo: return ALL_TOOLS.filter { $0.key != "calc" && PHYS_NAME[$0.key] == nil }
        }
    }
    var tip: String {
        if pendPoint != nil { return "已选点，再点一条线" }
        if pendDir != nil { return "已选线，再点一个点" }
        return ALL_TOOLS.first { $0.key == tool }?.tip ?? ""
    }
    var isEmpty: Bool { objs.isEmpty }
    var hasPen: Bool { objs.contains { $0.t == "pen" } }

    private func relayout() {
        ox = (size.width / 2 / CELL).rounded() * CELL
        oy = (size.height / 2 / CELL).rounded() * CELL
    }
    func px(_ q: P2) -> CGPoint { CGPoint(x: ox + q[0] * CELL, y: oy - q[1] * CELL) }
    func at(_ loc: CGPoint) -> (P2, P2) {
        let raw: P2 = [((loc.x - ox) / CELL * 100).rounded() / 100, ((oy - loc.y) / CELL * 100).rounded() / 100]
        return (snap && tool != "pen" ? [raw[0].rounded(), raw[1].rounded()] : raw, raw)
    }

    // ---------- 历史 ----------
    private func change(_ f: () -> Void) {
        hist.append(objs); if hist.count > 50 { hist.removeFirst() }
        fut = []; f(); ver += 1
    }
    private func sty() -> (String, Double, Bool) { (color, width, dash) }
    private func add(_ o: GObj) { var o = o; (o.c, o.w, o.d) = sty(); change { objs.append(o) } }
    func undo() { if pendPts != nil || pendPoint != nil || pendDir != nil { reset(); return }; guard let l = hist.popLast() else { return }; fut.append(objs); objs = l; ver += 1 }
    func redo() { guard let l = fut.popLast() else { return }; hist.append(objs); objs = l; ver += 1 }
    func reset() { pendPts = nil; pendPoint = nil; pendDir = nil }
    func clear() { guard !objs.isEmpty else { return }; change { objs = [] } }
    func pick(_ k: String) { tool = k; reset() }

    // ---------- 交互 ----------
    func down(_ loc: CGPoint) {
        let (p, raw) = at(loc), t = tool
        if t == "erase" { rub = true; rubAt(raw); return }
        var o = GObj(t: t); (o.c, o.w, o.d) = sty()
        if t == "pen" { o.pts = [raw]; drag = o }
        else if ["line", "ray", "circle"].contains(t) || SEGS.contains(t) { o.a = p; o.b = p; drag = o }
        else { tapAt = (p, raw) }
    }
    func move(_ loc: CGPoint) {
        let (p, raw) = at(loc)
        if rub { rubAt(raw); return }
        if var d = drag { if d.t == "pen" { d.pts.append(raw) } else { d.b = p }; drag = d }
        else if tapAt != nil { tapAt = (p, raw) }
    }
    func up(_ loc: CGPoint) {
        let d = drag, tp = tapAt
        drag = nil; tapAt = nil; rub = false
        if let d = d, d.t == "force", dist(d.a, d.b) > 0.01 {
            let used = Set(objs.map { $0.name })
            let def = ["F", "G", "F1", "F2", "f", "F浮", "F支"].first { !used.contains($0) } ?? "F"
            ask = AskReq(title: "力的名称", def: def) { [self] name in var x = d; x.name = name; add(x) }
        } else if let d = d, d.t == "pen" ? d.pts.count > 1 : dist(d.a, d.b) > 0.01 { add(d) }
        else if let (p, raw) = tp { act(p, raw) }
    }
    func cancelTouch() { drag = nil; tapAt = nil; rub = false }

    private func rubAt(_ raw: P2) { if let i = hit(raw) { change { objs.remove(at: i) } } }

    private func act(_ p: P2, _ raw: P2) {
        let t = tool
        if t == "poly" || t == "curve" {
            if var pts = pendPts {
                if t == "poly", pts.count > 2, dist(p, pts[0]) < 0.4 { finish(); return }
                pts.append(p); pendPts = pts
            } else { pendPts = [p] }
        } else if t == "point" {
            let i = objs.firstIndex { $0.t == "pt" && dist($0.p, p) < 0.01 }
            let used = Set(objs.map { $0.name })
            let def = i.map { objs[$0].name } ?? (Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init).first { !used.contains($0) } ?? "")
            ask = AskReq(title: "点的名字（自动标坐标）", def: def) { [self] name in
                if let i = i { change { objs[i].name = name } } else { var o = GObj(t: "pt"); o.p = p; o.name = name; add(o) }
            }
        } else if t == "text" {
            ask = AskReq(title: "写点什么", def: "") { [self] s in if !s.isEmpty { var o = GObj(t: "text"); o.p = p; o.s = s; add(o) } }
        } else if t == "calc" {
            ask = AskReq(title: "算式或方程（如 x²-5x+6=0）", def: "") { [self] s in if !s.isEmpty { var o = GObj(t: "text"); o.p = p; o.s = calcText(s); add(o) } }
        } else if t == "perp" {
            guard let pd = pendPoint else { pendPoint = p; return }
            guard let L = lineAt(raw) else { message = "请点在一条线上"; return }
            let F = proj(pd, L.0, L.1, "line")
            pendPoint = nil
            if dist(pd, F) < 0.01 { message = "点在线上，换一个点"; return }
            let u = [L.1[0] - L.0[0], L.1[1] - L.0[1]], v = [pd[0] - F[0], pd[1] - F[1]], lu = hypot(u[0], u[1]), lv = hypot(v[0], v[1])
            var s1 = GObj(t: "seg"); s1.a = pd; s1.b = F; (s1.c, s1.w, s1.d) = sty()
            var ra = GObj(t: "ra"); ra.at = F; ra.u = [u[0] / lu, u[1] / lu]; ra.v = [v[0] / lv, v[1] / lv]; (ra.c, ra.w, ra.d) = (color, width, false)
            change { objs.append(s1); objs.append(ra) }
        } else if t == "para" {
            guard let dir = pendDir else {
                guard let L = lineAt(raw) else { message = "先点在一条线上"; return }
                pendDir = [L.1[0] - L.0[0], L.1[1] - L.0[1]]; return
            }
            pendDir = nil
            var o = GObj(t: "line"); o.a = p; o.b = [p[0] + dir[0], p[1] + dir[1]]; add(o)
        }
    }
    func finish() {
        guard let pts = pendPts else { return }
        pendPts = nil
        if pts.count > 1 { var o = GObj(t: tool); o.pts = pts; add(o) }
    }

    /// 计算板：把一行文字（算式结果）贴到画板上第一行空行
    func pasteLine(_ s: String) {
        var y = (oy / CELL).rounded(.down) - 1
        func frac(_ t: String) -> Bool { t.range(of: "\\d+/\\d+", options: .regularExpression) != nil }
        while y > -Double(size.height) / CELL, objs.contains(where: { $0.t == "text" && abs($0.p[1] - y) < (frac($0.s) || frac(s) ? 1.3 : 1) }) { y -= 1 }
        var o = GObj(t: "text"); o.p = [(-ox / CELL).rounded(.up) + 1, y]; o.s = s
        add(o)
    }

    func plot(_ src: String) {
        let e = src.trimmingCharacters(in: .whitespaces)
        let body = e.lowercased().hasPrefix("y=") ? String(e.dropFirst(2)).trimmingCharacters(in: .whitespaces) : e
        guard !body.isEmpty else { return }
        do { _ = try compileFn(body) } catch let err as FnErr { message = err.msg; return } catch { return }
        if !axes { axes = true }
        var o = GObj(t: "fn"); o.expr = "y = " + body; add(o)
    }
    func fn(_ expr: String) -> ((Double) -> Double)? {
        if let f = fns[expr] { return f }
        let f = try? compileFn(expr)
        fns[expr] = f
        return f
    }

    // ---------- 命中 ----------
    func hit(_ p: P2) -> Int? {
        var best: Int?, bd = 0.5
        for (i, o) in objs.enumerated() { let d = distTo(o, p); if d < bd { bd = d; best = i } }
        return best
    }
    func distTo(_ o: GObj, _ p: P2) -> Double {
        let E = edges(o)
        if !E.isEmpty { return E.map { dist(p, proj(p, $0.0, $0.1, $0.2)) }.min() ?? 9 }
        if o.t == "circle" { return abs(dist(p, o.a) - dist(o.a, o.b)) }
        if !o.pts.isEmpty { return o.pts.enumerated().map { (i, q) in i > 0 ? dist(p, proj(p, o.pts[i - 1], q, "seg")) : dist(p, q) }.min() ?? 9 }
        if o.t == "fn" { if let y = fn(o.expr)?(p[0]), y.isFinite { return abs(y - p[1]) }; return 9 }
        return dist(p, o.t == "ra" || o.t == "angle" ? o.at : o.p)
    }
    func lineAt(_ p: P2) -> (P2, P2)? {
        var best: (P2, P2)?, bd = 0.6
        for o in objs { for (a, b, k) in edges(o) { let d = dist(p, proj(p, a, b, k)); if d < bd { bd = d; best = (a, b) } } }
        return best
    }

    // ---------- 文字描述（交给批改：坐标单位=格；方程、截距、交点都算好）----------
    func describe() -> String {
        let col = ["#d64545": "红", "#2f6fed": "蓝"]
        func eq(_ a: P2, _ b: P2) -> String {
            if abs(a[0] - b[0]) < 1e-9 { return "x=\(num2(a[0]))" }
            let k = (b[1] - a[1]) / (b[0] - a[0]), m = a[1] - k * a[0]
            let kx = abs(k) < 1e-9 ? "" : "\(k == 1 ? "" : k == -1 ? "-" : num2(k))x"
            let ms = abs(m) < 1e-9 ? (kx.isEmpty ? "0" : "") : (m > 0 && !kx.isEmpty ? "+" : "") + num2(m)
            return "y=\(kx)\(ms)"
        }
        struct Ln { var a: P2; var b: P2; var k: String; var id: String }
        func on(_ L: Ln, _ q: P2) -> Bool { dist(q, proj(q, L.a, L.b, L.k)) < 1e-6 }
        func cross(_ L1: Ln, _ L2: Ln) -> P2? {
            let d1 = [L1.b[0] - L1.a[0], L1.b[1] - L1.a[1]], d2 = [L2.b[0] - L2.a[0], L2.b[1] - L2.a[1]], den = d1[0] * d2[1] - d1[1] * d2[0]
            if abs(den) < 1e-9 { return nil }
            let k = ((L2.a[0] - L1.a[0]) * d2[1] - (L2.a[1] - L1.a[1]) * d2[0]) / den, q = lerp(L1.a, L1.b, k)
            return on(L1, q) && on(L2, q) ? q : nil
        }
        func p2(_ q: P2) -> String { "(\(num2(q[0])),\(num2(q[1])))" }
        var lines: [Ln] = [], parts: [String] = []
        let items = objs.filter { $0.t != "pen" }
        for (i, o) in items.enumerated() {
            let id = "[\(i + 1)]", pre = (o.d ? "虚" : "") + (col[o.c] ?? "")
            var d = ""
            if let nm = PHYS_NAME[o.t] {
                d = o.t == "force" ? "\(pre)力\(o.name) 作用点\(xy(o.a)) 指向\(xy(o.b)) 长\(num2(dist(o.a, o.b)))格" : "\(pre)\(nm)\(xy(o.a))\(o.t == "light" ? "→" : "")\(xy(o.b))"
                if o.t == "light" {
                    for m in items where m.t == "mirror" {
                        for (end, other, nm2) in [(o.b, o.a, "入射角"), (o.a, o.b, "反射角")] {
                            if dist(end, proj(end, m.a, m.b, "seg")) > 1e-6 { continue }
                            let v = [other[0] - end[0], other[1] - end[1]], mv = [m.b[0] - m.a[0], m.b[1] - m.a[1]]
                            let cosv = abs(v[0] * mv[0] + v[1] * mv[1]) / hypot(v[0], v[1]) / hypot(mv[0], mv[1])
                            d += " \(nm2)≈\(Int((90 - acos(min(1, cosv)) * 180 / .pi).rounded()))°"
                        }
                    }
                }
            } else if ["seg", "line", "ray"].contains(o.t) {
                let L = Ln(a: o.a, b: o.b, k: o.t, id: id)
                lines.append(L)
                let name = o.t == "seg" ? "线段\(xy(o.a))\(xy(o.b))" : o.t == "line" ? "直线过\(xy(o.a))\(xy(o.b))" : "射线\(xy(o.a))→\(xy(o.b))"
                let ix = [[0.0, 1.0], [1.0, 0.0]].compactMap { cross(L, Ln(a: [0, 0], b: $0, k: "line", id: "")) }
                d = "\(pre)\(name) \(eq(o.a, o.b))" + (axes && !ix.isEmpty ? " 交轴\(ix.map(p2).joined())" : "")
            } else if o.t == "circle" { d = "\(pre)圆 心\(xy(o.a)) 半径\(num2(dist(o.a, o.b)))" }
            else if o.t == "poly" { d = "\(pre)多边形\(o.pts.map(xy).joined())" }
            else if o.t == "curve" { d = "\(pre)曲线过\(o.pts.map(xy).joined())" }
            else if o.t == "fn" { d = "函数 \(o.expr)" }
            else if o.t == "ra" { d = "直角@\(xy(o.at))" }
            else if o.t == "text" { d = "文字「\(o.s)」" + (mode == .calc ? "" : "@\(xy(o.p))") }
            else {
                let hosts = items.enumerated().filter { (j, h) in h != o && !["pt", "text", "ra"].contains(h.t) && distTo(h, o.p) < 0.05 }.map { "[\($0.offset + 1)]" }
                d = "点\(o.name)\(xy(o.p))\(hosts.isEmpty ? "" : "在" + hosts.joined() + "上")"
            }
            parts.append(id + d)
        }
        for i in 0..<lines.count { for j in (i + 1)..<max(i + 1, lines.count) { if let q = cross(lines[i], lines[j]) { parts.append("\(lines[i].id)∩\(lines[j].id)=\(p2(q))") } } }
        let pens = objs.count - items.count
        if pens > 0 { parts.append("手绘\(pens)笔") }
        return (axes ? "坐标轴；" : "") + parts.joined(separator: "；")
    }
}
