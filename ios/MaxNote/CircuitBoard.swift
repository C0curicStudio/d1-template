import SwiftUI

// 电路图板（物理，初中）：拖动放元件、拖动连导线（自动折直角、自动画连接点），「通电」看哪盏灯亮、电表有无示数、短路、电表接反。
// 交卷时 describe() 给老师网表（各元件两端接哪个节点）+ 串并联 / 短路 / 断头提示 + 通电结果。移植自网页版电路板（circuit.js）。

let CC: Double = 28

struct PartDef { let key: String; let name: String; let prefix: String; let g: Double }
let PARTS: [PartDef] = [
    .init(key: "cell", name: "电源", prefix: "电源", g: 0), .init(key: "batt", name: "电池组", prefix: "电源", g: 0), .init(key: "sw", name: "开关", prefix: "S", g: 0),
    .init(key: "lamp", name: "灯泡", prefix: "L", g: 0.1), .init(key: "res", name: "定值电阻", prefix: "R", g: 0.1), .init(key: "rheo", name: "滑动变阻器", prefix: "R′", g: 0.05),
    .init(key: "am", name: "电流表", prefix: "A", g: 1e3), .init(key: "vm", name: "电压表", prefix: "V", g: 0), .init(key: "motor", name: "电动机", prefix: "M", g: 0.1),
    .init(key: "bell", name: "电铃", prefix: "电铃", g: 0.1), .init(key: "led", name: "发光二极管", prefix: "LED", g: 0.1), .init(key: "fuse", name: "保险丝", prefix: "FU", g: 1e3),
]
private func part(_ k: String) -> PartDef? { PARTS.first { $0.key == k } }
private let SRC: Set<String> = ["cell", "batt"]
private let CTOOLS: [(String, String, String)] = [
    ("wire", "〰导线", "从一个格点拖到另一个格点；不在一条线上会自动折成直角"),
    ("flip", "⇄翻转", "点电源/电表/LED 换正负方向；点开关切换断开/闭合"),
    ("name", "✎改名", "点元件改编号，如 L1、R2"),
    ("text", "T文字", "点一下写字，如滑片端 a、b"),
    ("erase", "⌫橡皮", "点一下删除元件或导线"),
]

struct CObj: Equatable {
    var t: String
    var a: P2 = [0, 0]
    var b: P2 = [0, 0]
    var pts: [P2] = []
    var p: P2 = [0, 0]
    var s = ""
    var name = ""
    var on = false
}

private func gauss(_ A0: [[Double]]) -> [Double] {
    var A = A0
    let n = A.count
    for i in 0..<n {
        var p = i
        for r in (i + 1)..<max(i + 1, n) where abs(A[r][i]) > abs(A[p][i]) { p = r }
        A.swapAt(i, p)
        if abs(A[i][i]) < 1e-15 { continue }
        for r in 0..<n where r != i {
            let f = A[r][i] / A[i][i]
            if f != 0 { for c in i...n { A[r][c] -= f * A[i][c] } }
        }
    }
    return A.enumerated().map { (i, row) in abs(row[i]) < 1e-15 ? 0 : row[n] / row[i] }
}

@MainActor
final class CircuitBoard: ObservableObject, BoardAnswer {
    @Published var objs: [CObj] = []
    @Published var tool = "wire"
    @Published var check = false
    @Published var drag: (P2, P2)?
    @Published var ask: AskReq?
    private var hist: [[CObj]] = [], fut: [[CObj]] = []
    var size = CGSize(width: 360, height: 360)

    var tag: String { "[电路]" }
    var isEmpty: Bool { objs.isEmpty }
    var hasPen: Bool { false }
    var tip: String { check ? "通电中：点开关可直接通断" : (part(tool).map { "拖动放\($0.name)（两端吸附格点），点一下默认横放" } ?? CTOOLS.first { $0.0 == tool }?.2 ?? "") }

    func px(_ q: P2) -> CGPoint { CGPoint(x: CC / 2 + q[0] * CC, y: CC / 2 + q[1] * CC) }
    func at(_ loc: CGPoint) -> (P2, P2) {
        let raw: P2 = [(Double(loc.x) - CC / 2) / CC, (Double(loc.y) - CC / 2) / CC]
        return ([raw[0].rounded(), raw[1].rounded()], raw)
    }

