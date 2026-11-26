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

/// 全局导航：任何页面都能发起「练题 / 讲解 / 问 Max / 打开网页版」，由根视图统一弹出
@MainActor
final class Router: ObservableObject {
    @Published var tab = 0
    @Published var quiz: QuizSpec?
    @Published var chat: ChatSpec?
    @Published var lesson: LessonSpec?
    @Published var web: WebSpec?
    @Published var printSpec: IdsSpec?

    func practice(ids: [Int], title: String = "练习") {
        guard !ids.isEmpty else { return }
        quiz = QuizSpec(title: title, path: "/api/practice?ids=" + ids.prefix(50).map(String.init).joined(separator: ","))
    }
    func practiceToday() { quiz = QuizSpec(title: "今日练习", path: "/api/practice") }
    func practice(subject: String) { quiz = QuizSpec(title: subject, path: "/api/practice?subject=" + subject.urlEnc) }
    func practice(topic: String) { quiz = QuizSpec(title: topic.replacingOccurrences(of: "/", with: " › "), path: "/api/practice?topic=" + topic.urlEnc) }
    func print(ids: [Int]) { printSpec = IdsSpec(ids: ids) }
    func ask(_ prompt: String? = nil, ctx: J = [:], study: Bool = true, topic: String = "") {
        chat = ChatSpec(title: "问 Max", study: study, topic: topic, ctx: ctx, prompt: prompt)
    }
    func open(_ a: MaxAction) {
        switch a.kind {
        case .practice: practice(topic: a.arg)
        case .go: tab = a.arg == "/wrong" ? 2 : a.arg == "/bank" ? 1 : 0
        default: break
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
