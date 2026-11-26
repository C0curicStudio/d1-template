import Foundation

// 画板用的数学：函数解析（+ - * / ^ ( ) | |、隐式乘法、sqrt sin cos tan abs ln log、pi e）、
// 算式出得数（分数、根式化简）、方程 / 方程组 / 不等式求解。移植自网页版画板，规则一致。

struct FnErr: Error { let msg: String; init(_ m: String) { msg = m } }

private func rxMatches(_ s: String, _ pattern: String, options: NSRegularExpression.Options = []) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
    let ns = s as NSString
    return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
}

private func rxReplace(_ s: String, _ pattern: String, _ template: String, options: NSRegularExpression.Options = []) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
    return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
}

private final class FnParser {
    let t: [String]
    var i = 0
    init(_ t: [String]) { self.t = t }
    func tok() -> String? { i < t.count ? t[i] : nil }
    func need(_ c: String, _ msg: String) throws { if tok() != c { throw FnErr(msg) }; i += 1 }

    func startsOperand(_ k: String) -> Bool {
        guard let c = k.first else { return false }
        return c.isNumber || c == "." || c == "(" || (c.isLetter && c.isASCII)
    }

    func sum() throws -> (Double) -> Double {
        var f = try prod()
        while let k = tok(), k == "+" || k == "-" {
            i += 1
            let a = f, sgn: Double = k == "+" ? 1 : -1
            let g = try prod()
            f = { a($0) + sgn * g($0) }
        }
        return f
    }
    func prod() throws -> (Double) -> Double {
        var f = try neg()
        while let k = tok(), k == "*" || k == "/" || startsOperand(k) {
            let div = k == "/"
            if k == "*" || div { i += 1 }
            let a = f
            let g = try neg()
            f = div ? { a($0) / g($0) } : { a($0) * g($0) }
        }
        return f
    }
    func neg() throws -> (Double) -> Double {
        if tok() == "-" { i += 1; let g = try neg(); return { -g($0) } }
        if tok() == "+" { i += 1; return try neg() }
        return try pow()
    }
    func pow() throws -> (Double) -> Double {
        let b = try atom()
        if tok() != "^" { return b }
        i += 1
        let e = try neg()
        return { Foundation.pow(b($0), e($0)) }
    }
    func atom() throws -> (Double) -> Double {
        let w = (tok() ?? "").lowercased()
        i += 1
        if w.isEmpty { throw FnErr("式子不完整") }
        if let c = w.first, c.isNumber || c == "." { let v = Double(w) ?? 0; return { _ in v } }
        if w == "(" { let f = try sum(); try need(")", "括号不配对"); return f }
        if w == "|" { let f = try sum(); try need("|", "绝对值不配对"); return { abs(f($0)) } }
        if w == "x" { return { $0 } }
        if w == "pi" { return { _ in Double.pi } }
        if w == "e" { return { _ in M_E } }
        let fns: [String: (Double) -> Double] = ["sqrt": { $0.squareRoot() }, "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) }, "abs": { abs($0) }, "ln": { log($0) }, "log": { log10($0) }]
        guard let fn = fns[w] else { throw FnErr("不认识：" + w) }
        try need("(", w + " 后面要加括号")
        let f = try sum()
        try need(")", "括号不配对")
        return { fn(f($0)) }
    }
}

func compileFn(_ src: String) throws -> (Double) -> Double {
    var s = src.filter { !$0.isWhitespace }
    if s.lowercased().hasPrefix("y=") { s = String(s.dropFirst(2)) }
    s = s.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")").replacingOccurrences(of: "×", with: "*")
        .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "²", with: "^2").replacingOccurrences(of: "³", with: "^3")
    s = rxReplace(s, "√(\\d+\\.?\\d*|[a-z]|π)", "√($1)", options: .caseInsensitive)
    s = s.replacingOccurrences(of: "√", with: "sqrt").replacingOccurrences(of: "π", with: "pi")
    let toks = rxMatches(s, "\\d+\\.?\\d*|\\.\\d+|[a-z]+|[-+*/^()|]", options: .caseInsensitive)
    if toks.isEmpty || toks.joined() != s { throw FnErr("看不懂这个式子") }
    let p = FnParser(toks)
    let f = try p.sum()
    if p.i < toks.count { throw FnErr("多余的：" + toks[p.i...].joined()) }
    return f
}

/// 把一个数写成最简形式：整数、分数、a√b/d，后面附小数方便核对
func nice(_ v: Double) -> String {
    if !v.isFinite { return "无意义" }
    func near(_ n: Double, _ d: Double) -> Bool { abs(v * d - n) < 1e-9 * max(1, abs(v * d)) }
    let n0 = v.rounded()
    if near(n0, 1) { return String(Int(n0)) }
    let dec = "（≈\(fmt6(v))）"
    for d in 2...1000 {
        let n = (v * Double(d)).rounded()
        if near(n, Double(d)) { return "\(Int(n))/\(d)\(dec)" }
    }
    for b in [2, 3, 5, 6, 7, 10, 11, 13, 14, 15] {
        for d in 1...12 {
            let a = ((v * Double(d)) / Double(b).squareRoot()).rounded()
            if a != 0 && abs((a * Double(b).squareRoot()) / Double(d) - v) < 1e-9 {
                let ai = Int(a)
                return "\(ai == 1 ? "" : ai == -1 ? "-" : String(ai))√\(b)\(d > 1 ? "/\(d)" : "")\(dec)"
            }
        }
    }
    return fmt6(v)
}

private func fmt6(_ v: Double) -> String {
    let s = String(format: "%.6g", v)
    return s.contains("e") ? s : s
}

