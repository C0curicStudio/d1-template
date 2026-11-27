import Foundation

/// 网站地址：默认是部署好的 Workers 地址，可以在「无法连接」卡片里改（存在本机）。
enum Site {
    static let defaultURL = "https://lxb.maxcc.cc.cd"
    private static let key = "siteURL"

    /// 旧版本存过的 workers.dev 地址：换域名后自动改用新域名
    static func migrate() {
        if let s = UserDefaults.standard.string(forKey: key), s.contains("workers.dev") { UserDefaults.standard.removeObject(forKey: key) }
    }

    static var url: URL {
        let s = UserDefaults.standard.string(forKey: key) ?? defaultURL
        return URL(string: s) ?? URL(string: defaultURL)!
    }

    static var text: String { UserDefaults.standard.string(forKey: key) ?? defaultURL }

    /// 保存前规整：补 https://，去掉结尾斜杠；不合法返回 nil
    @discardableResult
    static func save(_ raw: String) -> Bool {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { UserDefaults.standard.removeObject(forKey: key); return true }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let u = URL(string: s), u.host != nil else { return false }
        UserDefaults.standard.set(s, forKey: key)
        return true
    }
}
