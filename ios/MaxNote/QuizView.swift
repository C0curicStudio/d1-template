import SwiftUI

/// 做题：题目从服务器数据库拉取，选择 / 填空在原生界面里作答；带画板、手写、题图的题用网页版作答
struct QuizView: View {
    let spec: QuizSpec
    @Environment(\.dismiss) private var dismiss
    @State private var qs: [J] = []
    @State private var idx = 0
    @State private var picks: [Int: Set<String>] = [:] // 选择题：选的字母
    @State private var texts: [Int: String] = [:]      // 填空
    @State private var started: [Int: Date] = [:]
    @State private var phase: Phase = .loading
    @State private var error: String?
    @State private var hints: [Int: [String]] = [:]
    @State private var hinting = false
    @State private var attemptIds: [Int] = []
    @State private var results: [J] = []
    @State private var polling = false
    @State private var sheet: SheetKind?
    @EnvironmentObject private var router: Router
    @State private var confirmExit = false

    enum Phase { case loading, doing, submitting, result, empty, failed }

    private let native: Set<String> = ["single", "multi", "fill"]
    private func isNative(_ q: J) -> Bool { native.contains(q.str("type")) && !(q.has("fig") && !(q["fig"] is NSNull)) && !["coord", "grid", "calc", "circuit"].contains(q.str("board")) }
    private func answered(_ i: Int) -> Bool { !(picks[i] ?? []).isEmpty || !(texts[i] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                switch phase {
                case .loading: ProgressView("正在从数据库取题…")
                case .empty: EmptyHint(icon: "checkmark.seal", text: "这里没有要做的题了 · Bravo !")
                case .failed: failedView
                case .doing: doing
                case .submitting: ProgressView("交卷中…")
                case .result: resultView
                }
            }
            .navigationTitle(phase == .doing ? "\(idx + 1) / \(qs.count)" : spec.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .result ? "完成" : "退出") {
                        if phase == .doing && picks.values.contains(where: { !$0.isEmpty }) || phase == .doing && texts.values.contains(where: { !$0.isEmpty }) { confirmExit = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog("退出后这次作答不会保存", isPresented: $confirmExit, titleVisibility: .visible) { Button("退出", role: .destructive) { dismiss() } }
        }
        .interactiveDismissDisabled(phase == .doing)
        .sheet(item: $sheet) { SheetHost(kind: $0).environmentObject(router) }
        .task { await load() }
    }

    private var failedView: some View {
        VStack(spacing: 14) {
            EmptyHint(icon: "wifi.exclamationmark", text: error ?? "取题失败")
            Button("重试") { Task { await load() } }.buttonStyle(BrandButtonStyle(filled: true))
        }
    }

    // MARK: 作答
    private var doing: some View {
        let q = qs[idx]
        return VStack(spacing: 0) {
            ProgressView(value: Double(idx + 1), total: Double(max(1, qs.count))).tint(Color.brand).padding(.horizontal, 20).padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Chip(text: q.str("subject"))
                        if !q.str("tag").isEmpty { Chip(text: q.str("tag"), tint: .secondary) }
                        if !q.str("topic").isEmpty { Chip(text: q.str("topic"), tint: .secondary) }
                    }
                    Text(plain(q.str("stem"))).font(.title3).lineSpacing(5)
                    if isNative(q) { answerArea(q) } else { webOnly(q) }
                    hintArea(q)
                }
                .padding(20)
                .id(idx)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .onAppear { started[idx] = started[idx] ?? Date() }
    }

