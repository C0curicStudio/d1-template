import Foundation
import WebKit

/// 题库同步：该请求的请求——带着上次的指纹（ETag）去问服务器，没变化只回 304，不重复下载；有变化才整份更新本地 SQLite。
/// 登录状态复用网页里的 Cookie，不用另外登录。
final class LibrarySync: ObservableObject {
    static let shared = LibrarySync()
    @Published var count: Int = LocalStore.shared.count()
    @Published var lastSync: Date?
    private var running = false
    private var lastRun = Date.distantPast

    func refresh(force: Bool = false) {
        guard !running, force || Date().timeIntervalSince(lastRun) > 300 else { return }
        running = true
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let host = Site.url.host ?? ""
            let mine = cookies.filter { c in
                let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                return host == d || host.hasSuffix("." + d)
            }
            guard !mine.isEmpty else { DispatchQueue.main.async { self.running = false }; return } // 还没登录
            var req = URLRequest(url: Site.url.appendingPathComponent("api/library/sync"))
            req.httpShouldHandleCookies = false
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 30
            for (k, v) in HTTPCookie.requestHeaderFields(with: mine) { req.setValue(v, forHTTPHeaderField: k) }
            if let et = LocalStore.shared.meta("etag"), LocalStore.shared.count() > 0 { req.setValue(et, forHTTPHeaderField: "If-None-Match") }
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                var items: [[String: Any]]?
                let http = resp as? HTTPURLResponse
                if http?.statusCode == 200, let data = data,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let arr = obj["items"] as? [[String: Any]] {
                    items = arr
                    LocalStore.shared.replaceAll(arr, etag: http?.value(forHTTPHeaderField: "ETag"))
                }
                DispatchQueue.main.async {
                    self.running = false
                    if http != nil { self.lastRun = Date() }
                    if items != nil || http?.statusCode == 304 { self.lastSync = Date() }
                    self.count = LocalStore.shared.count()
                }
            }.resume()
        }
    }
}
