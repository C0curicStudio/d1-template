import Foundation
import SQLite3

struct QRow: Identifiable, Hashable {
    let id: Int
    let subject: String
    let category: String
    let topic: String
    let type: String
    let tag: String
    let stem: String
    let options: [String]
    let answer: [String]
    let explanation: String
    let state: String
    let wrongs: Int
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 本地题库副本（SQLite）：从服务器同步下来，没网也能搜、能看答案和解析。
final class LocalStore {
    static let shared = LocalStore()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "maxnote.localstore")

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("maxnote.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK { db = nil; return }
        run("CREATE TABLE IF NOT EXISTS questions(id INTEGER PRIMARY KEY, subject TEXT, category TEXT, topic TEXT, type TEXT, tag TEXT, stem TEXT, options TEXT, answer TEXT, explanation TEXT, state TEXT, wrongs INTEGER, created_at TEXT)")
        run("CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT)")
        run("CREATE TABLE IF NOT EXISTS cache(k TEXT PRIMARY KEY, v BLOB, at REAL)")
    }

    @discardableResult
    private func run(_ sql: String) -> Bool {
        guard let db = db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func text(_ stmt: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }

    private func strings(_ s: String) -> [String] {
        guard let d = s.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return a
    }

    private func json(_ v: Any?) -> String {
        guard let v = v, JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v), let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }

    /// 接口结果缓存（GET）：没网时先给上次的
    func cacheGet(_ k: String) -> Data? {
        queue.sync {
            guard let db = db else { return nil }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "SELECT v FROM cache WHERE k = ?", -1, &st, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(st, 1, k, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(st) == SQLITE_ROW, let p = sqlite3_column_blob(st, 0) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(st, 0)))
        }
    }

    func cachePut(_ k: String, _ d: Data) {
        queue.sync {
            guard let db = db, d.count < 2_000_000 else { return }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO cache(k, v, at) VALUES(?, ?, ?)", -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(st, 1, k, -1, SQLITE_TRANSIENT)
            _ = d.withUnsafeBytes { sqlite3_bind_blob(st, 2, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) }
            sqlite3_bind_double(st, 3, Date().timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func clearCache() { queue.sync { _ = run("DELETE FROM cache") } }

    func meta(_ k: String) -> String? {
        queue.sync {
            guard let db = db else { return nil }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "SELECT v FROM meta WHERE k = ?", -1, &st, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(st, 1, k, -1, SQLITE_TRANSIENT)
            return sqlite3_step(st) == SQLITE_ROW ? text(st, 0) : nil
        }
    }

    func count() -> Int {
        queue.sync {
            guard let db = db else { return 0 }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM questions", -1, &st, nil) == SQLITE_OK, sqlite3_step(st) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(st, 0))
        }
    }

    /// 用服务器的完整快照替换本地副本（一个事务，中途失败不会留下半份数据）
    func replaceAll(_ items: [[String: Any]], etag: String?) {
        queue.sync {
            guard let db = db else { return }
            run("BEGIN")
            run("DELETE FROM questions")
            var st: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO questions(id, subject, category, topic, type, tag, stem, options, answer, explanation, state, wrongs, created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { run("ROLLBACK"); return }
            for it in items {
                guard let id = it["id"] as? Int else { continue }
                sqlite3_reset(st)
                sqlite3_bind_int(st, 1, Int32(id))
                let cols: [String] = [
                    (it["subject"] as? String) ?? "", (it["category"] as? String) ?? "", (it["topic"] as? String) ?? "",
                    (it["type"] as? String) ?? "", (it["tag"] as? String) ?? "", (it["stem"] as? String) ?? "",
                    json(it["options"]), json(it["answer"]), (it["explanation"] as? String) ?? "", (it["state"] as? String) ?? "",
                ]
                for (i, c) in cols.enumerated() { sqlite3_bind_text(st, Int32(i + 2), c, -1, SQLITE_TRANSIENT) }
                sqlite3_bind_int(st, 12, Int32((it["wrongs"] as? Int) ?? 0))
                sqlite3_bind_text(st, 13, (it["created_at"] as? String) ?? "", -1, SQLITE_TRANSIENT)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
            if let e = etag {
                var m: OpaquePointer?
                if sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO meta(k, v) VALUES('etag', ?)", -1, &m, nil) == SQLITE_OK {
                    sqlite3_bind_text(m, 1, e, -1, SQLITE_TRANSIENT)
                    sqlite3_step(m)
                }
                sqlite3_finalize(m)
            }
            run("COMMIT")
        }
    }

    func subjects() -> [String] {
        queue.sync {
            guard let db = db else { return [] }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, "SELECT DISTINCT subject FROM questions ORDER BY subject", -1, &st, nil) == SQLITE_OK else { return [] }
            var out: [String] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(text(st, 0)) }
            return out
        }
    }

    func search(_ q: String, subject: String) -> [QRow] {
        queue.sync {
            guard let db = db else { return [] }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            var sql = "SELECT id, subject, category, topic, type, tag, stem, options, answer, explanation, state, wrongs FROM questions WHERE 1=1"
            let like = "%" + q.trimmingCharacters(in: .whitespaces) + "%"
            if !q.trimmingCharacters(in: .whitespaces).isEmpty { sql += " AND (stem LIKE ?1 OR topic LIKE ?1 OR category LIKE ?1 OR explanation LIKE ?1)" }
            if !subject.isEmpty { sql += " AND subject = ?2" }
            sql += " ORDER BY id DESC LIMIT 300"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            if sql.contains("?1") { sqlite3_bind_text(st, 1, like, -1, SQLITE_TRANSIENT) }
            if sql.contains("?2") { sqlite3_bind_text(st, 2, subject, -1, SQLITE_TRANSIENT) }
            var out: [QRow] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(QRow(id: Int(sqlite3_column_int(st, 0)), subject: text(st, 1), category: text(st, 2), topic: text(st, 3), type: text(st, 4), tag: text(st, 5),
                                stem: text(st, 6), options: strings(text(st, 7)), answer: strings(text(st, 8)), explanation: text(st, 9), state: text(st, 10), wrongs: Int(sqlite3_column_int(st, 11))))
            }
            return out
        }
    }
}