    @ViewBuilder private func answerArea(_ q: J) -> some View {
        let type = q.str("type")
        if type == "fill" {
            TextField("你的答案", text: Binding(get: { texts[idx] ?? "" }, set: { texts[idx] = $0 }))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).glassCard(cornerRadius: 16)
        } else {
            if type == "multi" { Text("多选").font(.caption).foregroundStyle(.secondary) }
            VStack(spacing: 10) {
                ForEach(q.strs("options"), id: \.self) { opt in
                    let letter = String(opt.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
                    let on = (picks[idx] ?? []).contains(letter)
                    Button {
                        Haptic.select()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            var s = picks[idx] ?? []
                            if type == "multi" { if s.contains(letter) { s.remove(letter) } else { s.insert(letter) } } else { s = [letter] }
                            picks[idx] = s
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: on ? (type == "multi" ? "checkmark.square.fill" : "largecircle.fill.circle") : (type == "multi" ? "square" : "circle"))
                                .foregroundStyle(on ? Color.brand : .secondary).font(.title3)
                            Text(plain(opt)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? Color.brand.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .glassCard(cornerRadius: 16)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Color.brand : .clear, lineWidth: 1.5))
                        .scaleEffect(on ? 1.01 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func webOnly(_ q: J) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("这道题要用画板、手写或看题图，用网页版作答", systemImage: "pencil.and.scribble").font(.subheadline).foregroundStyle(.secondary)
            Button("在网页版作答") { sheet = .web(WebSpec(path: "/quiz?ids=\(q.int("id"))", title: "作答")) }.buttonStyle(GlassButtonStyle(prominent: true))
        }
        .padding(16).glassCard(cornerRadius: 18)
    }

    @ViewBuilder private func hintArea(_ q: J) -> some View {
        let hs = hints[idx] ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(hs.enumerated()), id: \.offset) { i, h in
                Label { Text(plain(h)).font(.subheadline) } icon: { Image(systemName: "lightbulb.fill").foregroundStyle(.yellow) }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 14)
            }
            if hs.count < 3 {
                Button { Task { await hint(q) } } label: { Label(hinting ? "思考中…" : (hs.isEmpty ? "卡住了？给个提示" : "再给点提示"), systemImage: "lightbulb") }
                    .font(.footnote).disabled(hinting)
            } else {
                Button { sheet = .chat(ChatSpec(title: "问 Max", study: false, ctx: ["q": q.int("id")], prompt: "这题我还是不会，再给我讲讲思路（先别说答案）")) } label: { Label("还是不会，问 Max", systemImage: "sparkles") }.font(.footnote)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { go(-1) } label: { Image(systemName: "chevron.left").frame(width: 44) }.buttonStyle(GlassButtonStyle()).frame(width: 70).disabled(idx == 0).opacity(idx == 0 ? 0.4 : 1)
            if idx < qs.count - 1 {
                Button { go(1) } label: { Text("下一题") }.buttonStyle(GlassButtonStyle(prominent: true))
            } else {
                Button { Task { await submit() } } label: { Text("交卷（已答 \(qs.indices.filter { isNative(qs[$0]) && answered($0) }.count) 题）") }.buttonStyle(GlassButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func go(_ d: Int) {
        Haptic.tap()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { idx = min(max(0, idx + d), qs.count - 1) }
        started[idx] = started[idx] ?? Date()
    }

    // MARK: 结果
    private var resultView: some View {
        let right = results.filter { $0.int("is_correct") == 1 && $0.str("status") != "待批改" }.count
        let wait = results.filter { $0.str("status") == "待批改" }.count
        return ScrollView {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                    Circle().trim(from: 0, to: results.isEmpty ? 0 : CGFloat(right) / CGFloat(results.count))
                        .stroke(Color.brand, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: right)
                    VStack { Text("\(right) / \(results.count)").font(.system(size: 30, weight: .bold, design: .rounded)); Text(wait > 0 ? "\(wait) 题批改中" : "答对").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(width: 130, height: 130).padding(.top, 10)
                if wait > 0 && polling { ProgressView("Max 批改中…").font(.footnote) }
                ForEach(Array(results.enumerated()), id: \.offset) { _, r in ResultCard(r: r, sheet: $sheet) }
            }
            .padding(16)
        }
    }

    // MARK: 数据
    private func load() async {
        phase = .loading; error = nil
        do {
            qs = try await API.shared.list(spec.path)
            if qs.isEmpty {
                // 「练这组」在题库里没有同类题：让 Max 现场出题（临时题不进题库）→ 网页版处理
                if spec.path.contains("topic=") { phase = .empty } else { phase = .empty }
                return
            }
            idx = 0; started = [0: Date()]
            withAnimation { phase = .doing }
        } catch { self.error = error.localizedDescription; phase = .failed }
    }

    private func hint(_ q: J) async {
        hinting = true
        defer { hinting = false }
        do {
            let r = try await API.shared.obj("/api/max/hint", method: "POST", json: ["q": q.int("id"), "level": (hints[idx] ?? []).count + 1])
            hints[idx, default: []].append(r.str("text"))
            Haptic.soft()
        } catch { hints[idx, default: []].append(error.localizedDescription) }
    }

    private func submit() async {
        var items: [[String: Any]] = []
        for (i, q) in qs.enumerated() where isNative(q) && answered(i) {
            let type = q.str("type")
            let ans: Any = type == "fill" ? (texts[i] ?? "").trimmingCharacters(in: .whitespaces) : Array(picks[i] ?? []).sorted()
            items.append(["question_id": q.int("id"), "answer": ans, "time_spent_sec": Int(Date().timeIntervalSince(started[i] ?? Date()))])
        }
        guard !items.isEmpty else { error = "还没有作答的题"; Haptic.bad(); return }
        phase = .submitting
        do {
            let r = try await API.shared.obj("/api/submit", method: "POST", json: ["items": items])
            attemptIds = (r["attempt_ids"] as? [Int]) ?? []
            Haptic.ok()
            await refreshResults()
            withAnimation { phase = .result }
            NotificationCenter.default.post(name: .bankChanged, object: nil)
            await pollPending()
        } catch { self.error = error.localizedDescription; phase = .doing; Haptic.bad() }
    }

    private func refreshResults() async {
        guard !attemptIds.isEmpty else { return }
        if let l = try? await API.shared.list("/api/attempts?ids=" + attemptIds.map(String.init).joined(separator: ",")) { results = l }
    }

    private func pollPending() async {
        polling = true
        defer { polling = false }
        for _ in 0..<12 {
            guard results.contains(where: { $0.str("status") == "待批改" && ($0.str("grader") == "max" || $0.str("grader") == "maxing") }) else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await refreshResults()
        }
    }
}

struct ResultCard: View {
    let r: J
    @Binding var sheet: SheetKind?
    @State private var expl: String?

    var body: some View {
        let pending = r.str("status") == "待批改", ok = r.int("is_correct") == 1
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: pending ? "hourglass" : ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(pending ? .orange : ok ? .green : .red).font(.title3)
                Text(pending ? "批改中" : ok ? "答对了" : "答错了").font(.headline)
                Spacer()
                if !r.str("topic").isEmpty { Chip(text: r.str("topic"), tint: .secondary) }
            }
            Text(plain(r.str("stem").replacingOccurrences(of: "^[^·]*·", with: "", options: .regularExpression))).font(.subheadline).lineLimit(3)
            Text("你的答案：" + (r.str("answer_text").isEmpty ? "（空）" : plain(r.str("answer_text")))).font(.subheadline)
            if !ok && !pending { Text("正确答案：" + plain(r.strs("answer").joined(separator: " / "))).font(.subheadline.weight(.semibold)).foregroundStyle(.green) }
            if !r.str("comment").isEmpty { Text(r.str("comment")).font(.footnote).foregroundStyle(.secondary) }
            if !r.str("error_reason").isEmpty { Chip(text: "错因：" + r.str("error_reason"), tint: .red) }
            if let e = expl { Text("解析：" + plain(e)).font(.footnote) }
            HStack {
                Button("问 Max") { sheet = .chat(ChatSpec(title: "问 Max", study: false, ctx: ["explain": r.int("id")], prompt: "讲讲这道题")) }.buttonStyle(BrandButtonStyle())
                if expl == nil { Button("解析") { Task { await loadExpl() } }.buttonStyle(BrandButtonStyle()) }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private func loadExpl() async {
        if let q = try? await API.shared.obj("/api/question/\(r.int("question_id"))") { expl = q.str("explanation").isEmpty ? "这题没有解析" : q.str("explanation") }
    }
}
