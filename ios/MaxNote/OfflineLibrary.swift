import SwiftUI

/// 离线题库：没网时直接读本地 SQLite 副本（搜索、看答案和解析）
struct OfflineLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var subject = ""
    @State private var rows: [QRow] = []
    @State private var subjects: [String] = []

    var body: some View {
        NavigationStack {
            List(rows) { r in
                NavigationLink(value: r) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(r.subject).font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                            if !r.topic.isEmpty { Text(r.topic).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if r.wrongs > 0 { Text("错 \(r.wrongs)").font(.caption).foregroundStyle(.red) }
                            Text(r.state).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(plain(r.stem)).font(.body).lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if rows.isEmpty { Text(LocalStore.shared.count() == 0 ? "还没有同步过题库，联网打开一次就会自动保存。" : "没有符合的题").foregroundStyle(.secondary).padding() }
            }
            .searchable(text: $query, prompt: "搜索题干、考点、解析")
            .navigationTitle("离线题库")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: QRow.self) { QDetail(row: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("科目", selection: $subject) {
                            Text("全部科目").tag("")
                            ForEach(subjects, id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .task(id: query + "|" + subject) {
                if subjects.isEmpty { subjects = LocalStore.shared.subjects() }
                rows = LocalStore.shared.search(query, subject: subject)
            }
        }
    }
}

struct QDetail: View {
    let row: QRow
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(row.subject).font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                    if !row.topic.isEmpty { Text("· " + row.topic).font(.subheadline).foregroundStyle(.secondary) }
                    if !row.tag.isEmpty { Text(row.tag).font(.caption).padding(.horizontal, 8).padding(.vertical, 2).glassCapsule(interactive: false) }
                }
                Text(plain(row.stem)).font(.title3)
                if !row.options.isEmpty {
                    VStack(alignment: .leading, spacing: 6) { ForEach(row.options, id: \.self) { Text(plain($0)) } }
                }
                block("正确答案", row.answer.joined(separator: " / "))
                if !row.explanation.isEmpty { block("解析", row.explanation) }
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(plain(body)).font(.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }
}

/// 公式在原生界面里转成 Unicode 可读形式：上下标、分数、根号、化学式、常用符号（不依赖网页的 KaTeX）
private let SUP: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"]
private let SUB: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "n": "ₙ", "m": "ₘ"]

private func rx(_ s: String, _ pattern: String, _ f: ([String]) -> String) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
    let ns = s as NSString
    var out = "", last = 0
    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        out += f((0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) })
        last = m.range.location + m.range.length
    }
    return out + ns.substring(from: last)
}

private func mapChars(_ s: String, _ table: [Character: Character], _ fallback: String) -> String {
    let t = s.filter { $0 != " " }
    if t.allSatisfy({ table[$0] != nil }) { return String(t.map { table[$0]! }) }
    return fallback + (t.count > 1 ? "(" + t + ")" : t)
}

func plain(_ input: String) -> String {
    var t = input.replacingOccurrences(of: "$", with: "")
    // 化学式 \ce{H2O} \ce{2KMnO4 ->[\Delta] K2MnO4}
    t = rx(t, "\\\\ce\\{([^{}]*)\\}") { g in
        var c = g[1].replacingOccurrences(of: "<=>", with: " ⇌ ").replacingOccurrences(of: "->", with: " → ").replacingOccurrences(of: "\\Delta", with: "△")
        c = rx(c, "\\[([^\\]]*)\\]") { $0[1] }
        c = rx(c, "([A-Za-z\\)])(\\d+)") { $0[1] + mapChars($0[2], SUB, "_") }
        return c
    }
    t = rx(t, "\\\\[dt]?frac\\{([^{}]*)\\}\\{([^{}]*)\\}") { g in
        let a = g[1].count > 1 ? "(" + g[1] + ")" : g[1], b = g[2].count > 1 ? "(" + g[2] + ")" : g[2]
        return a + "/" + b
    }
    t = rx(t, "\\\\sqrt\\[(\\d)\\]\\{([^{}]*)\\}") { (g: [String]) -> String in mapChars(g[1], SUP, "^") + "√(" + g[2] + ")" }
    t = rx(t, "\\\\sqrt\\{([^{}]*)\\}") { "√(" + $0[1] + ")" }
    t = t.replacingOccurrences(of: "\\sqrt", with: "√")
    let sym: [(String, String)] = [("\\times", "×"), ("\\cdot", "·"), ("\\div", "÷"), ("\\pm", "±"), ("\\neq", "≠"), ("\\ne", "≠"), ("\\leq", "≤"), ("\\le", "≤"), ("\\geq", "≥"), ("\\ge", "≥"),
        ("\\approx", "≈"), ("\\infty", "∞"), ("\\circ", "°"), ("\\angle", "∠"), ("\\triangle", "△"), ("\\perp", "⊥"), ("\\parallel", "∥"), ("\\because", "∵"), ("\\therefore", "∴"),
        ("\\rightarrow", "→"), ("\\to", "→"), ("\\Rightarrow", "⇒"), ("\\leftrightarrow", "↔"), ("\\Omega", "Ω"), ("\\omega", "ω"), ("\\Delta", "Δ"), ("\\delta", "δ"), ("\\alpha", "α"), ("\\beta", "β"),
        ("\\gamma", "γ"), ("\\theta", "θ"), ("\\lambda", "λ"), ("\\mu", "μ"), ("\\pi", "π"), ("\\rho", "ρ"), ("\\sigma", "σ"), ("\\varphi", "φ"), ("\\phi", "φ"), ("\\eta", "η"),
        ("\\left", ""), ("\\right", ""), ("\\,", " "), ("\;", " "), ("\\!", ""), ("\\quad", "  "), ("\\text", ""), ("\\mathrm", ""), ("\\%", "%"), ("\\{", "{"), ("\\}", "}")]
    for (a, b) in sym { t = t.replacingOccurrences(of: a, with: b) }
    t = rx(t, "\\^\\{([^{}]*)\\}") { mapChars($0[1], SUP, "^") }
    t = rx(t, "\\^([0-9A-Za-z+\\-])") { mapChars($0[1], SUP, "^") }
    t = rx(t, "_\\{([^{}]*)\\}") { mapChars($0[1], SUB, "_") }
    t = rx(t, "_([0-9A-Za-z])") { mapChars($0[1], SUB, "_") }
    return t.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
}
