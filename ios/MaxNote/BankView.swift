import SwiftUI

enum BankMode { case bank, wrong }

/// 题库 / 错题本：题目从服务器数据库拉取（先显示本地缓存，再更新），在手机上渲染成原生列表
struct BankView: View {
    let mode: BankMode
    @EnvironmentObject private var router: Router
    @StateObject private var feed: Feed
    @StateObject private var sum = Feed("/api/max/wrongsum")
    @State private var tab = "active"
    @State private var scope = 0 // 题库：0 在用 / 1 全集
    @State private var query = ""
    @State private var subject = ""
    @State private var library: [J] = []
    @State private var libOffline = false
    @State private var selecting = false
    @State private var selection = Set<Int>()
    @State private var organizing = false

    init(mode: BankMode) {
        self.mode = mode
        _feed = StateObject(wrappedValue: Feed(mode == .bank ? "/api/bank" : "/api/wrong?tab=active"))
    }

    private var items: [J] {
        let base = (mode == .bank && scope == 1) ? library : feed.obj.arr("items")
        return base.filter { q in
            (subject.isEmpty || q.str("subject") == subject) &&
            (query.isEmpty || q.str("stem").localizedCaseInsensitiveContains(query) || q.str("topic").localizedCaseInsensitiveContains(query) || q.str("category").localizedCaseInsensitiveContains(query))
        }
    }
    private var subjects: [String] { Array(Set((mode == .bank && scope == 1 ? library : feed.obj.arr("items")).map { $0.str("subject") })).sorted() }
    private var today: String { feed.obj.str("today") }