func num1(_ v: Double) -> String { let r = (v * 10).rounded() / 10; return r == 0 ? "0" : (r == r.rounded() ? String(Int(r)) : String(r)) }
func num2(_ v: Double) -> String { let r = (v * 100).rounded() / 100; return r == 0 ? "0" : (r == r.rounded() ? String(Int(r)) : String(r)) }

/// 方程为主：一元方程（含二次，附判别式）、二元一次方程组（逗号隔开）、一元一次不等式；没有未知数就直接算
func calcText(_ input: String) -> String {
    let s = input.trimmingCharacters(in: .whitespaces)
    var memo: [String: (Double) -> Double] = [:]
    func fy(_ src: String, _ y: Double) throws -> (Double) -> Double {
        let k = src + "|" + String(y)
        if let f = memo[k] { return f }
        let f = try compileFn(src.replacingOccurrences(of: "y", with: "(\(y))", options: .caseInsensitive))
        memo[k] = f
        return f
    }
    func G(_ eq: String) -> (Double, Double) throws -> Double {
        let parts = eq.components(separatedBy: "=")
        let L = parts.first ?? "", R = parts.count > 1 ? parts[1] : ""
        return { x, y in try fy(L, y)(x) - fy(R, y)(x) }
    }
    func lin(_ g: (Double, Double) throws -> Double) throws -> [Double]? {
        let c = try g(0, 0), a = try g(1, 0) - c, b = try g(0, 1) - c
        return abs(try g(2, 3) - (2 * a + 3 * b + c)) < 1e-9 ? [a, b, c] : nil
    }
    do {
        let eqs = s.split(whereSeparator: { ";；,，".contains($0) }).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let hasY = s.lowercased().contains("y")
        if hasY && eqs.count != 2 { return s }
        if eqs.count == 2 && hasY {
            guard let p = try lin(G(eqs[0])), let q = try lin(G(eqs[1])) else { return "\(s) → 只会解二元一次方程组" }
            let D = p[0] * q[1] - q[0] * p[1]
            if abs(D) < 1e-12 { return "\(s) → 无解或有无数组解" }
            return "\(s) → x=\(nice((p[1] * q[2] - q[1] * p[2]) / D))，y=\(nice((p[2] * q[0] - p[0] * q[2]) / D))"
        }
        let iqRe = try NSRegularExpression(pattern: "^([^<>≤≥]*)(>=|<=|≥|≤|>|<)([^<>≤≥]*)$")
        let ns = s as NSString
        if let m = iqRe.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), s.lowercased().contains("x") {
            let l = ns.substring(with: m.range(at: 1)), op0 = ns.substring(with: m.range(at: 2)), r = ns.substring(with: m.range(at: 3))
            guard let L = try lin(G(l + "=" + r)) else { return "\(s) → 只会解一元一次不等式" }
            let a = L[0], c = L[2]
            let op = op0 == ">=" ? "≥" : op0 == "<=" ? "≤" : op0
            let flip = [">": "<", "<": ">", "≥": "≤", "≤": "≥"]
            if abs(a) < 1e-12 {
                let ok = op == ">" ? c > 0 : op == "<" ? c < 0 : op == "≥" ? c >= 0 : c <= 0
                return "\(s) → \(ok ? "任意数" : "无解")"
            }
            return "\(s) → x\(a > 0 ? op : (flip[op] ?? op))\(nice(-c / a))"
        }
        let parts = s.components(separatedBy: "=")
        if parts.count > 2 { return s }
        let Ls = parts[0], Rs = parts.count > 1 ? parts[1] : nil
        if Rs == nil || Rs!.trimmingCharacters(in: .whitespaces).isEmpty {
            let l = Ls.hasSuffix("=") ? String(Ls.dropLast()) : Ls
            return "\(l) = \(nice(try compileFn(Ls)(0)))"
        }
        if !s.lowercased().contains("x") { return s }
        let g = G(s)
        let f: (Double) -> Double = { (try? g($0, 0)) ?? .nan }
        var roots: [Double] = []
        var x = -100.0, p = Double.nan, a = f(x)
        while x < 100 {
            let b = f(x + 0.01)
            if abs(a) <= abs(p) && abs(a) <= abs(b) && a * b >= 0 {
                var lo = x - 0.01, hi = x + 0.01
                for _ in 0..<60 { let m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3; if abs(f(m1)) < abs(f(m2)) { hi = m2 } else { lo = m1 } }
                if abs(f(lo)) < 1e-8 { roots.append(lo) }
            } else if a * b < 0 && a.isFinite && b.isFinite {
                var lo = x, hi = x + 0.01
                for _ in 0..<60 { let m = (lo + hi) / 2; if f(lo) * f(m) <= 0 { hi = m } else { lo = m } }
                if abs(f(lo)) < 1e-6 { roots.append(lo) }
            }
            p = a; a = b; x += 0.01
        }
        let c = f(0), a2 = (f(1) + f(-1)) / 2 - c, b2 = (f(1) - f(-1)) / 2
        let quad = abs(a2) > 1e-12 && [2.0, 3.0, -4.0].allSatisfy { abs(f($0) - (a2 * $0 * $0 + b2 * $0 + c)) < 1e-9 }
        var seen = Set<String>(), out: [String] = []
        for r in roots { let n = nice(r); if seen.insert(n).inserted { out.append(n) } }
        return "\(s) → \(out.isEmpty ? "无实数解" : out.map { "x=" + $0 }.joined(separator: "，"))\(quad ? "（Δ=\(nice(b2 * b2 - 4 * a2 * c))）" : "")"
    } catch { return s }
}
