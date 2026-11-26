import SwiftUI

struct QuizSpec: Identifiable { let id = UUID(); let title: String; let path: String }
struct ChatSpec: Identifiable {
    let id = UUID()
    var title = "问 Max"
    var study = true
    var topic = ""
    var ctx: J = [:]
    var prompt: String? = nil
}
struct LessonSpec: Identifiable { let id = UUID(); let topic: String }
struct IdsSpec: Identifiable { let id = UUID(); let ids: [Int] }
struct WebSpec: Identifiable { let id = UUID(); let path: String; let title: String }

/// 同一时间只弹一个面板：多个 .sheet 叠在同一个视图上，在 iOS 上只有最后一个能弹出来（输入框弹不出来就是这个原因）
enum SheetKind: Identifiable {
    case chat(ChatSpec), lesson(LessonSpec), web(WebSpec), print(IdsSpec), settings
    var id: String {
        switch self {
        case .chat(let s): return "chat-\(s.id)"
        case .lesson(let s): return "lesson-\(s.id)"
        case .web(let s): return "web-\(s.id)"
        case .print(let s): return "print-\(s.id)"
        case .settings: return "settings"
        }
    }
}

/// 全局导航：任何页面都能发起「练题 / 讲解 / 问 Max / 打开网页版」，由根视图统一弹出
@MainActor
final class Router: ObservableObject {
    @Published var tab = 0
    @Published var quiz: QuizSpec?
    @Published var sheet: SheetKind?

    var chat: ChatSpec? { get { if case .chat(let s) = sheet { return s }; return nil } set { sheet = newValue.map { .chat($0) } } }
    var lesson: LessonSpec? { get { if case .lesson(let s) = sheet { return s }; return nil } set { sheet = newValue.map { .lesson($0) } } }
    var web: WebSpec? { get { if case .web(let s) = sheet { return s }; return nil } set { sheet = newValue.map { .web($0) } } }

    func practice(ids: [Int], title: String = "练习") {
        guard !ids.isEmpty else { return }
        quiz = QuizSpec(title: title, path: "/api/practice?ids=" + ids.prefix(50).map(String.init).joined(separator: ","))
    }
    func practiceToday() { quiz = QuizSpec(title: "今日练习", path: "/api/practice") }
    func practice(subject: String) { quiz = QuizSpec(title: subject, path: "/api/practice?subject=" + subject.urlEnc) }
    func practice(topic: String) { quiz = QuizSpec(title: topic.replacingOccurrences(of: "/", with: " › "), path: "/api/practice?topic=" + topic.urlEnc) }
    func print(ids: [Int]) { sheet = .print(IdsSpec(ids: ids)) }
    func ask(_ prompt: String? = nil, ctx: J = [:], study: Bool = true, topic: String = "") {
        sheet = .chat(ChatSpec(title: "问 Max", study: study, topic: topic, ctx: ctx, prompt: prompt))
    }
    func open(_ a: MaxAction) {
        switch a.kind {
        case .practice: practice(topic: a.arg)
        case .go: tab = a.arg == "/wrong" ? 2 : a.arg == "/bank" ? 1 : 0
        default: break
        }
    }
}

/// 面板内容（根视图和做题页共用）
struct SheetHost: View {
    let kind: SheetKind
    @EnvironmentObject private var router: Router
    var body: some View {
        switch kind {
        case .chat(let s): ChatView(spec: s).environmentObject(router)
        case .lesson(let s): LessonView(spec: s).environmentObject(router)
        case .web(let s): WebSheet(spec: s)
        case .print(let s): PrintFlow(preselect: s.ids)
        case .settings: SettingsView().environmentObject(router)
        }
    }
}

extension String {
    var urlEnc: String {
        var a = CharacterSet.alphanumerics
        a.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: a) ?? self
    }
}
