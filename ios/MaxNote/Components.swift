import SwiftUI
import UIKit

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func ok() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func bad() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct Chip: View {
    let text: String
    var tint: Color = .accentColor
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

func levelColor(_ level: String) -> Color {
    switch level {
    case "薄弱": return .red
    case "熟练": return .green
    case "未练": return .gray
    default: return .accentColor
    }
}

struct StatTile: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .modifier(NumericTransition())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 20)
    }
}

struct NumericTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) { content.contentTransition(.numericText()) } else { content }
    }
}

struct OfflineBadge: View {
    var body: some View {
        Label("没有网络，显示的是上次的内容", systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyHint: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// Max 回答的排版：**加粗** 走系统 Markdown；公式去掉记号保持可读
func md(_ s: String) -> AttributedString {
    let t = plain(s)
    return (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
}

/// 回答里的动作标记：[[练:科目/考点]] [[去:/wrong]] [[做:动作|参数]] …  拆成按钮，正文里去掉
struct MaxAction: Identifiable, Hashable {
    enum Kind: Hashable { case practice, go, doit, note }
    let id = UUID()
    let kind: Kind
    let arg: String
    let extra: String
    var title: String {
        switch kind {
        case .practice: return "练：" + arg.replacingOccurrences(of: "/", with: " › ")
        case .go: return arg == "/wrong" ? "→ 错题本" : arg == "/bank" ? "→ 题库" : "→ 首页"
        case .doit: return arg + (extra.isEmpty ? "" : "…")
        case .note: return "Notion 笔记：" + arg
        }
    }
}

func splitActions(_ text: String) -> (String, [MaxAction]) {
    var out = text
    var acts: [MaxAction] = []
    func grab(_ pattern: String, _ make: ([String]) -> MaxAction?) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = out as NSString
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            let g = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            if let a = make(g) { acts.append(a) }
        }
        out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }
    grab("\\[\\[练[:：]([^\\]|]+)(?:\\|(\\d+))?\\]\\]") { MaxAction(kind: .practice, arg: $0[1].trimmingCharacters(in: .whitespaces), extra: $0[2]) }
    grab("\\[\\[去[:：]\\s*(/[\\w/]*)\\]\\]") { MaxAction(kind: .go, arg: $0[1], extra: "") }
    grab("\\[\\[做[:：]\\s*([^\\]|]+)(?:\\|(.*?))?\\]\\]") { MaxAction(kind: .doit, arg: $0[1].trimmingCharacters(in: .whitespaces), extra: $0[2]) }
    grab("\\[\\[整理错题\\]\\]") { _ in MaxAction(kind: .doit, arg: "整理错题", extra: "") }
    grab("\\[\\[笔记[:：]([^\\]]+)\\]\\]") { MaxAction(kind: .note, arg: $0[1], extra: "") }
    grab("\\[\\[图[:：][\\s\\S]*?\\]\\]") { _ in nil } // 图在网页版里看
    out = out.replacingOccurrences(of: "\\[\\[[^\\]]*$", with: "", options: .regularExpression) // 流式输出时没写完的
    return (out.trimmingCharacters(in: .whitespacesAndNewlines), acts)
}

/// 页面背景：系统分组底色 + 一点点暖色渐变（和网站的米色呼应）
struct WarmBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(scheme == .dark ? 0.10 : 0.07), Color.clear], startPoint: .top, endPoint: .center)
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea()
    }
}