    private func change(_ f: () -> Void) { hist.append(objs); if hist.count > 50 { hist.removeFirst() }; fut = []; f() }
    func undo() { guard let l = hist.popLast() else { return }; fut.append(objs); objs = l }
    func redo() { guard let l = fut.popLast() else { return }; hist.append(objs); objs = l }
    func clear() { guard !objs.isEmpty else { return }; change { objs = [] } }

    /// 元件只能横放或竖放，至少 2 格长
    func place(_ a: P2, _ b: P2) -> P2 {
        var d = [b[0] - a[0], b[1] - a[1]]
        if d[0] == 0 && d[1] == 0 { d = [2, 0] }
        let ax = abs(d[0]) >= abs(d[1]) ? 0 : 1
        let len = max(2, abs(d[ax])) * (d[ax] < 0 ? -1 : 1)
        var e = a; e[ax] += len
        return e
    }
    func route(_ a: P2, _ b: P2) -> [P2] { a[0] == b[0] || a[1] == b[1] ? [a, b] : [a, [b[0], a[1]], b] }

    // ---------- 交互 ----------
    func down(_ loc: CGPoint) {
        let (p, raw) = at(loc), i = hit(raw)
        if check, let i = i, objs[i].t == "sw" { toggle(i); return }
        if ["erase", "flip", "name", "text"].contains(tool) { tapAct(p, raw); return }
        drag = (p, p)
    }
    func move(_ loc: CGPoint) { if let d = drag { drag = (d.0, at(loc).0) } }
    func up(_ loc: CGPoint) {
        guard let d = drag else { return }
        drag = nil
        if tool == "wire" { if dist(d.0, d.1) > 0 { change { objs.append({ var w = CObj(t: "wire"); w.pts = route(d.0, d.1); return w }()) } }; return }
        guard let pd = part(tool) else { return }
        let used = Set(objs.map { $0.name })
        var n = 1
        var name = pd.prefix.count == 1 && pd.prefix.first!.isUppercase ? pd.prefix + "1" : pd.prefix
        while used.contains(name) { n += 1; name = pd.prefix + String(n) }
        var o = CObj(t: tool); o.a = d.0; o.b = place(d.0, d.1); o.name = name
        change { objs.append(o) }
    }
    func cancelTouch() { drag = nil }

    private func toggle(_ i: Int) { change { objs[i].on.toggle() } }
    private func tapAct(_ p: P2, _ raw: P2) {
        if tool == "text" { ask = AskReq(title: "写点什么（如滑片端 a、b）", def: "") { [self] s in if !s.isEmpty { var o = CObj(t: "text"); o.p = p; o.s = s; change { objs.append(o) } } }; return }
        guard let i = hit(raw) else { return }
        let o = objs[i]
        if tool == "erase" { change { objs.remove(at: i) } }
        else if tool == "flip" && o.t == "sw" { toggle(i) }
        else if tool == "flip" && part(o.t) != nil { change { let x = objs[i].a; objs[i].a = objs[i].b; objs[i].b = x } }
        else if tool == "name" && part(o.t) != nil { ask = AskReq(title: "元件编号（如 L1、R2）", def: o.name) { [self] s in if !s.isEmpty { change { objs[i].name = s } } } }
    }

    func segs(_ o: CObj) -> [(P2, P2)] {
        if o.t == "wire" { return o.pts.dropFirst().enumerated().map { (i, q) in (o.pts[i], q) } }
        if part(o.t) != nil { return [(o.a, o.b)] }
        return []
    }
    func hit(_ p: P2) -> Int? {
        var best: Int?, bd = 0.45
        for (i, o) in objs.enumerated() {
            let d = o.t == "text" ? dist(p, o.p) : min(9, segs(o).map { dist(p, proj(p, $0.0, $0.1, "seg")) }.min() ?? 9)
            if d <= bd { bd = d; best = i }
        }
        return best
    }

