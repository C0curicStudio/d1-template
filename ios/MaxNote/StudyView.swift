import SwiftUI

/// 学习台：掌握度地图 + AI 学习计划 + 微课 + 答疑入口
struct StudyView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var feed = Feed("/api/study")
    @State private var replanning = false
    @State private var plan: J?
    @State private var query = ""

    private var d: J { feed.obj }
    private var curPlan: J { plan ?? d.dict("plan") ?? [:] }
    private var rows: [J] { d.arr("rows").filter { query.isEmpty || $0.str("topic").localizedCaseInsensitiveContains(query) || $0.str("subject").localizedCaseInsensitiveContains(query) } }
    private var subjects: [String] { Array(Set(rows.map { $0.str("subject") })).sorted() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if feed.offline { OfflineBadge().padding(.horizontal, 4) }
                    let n = d.int("n"), right = d.int("right")
                    HStack(spacing: 10) {
                        StatTile(value: n, label: "近 60 天练过")
                        StatTile(value: n > 0 ? Int((Double(right) / Double(n) * 100).rounded()) : 0, label: "正确率 %")
                        StatTile(value: d.arr("rows").filter { $0.str("level") == "薄弱" }.count, label: "薄弱考点")
                    }

                    let steps = curPlan.arr("steps")
                    VStack(spacing: 4) {
                        HStack {
                            Text("今日学习计划").font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                            Chip(text: (curPlan["ai"] as? Bool) == true ? "AI 排的" : "按薄弱度排的", tint: Color.mute)
                            Spacer()
                        }
                        .padding(.horizontal, 4).padding(.top, 10)
                        VStack(spacing: 0) {
                            if steps.isEmpty { Text("还没有学习数据，先去做几道题").foregroundStyle(Color.mute).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading) }
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                                PlanRow(index: i + 1, step: s)
                                if i < steps.count - 1 { Divider().overlay(Color.hairline) }
                            }
                            Divider().overlay(Color.hairline)
                            Button { replan() } label: {
                                Label(replanning ? "AI 排计划中…" : "让 AI 重新排计划", systemImage: "arrow.triangle.2.circlepath").font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                                    .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PressRowStyle()).disabled(replanning)
                        }
                        .card(14)
                        if !curPlan.str("say").isEmpty { Text(curPlan.str("say")).font(.footnote).foregroundStyle(Color.mute).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6) }
                    }

                    ForEach(subjects, id: \.self) { s in
                        VStack(spacing: 4) {
                            SectionTitle(s)
                            VStack(spacing: 0) {
                                let rs = rows.filter { $0.str("subject") == s }
                                ForEach(Array(rs.enumerated()), id: \.offset) { i, r in
                                    MasteryRow(r: r)
                                    if i < rs.count - 1 { Divider().overlay(Color.hairline) }
                                }
                            }
                            .card(14)
                        }
                    }
                    if rows.isEmpty && !feed.loading { EmptyHint(icon: "chart.bar", text: "题库还是空的：拍照上传错题或让 Claude 出题后，这里会出现你的掌握度地图。") }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 170)
            }
            .background(WarmBackground())
            .navigationTitle("学习台")
            .searchable(text: $query, prompt: "搜索考点")
            .refreshable { await feed.load(); plan = nil }
            .task { await feed.load() }
            .safeAreaInset(edge: .bottom) { askBar }
        }
    }

    /// 底部的玻璃输入条（像系统「音乐」的迷你播放条）：点一下开始问
    private var askBar: some View {
        Button { Haptic.tap(); router.ask(study: true) } label: {
            HStack(spacing: 10) {
                MaxLogo(size: 22)
                Text("问 AI 助教：它能看到你的掌握度和错因").font(.subheadline).foregroundStyle(Color.mute).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(Color.brand)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.bottom, 62)
    }

    private func replan() {
        replanning = true
        Task {
            do { plan = try await API.shared.obj("/api/study/plan", method: "POST", json: ["force": true]); Haptic.ok() }
            catch { Haptic.bad() }
            replanning = false
        }
    }
}

