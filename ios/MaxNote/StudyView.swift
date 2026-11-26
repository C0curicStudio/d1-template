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
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 120)
            }
            .background(WarmBackground())
            .navigationTitle("学习台")
            .searchable(text: $query, prompt: "搜索考点")
            .refreshable { await feed.load(); plan = nil }
            .task { await feed.load() }
        }
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
                    if let e = error { Text(e).foregroundStyle(Color.brand) }
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