    // ---------- 网表：导线连通的格点并成一个节点；导线端点落在另一根导线中间也算连上（T 形接头），单纯交叉不算 ----------
    struct Nets { let parts: [CObj]; let of: (P2) -> Int; let deg: [String: Int] }
    func nets() -> Nets {
        var par: [String: String] = [:]
        func key(_ q: P2) -> String { "\(Int(q[0])),\(Int(q[1]))" }
        func find(_ k0: String) -> String { var k = k0; while par[k] != k { par[k] = par[par[k]!]; k = par[k]! }; return k }
        func add(_ k: String) { if par[k] == nil { par[k] = k } }
        func join(_ a: String, _ b: String) { add(a); add(b); par[find(a)] = find(b) }
        let wires = objs.filter { $0.t == "wire" }, ps = objs.filter { part($0.t) != nil }
        let ends = wires.flatMap { [$0.pts.first!, $0.pts.last!] } + ps.flatMap { [$0.a, $0.b] }
        ends.forEach { add(key($0)) }
        for w in wires { for (a, b) in segs(w) {
            join(key(a), key(b))
            for q in ends where dist(q, proj(q, a, b, "seg")) < 1e-9 { join(key(q), key(a)) }
        } }
        var ids: [String: Int] = [:]
        let of: (P2) -> Int = { q in let r = find(key(q)); if ids[r] == nil { ids[r] = ids.count + 1 }; return ids[r]! }
        var deg: [String: Int] = [:]
        for w in wires { for (a, b) in segs(w) { for q in [a, b] { deg[key(q), default: 0] += 1 } } }
        for o in ps { for q in [o.a, o.b] { deg[key(q), default: 0] += 1 } }
        for q in ends { for w in wires { for (a, b) in segs(w) where dist(q, a) > 1e-9 && dist(q, b) > 1e-9 && dist(q, proj(q, a, b, "seg")) < 1e-9 { deg[key(q), default: 0] += 2 } } }
        return Nets(parts: ps, of: of, deg: deg)
    }

    func describe() -> String {
        let n = nets()
        let ps = n.parts
        let N = ps.map { [n.of($0.a), n.of($0.b)] }
        var out: [String] = []
        for (i, o) in ps.enumerated() {
            let x = N[i][0], y = N[i][1], nm = part(o.t)?.name ?? ""
            if SRC.contains(o.t) { out.append("\(o.name)\(o.t == "batt" ? "(电池组)" : "")(正极→节点\(x)，负极→节点\(y))") }
            else if ["led", "am", "vm"].contains(o.t) { out.append("\(o.name)\(nm)(+→节点\(x)，−→节点\(y))") }
            else { out.append("\(o.name)\(nm)\(o.t == "sw" ? (o.on ? "(闭合)" : "(断开)") : "")(节点\(x)-\(y))") }
        }
        var notes: [String] = []
        var same: [String: [String]] = [:]
        for (i, xy) in N.enumerated() {
            if xy[0] == xy[1] { notes.append("\(ps[i].name)两端被导线直接连通（短接）") }
            else { same[xy.sorted().map(String.init).joined(separator: "-"), default: []].append(ps[i].name) }
        }
        for (k, v) in same.sorted(by: { $0.key < $1.key }) where v.count > 1 { notes.append("\(v.joined(separator: "、"))都接在节点\(k)之间（并联）") }
        var cnt: [Int: Int] = [:]
        N.flatMap { $0 }.forEach { cnt[$0, default: 0] += 1 }
        for (k, c) in cnt.sorted(by: { $0.key < $1.key }) where c == 1 { notes.append("节点\(k)只接了一个元件（断头）") }
        let texts = objs.filter { $0.t == "text" }.map { "文字「\($0.s)」" }
        let sim = simulate()
        return "电路图：\(out.joined(separator: "；"))" + (notes.isEmpty ? "" : "｜提示：\(notes.joined(separator: "；"))") + (sim.map { "｜通电：\($0.text)" } ?? "") + (texts.isEmpty ? "" : "｜\(texts.joined())")
    }