struct MasteryRow: View {
    @EnvironmentObject private var router: Router
    let r: J

    var body: some View {
        let level = r.str("level"), topic = r.str("subject") + "/" + r.str("topic")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(r.str("topic")).font(.body.weight(.medium)).foregroundStyle(Color.ink)
                Chip(text: level, tint: levelColor(level))
                Spacer()
                Text(r.int("n") > 0 ? "\(r.int("n")) 题 · \(r.int("mastery"))%" : "\(r.int("total")) 题未练").font(.caption).foregroundStyle(Color.mute)
            }
            ProgressView(value: Double(r.has("mastery") ? r.int("mastery") : 0), total: 100).tint(levelColor(level))
            HStack(spacing: 10) {
                Button("学") { Haptic.tap(); router.lesson = LessonSpec(topic: topic) }.buttonStyle(BrandButtonStyle())
                Button("练 5 题") { Haptic.tap(); router.practice(topic: topic) }.buttonStyle(BrandButtonStyle())
            }
        }
        .padding(.vertical, 10)
    }
}

/// 知识点微课：流式生成
struct LessonView: View {
    let spec: LessonSpec
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let (body, acts) = splitActions(text)
                    if text.isEmpty && error == nil { HStack(spacing: 10) { ProgressView(); Text("AI 正在备课…").foregroundStyle(.secondary) } }
                    if let e = error { Text(e).foregroundStyle(.red) }
                    Text(md(body)).font(.body).lineSpacing(5).textSelection(.enabled)
                    if !busy {
                        HStack {
                            Button("没懂，换种讲法") { Task { await load(again: true) } }.buttonStyle(BrandButtonStyle())
                            Button("去练 5 题") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.practice(topic: spec.topic) } }.buttonStyle(BrandButtonStyle(filled: true))
                        }
                        .controlSize(.regular)
                        ForEach(acts) { a in if a.kind != .practice { Text(a.title).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.2), value: text.count / 40)
            }
            .background(WarmBackground())
            .navigationTitle(spec.topic.replacingOccurrences(of: "/", with: " › "))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load(again: false) }
        }
        .presentationDetents([.large])
    }

    private func load(again: Bool) async {
        busy = true; error = nil; text = ""
        do { try await API.shared.stream("/api/study/lesson", json: ["topic": spec.topic, "again": again]) { text = $0 } }
        catch { self.error = error.localizedDescription }
        busy = false
        if error == nil { Haptic.soft() }
    }
}

struct ChatMsg: Identifiable { let id = UUID(); let role: String; var text: String }

