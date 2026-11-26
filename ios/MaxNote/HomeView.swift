import SwiftUI

extension Notification.Name { static let bankChanged = Notification.Name("bankChanged") }

struct HomeView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var feed = Feed("/api/home?brief=1")
    @StateObject private var study = Feed("/api/study")

    private var h: J { feed.obj }
    private var brief: J { h.dict("brief") ?? [:] }
    private var plan: J { study.obj.dict("plan") ?? [:] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if feed.offline { OfflineBadge().padding(.horizontal, 4) }

                    HStack(spacing: 10) {
                        StatTile(value: h.int("streak"), label: h.bool("done_today") ? "连续练习天数" : "连续天数 · 今天还没练")
                        StatTile(value: h.int("today_count"), label: "今日待练")
                        StatTile(value: h.int("right7"), label: "近 7 天做对")
                    }

                    Button { Haptic.tap(); router.practiceToday() } label: {
                        Label("今日练习（\(h.int("today_count")) 题）", systemImage: "play.fill")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))

                    if h.int("pending_grades") > 0 || h.int("pending_uploads") > 0 {
                        Label("\(h.int("pending_grades")) 题等 Claude 批改 · \(h.int("pending_uploads")) 张照片待处理", systemImage: "hourglass")
                            .font(.footnote).foregroundStyle(Color.mute).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !brief.str("say").isEmpty { briefCard }
                    planCard
                    subjectsCard
                    recentCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 130)
            }
            .background(WarmBackground())
            .navigationTitle("MAX NOTE")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { router.print(ids: []) } label: { Label("A4 排版打印", systemImage: "printer") }
                        Button { router.sheet = .settings } label: { Label("设置", systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .refreshable { await feed.load(); await study.load() }
            .task { await feed.load(); await study.load() }
            .onReceive(NotificationCenter.default.publisher(for: .bankChanged)) { _ in Task { await feed.load() } }
        }
    }

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) { MaxLogo(size: 22); Text("Max 今日建议").font(.headline).foregroundStyle(Color.ink) }
            Text(brief.str("say")).font(.body).foregroundStyle(Color.ink)
            let topics = Array(brief.arr("topics").prefix(3))
            if !topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(Array(topics.enumerated()), id: \.offset) { _, t in Chip(text: "\(t.str("subject")) · \(t.str("topic"))", tint: .red) } }
                }
            }
            let order = (brief["order"] as? [Int]) ?? [], weak = (brief["weakIds"] as? [Int]) ?? []
            HStack(spacing: 8) {
                if !order.isEmpty { Button("按推荐做（\(order.count)）") { router.practice(ids: order, title: "按推荐做") }.buttonStyle(BrandButtonStyle(filled: true)) }
                if !weak.isEmpty { Button("练薄弱点（\(weak.count)）") { router.practice(ids: weak, title: "薄弱点") }.buttonStyle(BrandButtonStyle()) }
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    @ViewBuilder private var planCard: some View {
        let steps = plan.arr("steps")
        if !steps.isEmpty {
            VStack(spacing: 4) {
                SectionTitle("今日学习计划")
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        PlanRow(index: i + 1, step: s)
                        if i < steps.count - 1 { Divider().overlay(Color.hairline) }
                    }
                }
                .card(14)
                if !plan.str("say").isEmpty { Text(plan.str("say")).font(.footnote).foregroundStyle(Color.mute).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.top, 2) }
            }
        }
    }

    @ViewBuilder private var subjectsCard: some View {
        let subjects = h.arr("subjects")
        VStack(spacing: 4) {
            SectionTitle("按科目练")
            if subjects.isEmpty {
                EmptyHint(icon: "tray", text: "还没有题：拍照上传错题或让 Claude 出题").card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(subjects.enumerated()), id: \.offset) { i, s in
                        Button { router.practice(subject: s.str("subject")) } label: {
                            HStack {
                                Text(s.str("subject")).font(.headline).foregroundStyle(Color.ink)
                                Spacer()
                                Text(s.int("undone") > 0 ? "\(s.int("undone")) 题未做" : "共 \(s.int("total")) 题").font(.subheadline).foregroundStyle(Color.mute)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.mute.opacity(0.6))
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PressRowStyle())
                        if i < subjects.count - 1 { Divider().overlay(Color.hairline) }
                    }
                }
                .card(16)
            }
        }
    }

    @ViewBuilder private var recentCard: some View {
        let recent = h.arr("recent")
        if !recent.isEmpty {
            VStack(spacing: 4) {
                SectionTitle("最近推送的题")
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { i, r in
                        Button { router.practice(ids: [r.int("id")]) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Chip(text: r.str("subject")); if !r.str("tag").isEmpty { Chip(text: r.str("tag"), tint: Color.mute) } }
                                Text(plain(r.str("stem"))).font(.subheadline).foregroundStyle(Color.ink).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(PressRowStyle())
                        if i < recent.count - 1 { Divider().overlay(Color.hairline) }
                    }
                }
                .card(16)
            }
        }
    }
}

struct PlanRow: View {
    @EnvironmentObject private var router: Router
    let index: Int
    let step: J

    var body: some View {
        let kind = step.str("kind"), topic = step.str("topic")
        HStack(spacing: 12) {
            Text("\(index)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(kindColor(kind), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.replacingOccurrences(of: "/", with: " › ")).font(.body.weight(.medium)).foregroundStyle(Color.ink)
                Text(step.str("why")).font(.caption).foregroundStyle(Color.mute)
            }
            Spacer(minLength: 8)
            Button(kind == "learn" ? "学" : "练 \(step.int("n"))") {
                Haptic.tap()
                if kind == "learn" { router.lesson = LessonSpec(topic: topic) } else { router.practice(topic: topic) }
            }
            .buttonStyle(BrandButtonStyle())
        }
        .padding(.vertical, 10)
    }

    private func kindColor(_ k: String) -> Color { k == "learn" ? .blue : k == "review" ? .green : Color.brand }
}