    // ---------- 通电仿真：节点电压法（MNA）。只给定性结果：灯亮不亮、电表有无示数、短路、电表接反 ----------
    struct Sim { var info: [Int: String]; var text: String }
    func simulate() -> Sim? {
        let nt = nets(), ps = nt.parts
        let cells = ps.filter { SRC.contains($0.t) }
        guard !cells.isEmpty else { return nil }
        let N = ps.map { [nt.of($0.a), nt.of($0.b)] }
        let n = N.flatMap { $0 }.max() ?? 1
        let firstIdx = ps.firstIndex { SRC.contains($0.t) } ?? 0
        let gnd = N[firstIdx][1]
        func ix(_ k: Int) -> Int { k == gnd ? -1 : (k < gnd ? k - 1 : k - 2) }
        let size = n - 1 + cells.count
        var off = Set<Int>()
        var V: [Double] = [], I: [Double] = []
        for _ in 0..<3 {
            var A = Array(repeating: Array(repeating: 0.0, count: size + 1), count: size)
            for i in 0..<max(0, n - 1) { A[i][i] += 1e-9 }
            func g(_ o: CObj, _ k: Int) -> Double { o.t == "sw" ? (o.on ? 1e3 : 0) : off.contains(k) ? 0 : (part(o.t)?.g ?? 0) }
            for (k, o) in ps.enumerated() where !SRC.contains(o.t) {
                let i = ix(N[k][0]), j = ix(N[k][1]), G = g(o, k)
                if i >= 0 { A[i][i] += G }; if j >= 0 { A[j][j] += G }
                if i >= 0 && j >= 0 { A[i][j] -= G; A[j][i] -= G }
            }
            for (m, o) in cells.enumerated() {
                let r = n - 1 + m, p = ix(nt.of(o.a)), q = ix(nt.of(o.b))
                if p == q { A[r][r] = 1; continue }
                if p >= 0 { A[p][r] += 1; A[r][p] += 1 }
                if q >= 0 { A[q][r] -= 1; A[r][q] -= 1 }
                A[r][size] = 3
            }
            let x = gauss(A)
            func v(_ k: Int) -> Double { ix(k) < 0 ? 0 : x[ix(k)] }
            V = N.map { v($0[0]) - v($0[1]) }
            I = ps.enumerated().map { (k, o) in SRC.contains(o.t) ? -x[n - 1 + (cells.firstIndex(of: o) ?? 0)] : V[k] * g(o, k) }
            if let rev = ps.enumerated().first(where: { (k, o) in o.t == "led" && !off.contains(k) && I[k] < -1e-6 })?.offset { off.insert(rev) } else { break }
        }
        var info: [Int: String] = [:]
        var words: [String] = []
        for (k, o) in ps.enumerated() {
            let on = abs(I[k]) > 1e-3
            var s = ""
            if SRC.contains(o.t) { s = (nt.of(o.a) == nt.of(o.b) || abs(I[k]) > 5) ? "short" : "" }
            else if o.t == "am" { s = on ? (I[k] < 0 ? "rev" : "on") : "" }
            else if o.t == "vm" { s = abs(V[k]) > 0.05 ? (V[k] < 0 ? "rev" : "on") : "" }
            else { s = on ? "on" : "" }
            info[k] = s
            func say(_ t: String, _ s: String) -> String? {
                let on = !s.isEmpty
                switch t { case "lamp", "led": return on ? "亮" : "不亮"; case "motor": return on ? "转" : "不转"; case "bell": return on ? "响" : "不响"; case "am", "vm": return on ? "有示数" : "无示数"; default: return nil }
            }
            if SRC.contains(o.t) { if s == "short" { words.append("注意：\(o.name)短路") } }
            else if let w = say(o.t, s) { words.append(o.name + w + (s == "rev" ? "（正负接线柱接反）" : "")) }
        }
        return Sim(info: info, text: words.isEmpty ? "无电流" : words.joined(separator: " "))
    }

    func image(full: Bool) -> UIImage? {
        let r = ImageRenderer(content: CircuitCanvas(board: self, live: false).frame(width: size.width, height: size.height))
        r.scale = full ? 2 : 1.2
        return r.uiImage
    }
}

// MARK: 绘制
struct CircuitCanvas: View {
    @ObservedObject var board: CircuitBoard
    var live = true

    var body: some View { Canvas { ctx, size in paint(&ctx, size) } }

