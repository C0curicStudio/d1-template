import Foundation
import Network

/// 自动缓存：启动、回到前台时在后台把今日题、各科题、题库、错题本、学习台数据存到本机，没网也能做题；
/// 没网时交的卷先存在本机，联网后自动补交。
@MainActor
final class Prefetcher: ObservableObject {
    static let shared = Prefetcher()
    @Published var running = false
    @Published var progress = ""
    @Published var lastRun: Date? = (UserDefaults.standard.object(forKey: "prefetchAt") as? Double).map { Date(timeIntervalSince1970: $0) }
    @Published var online = true
    @Published var onWifi = true
    @Published var pending = LocalStore.shared.outboxList().count

    private let monitor = NWPathMonitor()
    private var wasOnline = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.online = path.status == .satisfied
                self.onWifi = !path.isExpensive
                if self.online && !self.wasOnline { Task { await self.flush(); await self.run() } } // 网络恢复：补交答案、更新缓存
                self.wasOnline = self.online
            }
        }
        monitor.start(queue: DispatchQueue(label: "maxnote.net"))
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: "autoCache") as? Bool ?? true }
    var wifiOnly: Bool { UserDefaults.standard.bool(forKey: "wifiOnly") }

    /// force：用户在设置里点了「立即缓存」，不看开关和间隔
    func run(force: Bool = false) async {
        guard API.shared.authed == true, !running else { return }
        if !force {
            guard enabled, online else { return }
            if wifiOnly && !onWifi { return }
            if let t = lastRun, Date().timeIntervalSince(t) < 600 { return } // 10 分钟内不重复
        }
        running = true
        defer { running = false; progress = "" }
        var paths = ["/api/home?brief=1", "/api/study", "/api/bank", "/api/wrong?tab=active", "/api/wrong?tab=mastered", "/api/max/wrongsum", "/api/practice"]
        var done = 0
        var subjects: [String] = []
        var detailIds: [Int] = []
        func fetch(_ p: String) async -> Any? {
            progress = "缓存中 \(done + 1)/\(paths.count)"
            let v = try? await API.shared.fresh(p)
            done += 1
            return v
        }
        var i = 0
        while i < paths.count {
            let p = paths[i]
            let v = await fetch(p)
            if p.hasPrefix("/api/home"), let h = v as? J { subjects = h.arr("subjects").map { $0.str("subject") }; for s in subjects { paths.append("/api/practice?subject=" + s.urlEnc) } }
            if p.hasPrefix("/api/wrong?tab=active"), let w = v as? J { detailIds += w.arr("items").prefix(40).map { $0.int("id") } }
            if p == "/api/bank", let b = v as? J { detailIds += b.arr("items").prefix(30).map { $0.int("id") } }
            i += 1
        }
        // 题目详情（错题本和题库前面的题）：离线也能点开看
        for id in Array(Set(detailIds)).prefix(70) {
            if !online { break }
            progress = "缓存题目 \(id)"
            _ = try? await API.shared.fresh("/api/question/\(id)")
        }
        lastRun = Date()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "prefetchAt")
    }

    /// 补交没网时存下的答案
    func flush() async {
        for (id, body) in LocalStore.shared.outboxList() {
            guard let d = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: d) else { LocalStore.shared.outboxDelete(id); continue }
            do {
                _ = try await API.shared.any("/api/submit", method: "POST", json: json)
                LocalStore.shared.outboxDelete(id)
                NotificationCenter.default.post(name: .bankChanged, object: nil)
            } catch NetError.offline { break }
            catch NetError.unauthorized { break }
            catch { LocalStore.shared.outboxDelete(id) } // 服务器拒绝（题已被删等）：丢掉，别反复重试
        }
        pending = LocalStore.shared.outboxList().count
    }

    func refreshPending() { pending = LocalStore.shared.outboxList().count }
}
