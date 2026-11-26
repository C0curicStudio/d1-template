import Foundation
import WebKit

/// 服务器返回的 JSON 用字典读（字段多、有的可能缺或为 null，这样最不容易因为一个字段变了就整页读不出来）
typealias J = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func int(_ k: String) -> Int {
        if let v = self[k] as? Int { return v }
        if let d = self[k] as? Double { return Int(d) }
        if let s = self[k] as? String, let i = Int(s) { return i }
        return 0
    }
    func str(_ k: String) -> String { (self[k] as? String) ?? "" }
    func opt(_ k: String) -> String? { self[k] as? String }
    func arr(_ k: String) -> [J] { (self[k] as? [J]) ?? [] }
    func strs(_ k: String) -> [String] { (self[k] as? [String]) ?? [] }
    func dict(_ k: String) -> J? { self[k] as? J }
    func bool(_ k: String) -> Bool {
        if let b = self[k] as? Bool { return b }
        return int(k) != 0
    }
    func has(_ k: String) -> Bool { self[k] != nil && !(self[k] is NSNull) }
}

enum NetError: LocalizedError {
    case unauthorized, offline, server(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "需要登录"
        case .offline: return "没有网络，联网后再试"
        case .server(let m): return m
        }
    }
}

/// 和服务器说话：登录状态用系统 Cookie；GET 结果存进本地 SQLite，没网时先用上次的
@MainActor
final class API: ObservableObject {
    static let shared = API()
    @Published var authed: Bool? = nil // nil = 还不知道

    let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = HTTPCookieStorage.shared
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 25
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func url(_ path: String) -> URL { URL(string: Site.text + path) ?? Site.url }

    // MARK: 登录与 Cookie（原生和网页版共用一份登录）
    func bootstrap() async {
        #if DEBUG
        if Demo.on { authed = true; return }
        #endif
        await pullCookiesFromWeb()
        do { _ = try await data("/api/home") ; authed = true } catch NetError.unauthorized { authed = false } catch { authed = LocalStore.shared.count() > 0 || HTTPCookieStorage.shared.cookies(for: Site.url)?.isEmpty == false }
    }