    private func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let b = board
        if b.size != size { DispatchQueue.main.async { b.size = size } }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
        var x = CC / 2
        while x < Double(size.width) { var y = CC / 2; while y < Double(size.height) { ctx.fill(Path(CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Color(red: 0.81, green: 0.84, blue: 0.87))); y += CC }; x += CC }
        let sim = b.check ? b.simulate() : nil
        var list = b.objs
        if live, let d = b.drag {
            if b.tool == "wire" { var w = CObj(t: "wire"); w.pts = b.route(d.0, d.1); list.append(w) }
            else { var o = CObj(t: b.tool); o.a = d.0; o.b = b.place(d.0, d.1); list.append(o) }
        }
        let parts = b.nets().parts
        for o in list {
            let idx = parts.firstIndex(of: o)
            drawObj(&ctx, o, st: idx.flatMap { sim?.info[$0] }, A: nil, B: nil)
        }
        for (k, n) in b.nets().deg where n >= 3 {
            let q = k.split(separator: ",").map { Double($0) ?? 0 }
            let c = b.px(q)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(.black))
        }
        guard live else { return }
        if let d = b.drag {
            let c = b.px(d.1)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(Color(red: 0.18, green: 0.44, blue: 0.93)), lineWidth: 1.5)
            let a = b.px(d.0)
            ctx.fill(Path(ellipseIn: CGRect(x: a.x - 3, y: a.y - 3, width: 6, height: 6)), with: .color(Color(red: 0.18, green: 0.44, blue: 0.93)))
        }
        if let s = sim { ctx.draw(Text(s.text).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(red: 0.88, green: 0.54, blue: 0)), at: CGPoint(x: 8, y: size.height - 8), anchor: .bottomLeading) }
        else if b.check { ctx.draw(Text("先放一个电源").font(.system(size: 12)).foregroundColor(.gray), at: CGPoint(x: 8, y: size.height - 8), anchor: .bottomLeading) }
    }

    /// 元件符号；A、B 给定时画在指定像素位置（工具栏图标用）
    func drawObj(_ ctx: inout GraphicsContext, _ o: CObj, st: String?, A pa: CGPoint?, B pb: CGPoint?) {
        let ink: Color = st == "short" || st == "rev" ? Color(red: 0.84, green: 0.27, blue: 0.27) : st == "on" ? Color(red: 0.88, green: 0.54, blue: 0) : .black
        func line(_ pts: [CGPoint], w: Double = 2) {
            var p = Path()
            for (i, q) in pts.enumerated() { i == 0 ? p.move(to: q) : p.addLine(to: q) }
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        if o.t == "wire" { line(o.pts.map { board.px($0) }); return }
        if o.t == "text" { ctx.draw(Text(o.s).font(.system(size: 16, design: .serif)).italic().foregroundColor(ink), at: board.px(o.p), anchor: .leading); return }
        let A = pa ?? board.px(o.a), B = pb ?? board.px(o.b)
        let L = hypot(B.x - A.x, B.y - A.y)
        guard L > 0 else { return }
        if st == "on" && o.t == "lamp" {
            let m = CGPoint(x: (A.x + B.x) / 2, y: (A.y + B.y) / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 20, y: m.y - 20, width: 40, height: 40)), with: .color(Color(red: 1, green: 0.78, blue: 0).opacity(0.45)))
        }
        let u = CGPoint(x: (B.x - A.x) / L, y: (B.y - A.y) / L), n = CGPoint(x: -u.y, y: u.x)
        let M = CGPoint(x: (A.x + B.x) / 2, y: (A.y + B.y) / 2)
        func P(_ s: CGFloat, _ t: CGFloat = 0) -> CGPoint { CGPoint(x: M.x + u.x * s + n.x * t, y: M.y + u.y * s + n.y * t) }
        let hmap: [String: CGFloat] = ["cell": 4, "batt": 12, "sw": 18, "led": 9, "res": 14, "rheo": 14, "fuse": 14]
        let h = hmap[o.t] ?? 12, r: CGFloat = 12
        line([A, P(-h)]); line([P(h), B])
        func poly(_ pts: [CGPoint]) {
            var p = Path()
            for (i, q) in pts.enumerated() { i == 0 ? p.move(to: q) : p.addLine(to: q) }
            p.closeSubpath()
            ctx.fill(p, with: .color(.white)); ctx.stroke(p, with: .color(ink), lineWidth: 2)
        }
        func plus(_ q: CGPoint) { ctx.draw(Text("+").font(.system(size: 12)).foregroundColor(ink), at: q, anchor: .center) }
        func circ(_ s: String?) {
            let c = Path(ellipseIn: CGRect(x: M.x - r, y: M.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(c, with: .color(st == "on" && o.t == "lamp" ? Color(red: 1, green: 0.95, blue: 0.69) : .white)); ctx.stroke(c, with: .color(ink), lineWidth: 2)
            if let s = s { ctx.draw(Text(s).font(.system(size: 14, weight: .bold)).foregroundColor(ink), at: M, anchor: .center) }
        }
        switch o.t {
        case "cell": line([P(-4, -13), P(-4, 13)]); line([P(4, -7), P(4, 7)], w: 4); plus(P(-12, -12))
        case "batt":
            for s0: CGFloat in [-12, 4] { line([P(s0, -13), P(s0, 13)]); line([P(s0 + 8, -7), P(s0 + 8, 7)], w: 4) }
            plus(P(-18, -12))
        case "fuse": poly([P(-14, -5), P(14, -5), P(14, 5), P(-14, 5)]); line([P(-14), P(14)])
        case "sw":
            for q in [P(-h), P(h)] { ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)), with: .color(ink)) }
            line([P(-h), o.on ? P(h) : P(h - 3, -13)])
        case "lamp": circ(nil); line([P(-8.5, -8.5), P(8.5, 8.5)]); line([P(-8.5, 8.5), P(8.5, -8.5)])
        case "res", "rheo":
            poly([P(-14, -6), P(14, -6), P(14, 6), P(-14, 6)])
            if o.t == "rheo" { line([P(-12, 11), P(12, -13)]); line([P(5, -12), P(12, -13), P(11, -6)]) }
        case "am": circ("A"); plus(P(-16, -10))
        case "vm": circ("V"); plus(P(-16, -10))
        case "motor": circ("M")
        case "bell": poly((0...12).map { i in P(-12 * CGFloat(cos(Double(i) * .pi / 12)), -12 * CGFloat(sin(Double(i) * .pi / 12))) })
        case "led": poly([P(-h, -8), P(-h, 8), P(h, 0)]); line([P(h, -8), P(h, 8)]); line([P(2, -10), P(8, -17)]); line([P(7, -9), P(13, -16)])
        default: break
        }
        if !o.name.isEmpty && pa == nil {
            ctx.draw(Text(o.name).font(.system(size: 14, design: .serif)).italic().foregroundColor(Color(red: 0.84, green: 0.27, blue: 0.27)), at: CGPoint(x: M.x + (u.x != 0 ? 0 : 24), y: M.y + (u.x != 0 ? 24 : 0)), anchor: .center)
        }
    }
}

