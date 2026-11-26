import SwiftUI

private func gcol(_ hex: String) -> Color {
    switch hex {
    case "#d64545": return Color(red: 0.84, green: 0.27, blue: 0.27)
    case "#2f6fed": return Color(red: 0.18, green: 0.44, blue: 0.93)
    default: return Color(red: 0.07, green: 0.07, blue: 0.07)
    }
}

/// 画板的绘制（交互时和导出图片时共用）
struct GeoCanvas: View {
    @ObservedObject var board: GeoBoard
    var live = true

    var body: some View {
        Canvas { ctx, size in paint(&ctx, size) }
    }

    private func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, _ w: Double, dash: Bool = false) {
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: dash ? [7, 6] : []))
    }

    private func text(_ ctx: inout GraphicsContext, _ s: String, _ at: CGPoint, size: CGFloat = 15, italic: Bool = false, color: Color = .black, anchor: UnitPoint = .bottomLeading, halo: Bool = false) {
        var t = Text(s).font(.system(size: size, design: italic ? .serif : .default))
        if italic { t = t.italic() }
        if halo { ctx.draw(Text(s).font(.system(size: size, design: italic ? .serif : .default)).foregroundColor(.white), at: CGPoint(x: at.x + 1, y: at.y + 1), anchor: anchor) }
        ctx.draw(t.foregroundColor(color), at: at, anchor: anchor)
    }

    private func dot(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    private func head(_ ctx: inout GraphicsContext, tip: CGPoint, from: CGPoint, color: Color, lw: Double) {
        let k = atan2(tip.y - from.y, tip.x - from.x), s = 7 + lw
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - s * cos(k - 0.4), y: tip.y - s * sin(k - 0.4)))
        p.addLine(to: CGPoint(x: tip.x - s * cos(k + 0.4), y: tip.y - s * sin(k + 0.4)))
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    private func arrowLine(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, head0: Bool, head1: Bool, color: Color, lw: Double) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        stroke(&ctx, p, color, lw)
        if head0 { head(&ctx, tip: a, from: b, color: color, lw: lw) }
        if head1 { head(&ctx, tip: b, from: a, color: color, lw: lw) }
    }

    /// 直线 / 射线裁到画板边缘
    private func clip(_ a: CGPoint, _ b: CGPoint, ray: Bool, _ size: CGSize) -> (CGPoint, CGPoint)? {
        let d = [Double(b.x - a.x), Double(b.y - a.y)], m = 3.0
        var k0 = ray ? 0.0 : -Double.infinity, k1 = Double.infinity
        let av = [Double(a.x), Double(a.y)], lim = [Double(size.width), Double(size.height)]
        for j in 0..<2 {
            let lo = m, hi = lim[j] - m
            if d[j] == 0 { if av[j] < lo || av[j] > hi { return nil }; continue }
            let ka = (lo - av[j]) / d[j], kb = (hi - av[j]) / d[j]
            k0 = max(k0, min(ka, kb)); k1 = min(k1, max(ka, kb))
        }
        guard k0 < k1 else { return nil }
        func at(_ k: Double) -> CGPoint { CGPoint(x: Double(a.x) + d[0] * k, y: Double(a.y) + d[1] * k) }
        return (at(k0), at(k1))
    }

    private func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let b = board
        if b.size != size { DispatchQueue.main.async { b.size = size } }
        let ox = (size.width / 2 / CELL).rounded() * CELL, oy = (size.height / 2 / CELL).rounded() * CELL
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
        // 格线（计算板只有横线）
        var g = Path()
        if b.mode != .calc { var x = ox.truncatingRemainder(dividingBy: CELL); while x <= size.width { g.move(to: CGPoint(x: x + 0.5, y: 0)); g.addLine(to: CGPoint(x: x + 0.5, y: size.height)); x += CELL } }
        var y = oy.truncatingRemainder(dividingBy: CELL)
        while y <= size.height { g.move(to: CGPoint(x: 0, y: y + 0.5)); g.addLine(to: CGPoint(x: size.width, y: y + 0.5)); y += CELL }
        ctx.stroke(g, with: .color(Color(red: 0.89, green: 0.90, blue: 0.93)), lineWidth: 1)
        if b.axes { axes(&ctx, size, ox, oy) }

        var list = b.objs
        if live, var d = b.drag { (d.c, d.w, d.d) = (b.color, b.width, b.dash); list.append(d) }
        if live, let pts = b.pendPts {
            var o = GObj(t: b.tool == "poly" ? "open" : "curve"); (o.c, o.w, o.d) = (b.color, b.width, b.dash)
            o.pts = pts + (b.tapAt.map { [$0.0] } ?? [])
            list.append(o)
        }
        for o in list { obj(&ctx, o, size, ox, oy) }
        guard live else { return }
        let P = { (q: P2) in CGPoint(x: ox + q[0] * CELL, y: oy - q[1] * CELL) }
        for q in b.pendPts ?? (b.pendPoint.map { [$0] } ?? []) { dot(&ctx, P(q), 3.5, gcol("#d64545")) }
        if let d = b.drag, d.t != "pen" { ring(&ctx, P(d.a)) }
        let cur: P2? = (b.drag != nil && b.drag!.t != "pen") ? b.drag!.b : b.tapAt?.0
        if let c = cur, b.mode != .calc { guide(&ctx, P(c), c, size) }
    }

    private func ring(_ ctx: inout GraphicsContext, _ c: CGPoint) {
        let blue = gcol("#2f6fed")
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(blue), lineWidth: 1.5)
        dot(&ctx, c, 2.5, blue)
    }

    /// 落点：十字辅助线 + 手指上方的坐标气泡（手指挡住也能看准）
    private func guide(_ ctx: inout GraphicsContext, _ c: CGPoint, _ q: P2, _ size: CGSize) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: c.y)); p.addLine(to: CGPoint(x: size.width, y: c.y))
        p.move(to: CGPoint(x: c.x, y: 0)); p.addLine(to: CGPoint(x: c.x, y: size.height))
        ctx.stroke(p, with: .color(gcol("#2f6fed").opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        ring(&ctx, c)
        let s = xy(q), w = CGFloat(s.count) * 8.5 + 14
        let bx = min(max(c.x - w / 2, 2), size.width - w - 2), by = c.y - 64 < 2 ? c.y + 30 : c.y - 64
        ctx.fill(Path(roundedRect: CGRect(x: bx, y: by, width: w, height: 24), cornerRadius: 12), with: .color(gcol("#2f6fed")))
        ctx.draw(Text(s).font(.system(size: 14, weight: .bold)).foregroundColor(.white), at: CGPoint(x: bx + w / 2, y: by + 12), anchor: .center)
    }

    private func axes(_ ctx: inout GraphicsContext, _ size: CGSize, _ ox: Double, _ oy: Double) {
        let ink = Color(white: 0.2)
        arrowLine(&ctx, CGPoint(x: 0, y: oy + 0.5), CGPoint(x: size.width - 2, y: oy + 0.5), head0: false, head1: true, color: ink, lw: 1.2)
        arrowLine(&ctx, CGPoint(x: ox + 0.5, y: size.height), CGPoint(x: ox + 0.5, y: 2), head0: false, head1: true, color: ink, lw: 1.2)
        var x = ox.truncatingRemainder(dividingBy: CELL)
        while x < size.width - 12 { if abs(x - ox) > 1 && x > 8 { text(&ctx, num1((x - ox) / CELL), CGPoint(x: x, y: oy + 3), size: 11, color: ink, anchor: .top) }; x += CELL }
        var y = oy.truncatingRemainder(dividingBy: CELL)
        while y < size.height { if abs(y - oy) > 1 && y > 12 { text(&ctx, num1((oy - y) / CELL), CGPoint(x: ox - 4, y: y), size: 11, color: ink, anchor: .trailing) }; y += CELL }
        text(&ctx, "O", CGPoint(x: ox - 4, y: oy + 10), size: 14, italic: true, color: ink, anchor: .trailing)
        text(&ctx, "x", CGPoint(x: size.width - 4, y: oy - 11), size: 14, italic: true, color: ink, anchor: .trailing)
        text(&ctx, "y", CGPoint(x: ox + 7, y: 9), size: 14, italic: true, color: ink, anchor: .leading)
    }

    private func obj(_ ctx: inout GraphicsContext, _ o: GObj, _ size: CGSize, _ ox: Double, _ oy: Double) {
        let P = { (q: P2) in CGPoint(x: ox + q[0] * CELL, y: oy - q[1] * CELL) }
        let col = gcol(o.c), lw = o.w
        func path(_ pts: [P2], close: Bool = false) -> Path {
            var p = Path()
            for (i, q) in pts.enumerated() { i == 0 ? p.move(to: P(q)) : p.addLine(to: P(q)) }
            if close { p.closeSubpath() }
            return p
        }
        switch o.t {
        case "seg": stroke(&ctx, path([o.a, o.b]), col, lw, dash: o.d)
        case "force":
            let A = P(o.a), B = P(o.b)
            arrowLine(&ctx, A, B, head0: false, head1: true, color: col, lw: lw); dot(&ctx, A, 3.5, col)
            if !o.name.isEmpty { text(&ctx, o.name, CGPoint(x: B.x + 6, y: B.y - 4), italic: true, color: col, halo: true) }
        case "light":
            let A = P(o.a), B = P(o.b)
            stroke(&ctx, path([o.a, o.b]), col, lw, dash: o.d)
            head(&ctx, tip: CGPoint(x: A.x + (B.x - A.x) * 0.55, y: A.y + (B.y - A.y) * 0.55), from: A, color: col, lw: lw)
        case "normal": stroke(&ctx, path([o.a, o.b]), col, lw, dash: true)
        case "mirror":
            let A = P(o.a), B = P(o.b), L = hypot(B.x - A.x, B.y - A.y)
            guard L > 0 else { return }
            let u = CGPoint(x: (B.x - A.x) / L, y: (B.y - A.y) / L), n = CGPoint(x: -u.y, y: u.x)
            stroke(&ctx, path([o.a, o.b]), col, lw)
            var h = Path()
            var k: CGFloat = 4
            while k < L { let q = CGPoint(x: A.x + (B.x - A.x) * k / L, y: A.y + (B.y - A.y) * k / L); h.move(to: q); h.addLine(to: CGPoint(x: q.x + (n.x - u.x) * 6, y: q.y + (n.y - u.y) * 6)); k += 8 }
            ctx.stroke(h, with: .color(col), lineWidth: 1.2)
        case "lens", "lens2":
            let A = P(o.a), B = P(o.b), L = hypot(B.x - A.x, B.y - A.y)
            guard L > 0 else { return }
            let u = CGPoint(x: (B.x - A.x) / L, y: (B.y - A.y) / L)
            stroke(&ctx, path([o.a, o.b]), col, lw)
            if o.t == "lens" { head(&ctx, tip: A, from: B, color: col, lw: lw); head(&ctx, tip: B, from: A, color: col, lw: lw) }
            else { head(&ctx, tip: A, from: CGPoint(x: A.x - u.x * 9, y: A.y - u.y * 9), color: col, lw: lw); head(&ctx, tip: B, from: CGPoint(x: B.x + u.x * 9, y: B.y + u.y * 9), color: col, lw: lw) }
        case "open": stroke(&ctx, path(o.pts), col, lw, dash: o.d)
        case "poly": stroke(&ctx, path(o.pts, close: true), col, lw, dash: o.d)
        case "line", "ray":
            if let (s, e) = clip(P(o.a), P(o.b), ray: o.t == "ray", size) { arrowLine(&ctx, s, e, head0: o.t == "line", head1: true, color: col, lw: lw) }
        case "circle":
            let q = P(o.a), r = dist(o.a, o.b) * CELL
            stroke(&ctx, Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), col, lw, dash: o.d)
            dot(&ctx, q, 2, col)
        case "pen", "curve":
            let q = o.pts.map(P)
            guard q.count > 1 else { return }
            var p = Path(); p.move(to: q[0])
            for i in 0..<(q.count - 1) {
                let p0 = i > 0 ? q[i - 1] : q[i], p1 = q[i], p2 = q[i + 1], p3 = i + 2 < q.count ? q[i + 2] : p2
                p.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6), control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
            }
            stroke(&ctx, p, col, lw, dash: o.d)
        case "pt":
            let q = P(o.p)
            dot(&ctx, q, 3.5, col)
            text(&ctx, o.name + xy(o.p), CGPoint(x: q.x + 6, y: q.y - 4), size: o.name.isEmpty ? 13 : 15, italic: !o.name.isEmpty, color: col, halo: true)
        case "angle":
            break
        case "text":
            let q = P(o.p)
            if board.mode == .calc { richText(&ctx, o.s, q, col) }
            else { text(&ctx, o.s, q, size: 17, color: col, anchor: .leading) }
        case "ra":
            let k = 0.45, a = o.at
            stroke(&ctx, path([[a[0] + o.u[0] * k, a[1] + o.u[1] * k], [a[0] + (o.u[0] + o.v[0]) * k, a[1] + (o.u[1] + o.v[1]) * k], [a[0] + o.v[0] * k, a[1] + o.v[1] * k]]), col, lw)
        case "fn":
            guard let f = board.fn(o.expr) else { return }
            var p = Path(), last: Double?, end: CGPoint?
            var x = 0.0
            while x <= Double(size.width) {
                let y = oy - f((x - ox) / CELL) * CELL
                if !y.isFinite || abs(y) > Double(size.height) * 4 || (last != nil && abs(y - last!) > Double(size.height)) { last = nil; x += 1; continue }
                last == nil ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                last = y
                if y > 16 && y < Double(size.height) - 6 { end = CGPoint(x: x, y: y) }
                x += 1
            }
            stroke(&ctx, p, col, lw, dash: o.d)
            if let e = end { text(&ctx, o.expr, CGPoint(x: min(e.x, size.width - 4), y: e.y - 4), size: 13, italic: true, color: col, anchor: .bottomTrailing) }
        default: break
        }
    }

    /// 计算板上的文字：分数 3/4 写成竖式分数；结果后面的「（≈0.75）」小号灰字
    private func richText(_ ctx: inout GraphicsContext, _ s: String, _ at: CGPoint, _ color: Color) {
        var x = at.x
        let y = at.y
        guard let re = try? NSRegularExpression(pattern: "(-?\\d+/\\d+|（≈[^）]*）)") else { return }
        let ns = s as NSString
        var last = 0
        func piece(_ t: String) {
            guard !t.isEmpty else { return }
            let r = ctx.resolve(Text(t).font(.system(size: 17)).foregroundColor(color))
            ctx.draw(r, at: CGPoint(x: x, y: y), anchor: .leading)
            x += r.measure(in: CGSize(width: 1000, height: 40)).width
        }
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            piece(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            let part = ns.substring(with: m.range)
            last = m.range.location + m.range.length
            if part.hasPrefix("（≈") {
                let r = ctx.resolve(Text(part).font(.system(size: 13)).foregroundColor(Color(white: 0.55)))
                ctx.draw(r, at: CGPoint(x: x, y: y), anchor: .leading); x += r.measure(in: CGSize(width: 1000, height: 40)).width
                continue
            }
            let neg = part.hasPrefix("-"), body = neg ? String(part.dropFirst()) : part
            let nd = body.components(separatedBy: "/")
            guard nd.count == 2 else { piece(part); continue }
            if neg { piece("−"); x += 3 }
            let rn = ctx.resolve(Text(nd[0]).font(.system(size: 13)).foregroundColor(color)), rd = ctx.resolve(Text(nd[1]).font(.system(size: 13)).foregroundColor(color))
            let w = max(rn.measure(in: CGSize(width: 500, height: 30)).width, rd.measure(in: CGSize(width: 500, height: 30)).width) + 6
            ctx.draw(rn, at: CGPoint(x: x + w / 2, y: y - 7.5), anchor: .center)
            ctx.draw(rd, at: CGPoint(x: x + w / 2, y: y + 8.5), anchor: .center)
            var line = Path(); line.move(to: CGPoint(x: x, y: y + 0.5)); line.addLine(to: CGPoint(x: x + w, y: y + 0.5))
            ctx.stroke(line, with: .color(color), lineWidth: 1.2)
            x += w + 3
        }
        piece(ns.substring(from: last))
    }
}