    func login(_ code: String) async throws {
        var req = URLRequest(url: url("/login"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = ("passcode=" + (code.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).data(using: .utf8)
        do {
            let (_, r) = try await session.data(for: req)
            let c = (r as? HTTPURLResponse)?.statusCode ?? 0
            if c == 429 { throw NetError.server("尝试太频繁，1 分钟后再试") }
            if c == 401 { throw NetError.server("口令不对") }
            if c >= 400 { throw NetError.server("登录失败（\(c)）") }
        } catch let e as NetError { throw e } catch { throw NetError.offline }
        pushCookiesToWeb()
        authed = true
    }

    func logout() {
        for c in HTTPCookieStorage.shared.cookies(for: Site.url) ?? [] { HTTPCookieStorage.shared.deleteCookie(c) }
        let store = WKWebsiteDataStore.default()
        store.httpCookieStore.getAllCookies { cs in for c in cs { store.httpCookieStore.delete(c) } }
        authed = false
    }

    func pushCookiesToWeb() {
        for c in HTTPCookieStorage.shared.cookies(for: Site.url) ?? [] { WKWebsiteDataStore.default().httpCookieStore.setCookie(c) }
    }

    private func pullCookiesFromWeb() async {
        let host = Site.url.host ?? ""
        let cs: [HTTPCookie] = await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        for c in cs {
            let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            if host == d || host.hasSuffix("." + d) { HTTPCookieStorage.shared.setCookie(c) }
        }
    }

    // MARK: 请求
    func data(_ path: String, method: String = "GET", json: Any? = nil) async throws -> Data {
        #if DEBUG
        if Demo.on, let d = Demo.data(path, method) { authed = true; return d }
        #endif
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        if let j = json {
            req.httpBody = try JSONSerialization.data(withJSONObject: j)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        do {
            let (d, r) = try await session.data(for: req)
            let code = (r as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { authed = false; throw NetError.unauthorized }
            if code >= 400 {
                let m = ((try? JSONSerialization.jsonObject(with: d)) as? J)?.str("error") ?? ""
                throw NetError.server(m.isEmpty ? "服务器出错（\(code)）" : m)
            }
            if authed != true { authed = true }
            return d
        } catch let e as NetError { throw e } catch { throw NetError.offline }
    }

    /// 上传图片（multipart）：错题照片等
    func upload(_ path: String, field: String = "files", fields: [String: String] = [:], images: [Data]) async throws -> J {
        let boundary = "B" + UUID().uuidString
        var body = Data()
        for (k, v) in fields { body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".utf8)) }
        for (i, d) in images.enumerated() {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"p\(i).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
            body.append(d)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 60
        do {
            let (d, r) = try await session.upload(for: req, from: body)
            let code = (r as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { authed = false; throw NetError.unauthorized }
            let j = (try? JSONSerialization.jsonObject(with: d)) as? J ?? [:]
            if code >= 400 { throw NetError.server(j.str("error").isEmpty ? "上传失败（\(code)）" : j.str("error")) }
            return j
        } catch let e as NetError { throw e } catch { throw NetError.offline }
    }

    func any(_ path: String, method: String = "GET", json: Any? = nil) async throws -> Any {
        let d = try await data(path, method: method, json: json)
        return (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) ?? [:]
    }
    func obj(_ path: String, method: String = "GET", json: Any? = nil) async throws -> J { (try await any(path, method: method, json: json)) as? J ?? [:] }
    func list(_ path: String) async throws -> [J] { (try await any(path)) as? [J] ?? [] }

    /// GET 并缓存到本地
    func fresh(_ path: String) async throws -> Any {
        let d = try await data(path)
        LocalStore.shared.cachePut(path, d)
        return (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) ?? [:]
    }
    func cached(_ path: String) -> Any? {
        guard let d = LocalStore.shared.cacheGet(path) else { return nil }
        return try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
    }

    /// 流式读取（Max 聊天、微课）：边收边回调完整文本
    func stream(_ path: String, json: Any, onText: @escaping (String) -> Void) async throws {
        #if DEBUG
        if Demo.on {
            let full = path.contains("lesson") ? Demo.lessonText : Demo.chatText
            var shown = ""
            for ch in full { shown.append(ch); if shown.count % 6 == 0 { onText(shown); try await Task.sleep(nanoseconds: 20_000_000) } }
            onText(full)
            return
        }
        #endif
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 120
        do {
            let (bytes, resp) = try await session.bytes(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { authed = false; throw NetError.unauthorized }
            if code != 200 {
                var body = Data()
                for try await b in bytes { body.append(b) }
                let m = ((try? JSONSerialization.jsonObject(with: body)) as? J)?.str("error") ?? ""
                throw NetError.server(m.isEmpty ? "服务器出错（\(code)）" : m)
            }
            var pending = Data(), text = ""
            for try await b in bytes {
                pending.append(b)
                if let s = String(data: pending, encoding: .utf8) { text += s; pending.removeAll(); onText(text) } // 半个汉字时先等下一个字节
            }
        } catch let e as NetError { throw e } catch is CancellationError { throw CancellationError() } catch { throw NetError.offline }
    }
}

/// 先显示本地缓存，再向服务器要最新的（该缓存的缓存，该请求的请求）
@MainActor
final class Feed: ObservableObject {
    @Published var value: Any?
    @Published var loading = false
    @Published var offline = false
    @Published var error: String?
    private(set) var path: String
    init(_ path: String) { self.path = path; value = API.shared.cached(path) }

    /// 换一个接口地址（比如错题本切到「错题文件夹」）：先显示这个地址的缓存，再更新
    func use(_ p: String) async {
        guard p != path else { return }
        path = p
        value = API.shared.cached(p)
        await load()
    }

    var obj: J { value as? J ?? [:] }
    var list: [J] { value as? [J] ?? [] }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            value = try await API.shared.fresh(path)
            offline = false
            error = nil
        } catch NetError.offline {
            offline = true
        } catch NetError.unauthorized {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