/// 元件工具栏里的小符号
struct PartIcon: View {
    let key: String
    @ObservedObject var board: CircuitBoard
    var body: some View {
        Canvas { ctx, _ in
            var o = CObj(t: key); o.on = true
            CircuitCanvas(board: board, live: false).drawObj(&ctx, o, st: nil, A: CGPoint(x: 4, y: 18), B: CGPoint(x: 86, y: 18))
        }
        .frame(width: 90, height: 36)
    }
}

struct CircuitBoardPanel: View {
    @ObservedObject var board: CircuitBoard
    var canvasHeight: CGFloat = 360
    var onTouch: ((Bool) -> Void)? = nil
    @State private var started = false
    @State private var askText = ""

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PARTS, id: \.key) { p in
                        Button { Haptic.select(); board.tool = p.key } label: {
                            VStack(spacing: 0) { PartIcon(key: p.key, board: board); Text(p.name).font(.caption2).foregroundStyle(board.tool == p.key ? Color.white : Color.ink) }
                                .padding(.horizontal, 6).padding(.vertical, 4)
                                .background(board.tool == p.key ? Color.brand : Color.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CTOOLS, id: \.0) { t in chip(t.1, on: board.tool == t.0) { board.tool = t.0 } }
                    chip("通电", on: board.check) { board.check.toggle() }
                    chip("清空") { board.clear() }
                }
            }
            HStack(spacing: 8) {
                Text(board.tip).font(.caption).foregroundStyle(Color.mute).lineLimit(2)
                Spacer(minLength: 4)
                Button { board.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold)).frame(width: 36, height: 32) }.buttonStyle(.plain).foregroundStyle(Color.brand)
                Button { board.redo() } label: { Image(systemName: "arrow.uturn.forward").font(.body.weight(.semibold)).frame(width: 36, height: 32) }.buttonStyle(.plain).foregroundStyle(Color.brand)
            }
            CircuitCanvas(board: board)
                .frame(maxWidth: .infinity).frame(height: canvasHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.8))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in if !started { started = true; onTouch?(true); board.down(v.location) } else { board.move(v.location) } }
                    .onEnded { v in started = false; board.up(v.location); onTouch?(false) })
        }
        .onChange(of: board.ask?.id) { _ in askText = board.ask?.def ?? "" }
        .alert(board.ask?.title ?? "", isPresented: Binding(get: { board.ask != nil }, set: { if !$0 { board.ask = nil } })) {
            TextField("", text: $askText)
            Button("确定") { let f = board.ask?.done; board.ask = nil; f?(askText.trimmingCharacters(in: .whitespaces)) }
            Button("取消", role: .cancel) { board.ask = nil }
        }
    }

    private func chip(_ title: String, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { Haptic.select(); action() } label: {
            Text(title).font(.footnote.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : Color.ink)
                .background(on ? Color.brand : Color.card, in: Capsule()).overlay(Capsule().strokeBorder(Color.hairline, lineWidth: on ? 0 : 0.6))
        }.buttonStyle(.plain)
    }
}