    /// 科目 › 考点 分组
    private var groups: [(key: String, rows: [J])] {
        let d = Dictionary(grouping: items) { q -> String in
            let t = q.str("topic").isEmpty ? (q.str("category").isEmpty ? "未分考点" : q.str("category")) : q.str("topic")
            return q.str("subject") + " › " + t
        }
        return d.keys.sorted().map { ($0, d[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                headerPicker.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if feed.offline { Section { OfflineBadge() } }
                if mode == .wrong && tab == "active" { WrongSummary(sum: sum, organizing: $organizing, onChanged: { Task { await reload() } }) }
                if groups.isEmpty && !feed.loading {
                    EmptyHint(icon: mode == .wrong ? "checkmark.seal" : "tray", text: mode == .wrong ? (tab == "mastered" ? "文件夹是空的，错题重做做对后会放进来" : "还没有错题，做错的题会自动收进来") : "没有题")
                        .listRowBackground(Color.clear)
                }
                ForEach(groups, id: \.key) { g in
                    Section {
                        ForEach(Array(g.rows.enumerated()), id: \.offset) { _, q in
                            row(q).listRowBackground(Color.card)
                        }
                    } header: {
                        HStack {
                            Text(g.key)
                            Spacer()
                            Text("\(g.rows.count) 题").foregroundStyle(.secondary)
                            if mode == .wrong && tab == "active" {
                                Button("重做") { router.practice(ids: g.rows.map { $0.int("id") }, title: g.key) }.font(.footnote.weight(.semibold)).textCase(nil)
                            } else if mode == .bank && scope == 0 {
                                Button("练这组") { router.practice(ids: g.rows.map { $0.int("id") }, title: g.key) }.font(.footnote.weight(.semibold)).textCase(nil)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(WarmBackground())
            .tint(Color.brand)
            .navigationTitle(mode == .bank ? "题库" : "错题本")
            .navigationDestination(for: Int.self) { QuestionDetail(id: $0, onChanged: { Task { await reload() } }) }
            .searchable(text: $query, prompt: "搜索题干、考点")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("科目", selection: $subject) {
                            Text("全部科目").tag("")
                            ForEach(subjects, id: \.self) { Text($0).tag($0) }
                        }
                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selecting.toggle(); selection.removeAll() } } label: { Label(selecting ? "完成选择" : "选择多题", systemImage: "checkmark.circle") }
                        Button { router.print(ids: []) } label: { Label("A4 排版打印", systemImage: "printer") }
                        if mode == .bank { Button { Task { await classify() } } label: { Label("让 Max 整理分类", systemImage: "folder.badge.gearshape") } }
                    } label: { Image(systemName: subject.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
                }
            }
            .safeAreaInset(edge: .bottom) { if selecting && !selection.isEmpty { selectionBar } }
            .refreshable { await reload() }
            .task { await reload() }
            .task(id: "\(scope)|\(query)|\(subject)") { if mode == .bank && scope == 1 { await loadLibrary() } }
            .onReceive(NotificationCenter.default.publisher(for: .bankChanged)) { _ in Task { await reload() } }
        }
    }

    private var headerPicker: some View {
        Section {
            Picker("", selection: mode == .bank ? $scope : Binding(get: { tab == "active" ? 0 : 1 }, set: { tab = $0 == 0 ? "active" : "mastered"; Task { await switchTab() } })) {
                if mode == .bank { Text("在用").tag(0); Text("全集（含已隐藏）").tag(1) } else { Text("复习中").tag(0); Text("错题文件夹").tag(1) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Button("练 \(selection.count) 题") { router.practice(ids: Array(selection), title: "所选题目") }.buttonStyle(GlassButtonStyle(prominent: true))
            Button("打印") { router.print(ids: Array(selection)) }.buttonStyle(GlassButtonStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func row(_ q: J) -> some View {
        let id = q.int("id")
        let content = HStack(alignment: .top, spacing: 12) {
            if selecting {
                Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(id) ? Color.brand : .secondary)
                    .font(.title3)
                    .transition(.scale.combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if !q.str("tag").isEmpty { Chip(text: q.str("tag"), tint: .secondary) }
                    if mode == .wrong, !q.str("max_reason").isEmpty { Chip(text: "错因：" + q.str("max_reason"), tint: Color.brand) }
                }
                Text(plain(q.str("stem").replacingOccurrences(of: "^[^·]*·", with: "", options: .regularExpression))).font(.body).lineLimit(3)
            }
            Spacer(minLength: 4)
            stateChip(q)
        }
        return Group {
            if selecting {
                content.contentShape(Rectangle()).onTapGesture { Haptic.select(); if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
            } else {
                NavigationLink(value: id) { content }
            }
        }
        .swipeActions(edge: .trailing) {
            Button { router.practice(ids: [id]) } label: { Label("练", systemImage: "play.fill") }.tint(Color.brand)
        }
    }

    @ViewBuilder private func stateChip(_ q: J) -> some View {
        let (t, c) = state(q)
        Chip(text: t, tint: c)
    }

    private func state(_ q: J) -> (String, Color) {
        if q.int("pending") > 0 { return ("待批改", Color.mute) }
        if mode == .wrong { return tab == "mastered" ? ("已改对", Color.mute) : q.int("last") == 1 ? ("重做已对", Color.mute) : ("待重做", Color.brand) }
        if scope == 1, !q.str("state").isEmpty { return (q.str("state"), q.str("state") == "在用" ? Color.brand : .secondary) }
        if !q.str("due").isEmpty && q.str("due") > today { return ("\(Int(q.str("due").dropFirst(5).prefix(2)) ?? 0)月\(Int(q.str("due").suffix(2)) ?? 0)日做", .secondary) }
        return q.int("tries") == 0 ? ("未做", Color.mute) : q.int("last") == 1 ? ("做对", Color.mute) : ("做错", Color.brand)
    }

    private func reload() async {
        await feed.load()
        if mode == .wrong { await sum.load() }
        if mode == .bank && scope == 1 { await loadLibrary() }
    }

    /// 让 Max 合并同义考点、归章节（后台整理，轮询结果）
    private func classify() async {
        do {
            _ = try await API.shared.obj("/api/max/classify", method: "POST", json: [:])
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let s = try? await API.shared.obj("/api/max/classify"), s.str("status") != "running" { break }
            }
            Haptic.ok(); await reload()
        } catch { Haptic.bad() }
    }

    private func switchTab() async {
        await feed.use("/api/wrong?tab=" + tab)
    }

    private func loadLibrary() async {
        let path = "/api/library?limit=100&q=" + query.urlEnc + "&subject=" + subject.urlEnc
        do {
            library = (try await API.shared.obj(path)).arr("items")
            libOffline = false
        } catch {
            // 没网：用本地 SQLite 副本搜
            library = LocalStore.shared.search(query, subject: subject).map { r in
                ["id": r.id, "subject": r.subject, "category": r.category, "topic": r.topic, "tag": r.tag, "stem": r.subject + "·" + r.stem, "state": r.state, "tries": 0, "wrongs": r.wrongs] as J
            }
            libOffline = true
        }
    }
}

/// 错题本顶部：错因统计 + Max 总结 + 一键整理 / 学习诊断
struct WrongSummary: View {
    @EnvironmentObject private var router: Router
    @ObservedObject var sum: Feed
    @Binding var organizing: Bool
    let onChanged: () -> Void
    @State private var note: String?

    var body: some View {
        let s = sum.obj
        if s.int("total") > 0 {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("错因分析 · \(s.int("total")) 道错题").font(.headline)
                    if !s.str("summary").isEmpty { Text(s.str("summary")).font(.subheadline) }
                    let reasons = (s["max"] as? [String: Any] ?? [:]).compactMap { k, v -> (String, Int)? in (v as? Int).map { (k, $0) } }.filter { $0.0 != "待分析" }.sorted { $0.1 > $1.1 }.prefix(3)
                    ForEach(Array(reasons), id: \.0) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(r.0).font(.footnote).lineLimit(1); Spacer(); Text("\(r.1)").font(.footnote).foregroundStyle(Color.mute) }
                            ProgressView(value: Double(r.1), total: Double(max(1, s.int("total")))).tint(Color.brand)
                        }
                    }
                    HStack {
                        Button {
                            organize()
                        } label: { Label(organizing ? "整理中…" : (s.int("todo") > 0 ? "一键整理 · \(s.int("todo"))" : "一键整理"), systemImage: "folder.badge.gearshape").lineLimit(1).fixedSize() }
                            .disabled(organizing)
                        Button { router.ask("分析这页的错题：我最薄弱的 3 个考点、典型错因，接下来该怎么练？给我练习按钮", study: true) } label: { Label("学习诊断", systemImage: "sparkles").lineLimit(1).fixedSize() }
                        Spacer(minLength: 0)
                    }
                    .buttonStyle(BrandButtonStyle())
                    if let n = note { Text(n).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func organize() {
        organizing = true; note = nil
        Task {
            do {
                for _ in 0..<5 {
                    let r = try await API.shared.obj("/api/max/organize", method: "POST", json: [:])
                    if r.int("left") == 0 { break }
                }
                _ = try await API.shared.obj("/api/max/classify", method: "POST", json: [:])
                _ = try? await API.shared.any("/api/max/wrongsum?force=1")
                Haptic.ok(); note = "错题本整理好了"
                onChanged()
            } catch { Haptic.bad(); note = error.localizedDescription }
            organizing = false
        }
    }
}

/// 单题详情：答案、解析、做题历史；操作：练这题、放回练习、问 Max、标为已掌握、删除
struct QuestionDetail: View {
    let id: Int
    let onChanged: () -> Void
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @StateObject private var feed: Feed
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var note: J?

    init(id: Int, onChanged: @escaping () -> Void) {
        self.id = id
        self.onChanged = onChanged
        _feed = StateObject(wrappedValue: Feed("/api/question/\(id)"))
    }

    var body: some View {
        let q = feed.obj
        List {
            if feed.offline { Section { OfflineBadge() } }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Chip(text: q.str("subject"))
                        if !q.str("topic").isEmpty { Chip(text: q.str("topic"), tint: Color.mute) }
                        if !q.str("tag").isEmpty { Chip(text: q.str("tag"), tint: Color.mute) }
                    }
                    Text(plain(q.str("stem").replacingOccurrences(of: "^[^·]*·", with: "", options: .regularExpression))).font(.title3).foregroundStyle(Color.ink)
                    ForEach(q.strs("options"), id: \.self) { Text(plain($0)).foregroundStyle(Color.ink) }
                    if q.has("fig"), let fig = q["fig"], !(fig is NSNull) { FigView(fig: fig) }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.card)
            }
            if q.bool("locked") {
                // 没做过的题：做完才给答案和解析
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("还没做过这道题：做完才显示答案和解析", systemImage: "lock").font(.subheadline).foregroundStyle(Color.mute)
                        Button("练这题") { router.practice(ids: [id]) }.buttonStyle(BrandButtonStyle(filled: true))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.card)
                }
            } else {
                Section("正确答案") { Text(plain(q.strs("answer").joined(separator: " / ")).isEmpty ? "（无）" : plain(q.strs("answer").joined(separator: " / "))).font(.headline).foregroundStyle(Color.ink).listRowBackground(Color.card) }
                if !q.str("explanation").isEmpty { Section("解析") { Text(plain(q.str("explanation"))).foregroundStyle(Color.ink).listRowBackground(Color.card) } }
            }
            let attempts = q.arr("attempts")
            if !attempts.isEmpty {
                Section("做题记录") {
                    ForEach(Array(attempts.enumerated()), id: \.offset) { _, a in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: a.str("status") == "待批改" ? "hourglass" : a.int("is_correct") == 1 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(a.str("status") == "待批改" ? Color.mute : a.int("is_correct") == 1 ? Color.ink : Color.brand)
                                Text(a.str("answer_text").isEmpty ? "（空）" : plain(a.str("answer_text"))).lineLimit(2)
                                Spacer()
                                Text(String(a.str("created_at").prefix(10))).font(.caption).foregroundStyle(.secondary)
                            }
                            if !a.str("error_reason").isEmpty { Text("错因：" + a.str("error_reason")).font(.caption).foregroundStyle(Color.brand) }
                            if !a.str("comment").isEmpty { Text(a.str("comment")).font(.caption).foregroundStyle(.secondary) }
                        }
                        .listRowBackground(Color.card)
                    }
                }
            }
            if let n = note, let u = URL(string: n.str("url")) {
                Section { Link(destination: u) { Label("Notion 笔记：" + n.str("title"), systemImage: "book") }.listRowBackground(Color.card) }
            }
            if let t = toast { Section { Text(t).font(.footnote).foregroundStyle(.secondary) } }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WarmBackground())
        .navigationTitle("题目详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { router.practice(ids: [id]) } label: { Label("练这题", systemImage: "play.fill") }
                    Button { router.ask("这道题怎么想？先别说答案，给我思路。", ctx: ["q": id], study: false) } label: { Label("问 Max", systemImage: "sparkles") }
                    Button { router.print(ids: [id]) } label: { Label("打印", systemImage: "printer") }
                    Button { Task { await act("/api/question/\(id)/restore", "已放回练习") } } label: { Label("放回练习", systemImage: "arrow.uturn.backward") }
                    Button { Task { await act("/api/question/\(id)/master", "已标为已掌握") } } label: { Label("标为已掌握", systemImage: "checkmark.seal") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("删除这道题？（做题记录会保留）", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await act("/api/question/\(id)/delete", nil); dismiss() } }
        }
        .task {
            await feed.load()
            // 考点 → Notion 笔记链接（对照表里有才显示）
            let q = feed.obj
            if !q.str("topic").isEmpty, let r = try? await API.shared.obj("/api/notion?subject=\(q.str("subject").urlEnc)&topic=\(q.str("topic").urlEnc)") { note = r.dict("note") }
        }
    }

    private func act(_ path: String, _ ok: String?) async {
        do {
            _ = try await API.shared.any(path, method: "POST", json: [:])
            if let ok = ok { toast = ok; Haptic.ok() }
            NotificationCenter.default.post(name: .bankChanged, object: nil)
            onChanged()
        } catch { toast = error.localizedDescription; Haptic.bad() }
    }
}