/// 和 Max 对话：流式、带学习数据 / 题目上下文
struct ChatView: View {
    let spec: ChatSpec
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var msgs: [ChatMsg] = []
    @State private var input = ""
    @State private var busy = false
    @State private var deep = false
    @State private var web = false
    @State private var pending: PendingAlert?
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if msgs.isEmpty { suggestions }
                        ForEach(msgs) { m in bubble(m).id(m.id).transition(.move(edge: .bottom).combined(with: .opacity)) }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: msgs.last?.text) { _ in if let l = msgs.last { proxy.scrollTo(l.id, anchor: .bottom) } }
            }
            .background(WarmBackground())
            .navigationTitle(spec.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle(isOn: $deep) { Label("深度思考", systemImage: "brain") }
                        Toggle(isOn: $web) { Label("联网搜索", systemImage: "globe") }
                        Button(role: .destructive) { msgs.removeAll() } label: { Label("清空对话", systemImage: "trash") }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .alert(item: $pending) { p in
                Alert(title: Text(p.action.arg), message: Text(p.message), primaryButton: .default(Text("确定")) { Task { await run(p.action, dry: false) } }, secondaryButton: .cancel())
            }
            .task {
                if let p = spec.prompt, msgs.isEmpty { send(p) } else { try? await Task.sleep(nanoseconds: 450_000_000); focus = true } // 从悬浮球打开：自动弹出键盘
            }
        }
        .presentationDetents([.large])
    }

    private struct PendingAlert: Identifiable { let id = UUID(); let action: MaxAction; let message: String }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可以问我").font(.footnote).foregroundStyle(.secondary)
            ForEach(spec.study ? ["我现在最该先补哪块？", "用一个例子讲讲我最薄弱的考点", "我总是犯哪类错？怎么改？"] : ["这题考什么知识点？", "我错在哪一步？", "给我一道类似的题"], id: \.self) { s in
                Button { send(s) } label: { Text(s).font(.subheadline).padding(.horizontal, 14).padding(.vertical, 9).glassCapsule(interactive: true) }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatMsg) -> some View {
        if m.role == "user" {
            Text(m.text).padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(.white).background(Color.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 50)
        } else {
            let (body, acts) = splitActions(m.text)
            VStack(alignment: .leading, spacing: 8) {
                if m.text.isEmpty { HStack(spacing: 8) { ProgressView(); Text("思考中…").foregroundStyle(.secondary) } }
                else { Text(md(body)).lineSpacing(4).textSelection(.enabled) }
                if !(busy && m.id == msgs.last?.id) {
                    ForEach(acts) { a in
                        Button { tap(a) } label: { Label(a.title, systemImage: a.kind == .practice ? "play.fill" : a.kind == .doit ? "checkmark.circle" : "arrow.right").font(.footnote.weight(.semibold)) }
                            .buttonStyle(BrandButtonStyle()).controlSize(.small)
                    }
                }
            }
            .padding(14).glassCard(cornerRadius: 20)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 20)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("问 Max…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($focus)
                .accessibilityIdentifier("chatInput")
                .padding(.horizontal, 14).padding(.vertical, 10)
            Button { send(input) } label: {
                Image(systemName: busy ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(input.isEmpty && !busy ? Color.secondary : Color.brand)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty && !busy)
            .accessibilityIdentifier("chatSend")
            .padding(.trailing, 6).padding(.bottom, 4)
        }
        .glassCard(cornerRadius: 26)
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    @State private var task: Task<Void, Never>?

    private func send(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if busy { task?.cancel(); busy = false; return }
        guard !t.isEmpty else { return }
        Haptic.tap(); input = ""
        msgs.append(ChatMsg(role: "user", text: t))
        let history = msgs.suffix(6).map { ["role": $0.role, "content": String($0.text.prefix(800))] }
        msgs.append(ChatMsg(role: "assistant", text: ""))
        let idx = msgs.count - 1
        var ctx = spec.ctx
        ctx["study"] = spec.study; ctx["topic"] = spec.topic; ctx["deep"] = deep; ctx["web"] = web; ctx["len"] = spec.study ? "l" : "m"
        busy = true
        task = Task {
            do { try await API.shared.stream("/api/max/chat", json: ["messages": history, "ctx": ctx]) { text in if idx < msgs.count { msgs[idx].text = text } } }
            catch is CancellationError {}
            catch { if idx < msgs.count { msgs[idx].text = error.localizedDescription } }
            busy = false
            Haptic.soft()
        }
    }

    private func tap(_ a: MaxAction) {
        Haptic.tap()
        switch a.kind {
        case .practice, .go:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.open(a) }
        case .doit: Task { await run(a, dry: true) }
        case .note: break
        }
    }

    /// Max 给的网站动作：先数一数、确认才做
    private func run(_ a: MaxAction, dry: Bool) async {
        do {
            let r = try await API.shared.obj("/api/max/do", method: "POST", json: ["name": a.arg, "arg": a.extra, "dry": dry])
            if dry {
                if r.bool("empty") { msgs.append(ChatMsg(role: "assistant", text: r.str("msg"))) } else { pending = PendingAlert(action: a, message: r.str("msg")) }
            } else {
                Haptic.ok(); msgs.append(ChatMsg(role: "assistant", text: "✅ " + r.str("msg")))
                NotificationCenter.default.post(name: .bankChanged, object: nil)
            }
        } catch { Haptic.bad(); msgs.append(ChatMsg(role: "assistant", text: error.localizedDescription)) }
    }
}
