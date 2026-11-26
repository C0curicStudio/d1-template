import SwiftUI
import PencilKit

/// 做题：题目从服务器数据库拉取，所有题型都在原生界面作答：选择、填空、简答 / 计算 / 解答（打字）、画板（作图 / 函数 / 电路…）、拍照作答；题库没有同类题时 Max 现场出题
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
    @State private var marked = Set<Int>()
    @State private var boards: [Int: PKDrawing] = [:]    // 画板 / 手写答案：交卷时拍成图交给老师
    @State private var scratches: [Int: PKDrawing] = [:] // 草稿纸：不交
    @State private var photos: [Int: [UIImage]] = [:]    // 拍照作答
    @State private var cover: Cover?

    enum Cover: Identifiable {
        case sketch(SketchSpec), camera(Int)
        var id: String { switch self { case .sketch(let s): return "s-\(s.id)"; case .camera(let i): return "c-\(i)" } }
    }

    enum Phase { case loading, doing, submitting, result, empty, failed, drill }

    private func isNative(_ q: J) -> Bool { ["single", "multi", "fill", "short"].contains(q.str("type")) }
    private func hasBoard(_ i: Int) -> Bool { !(boards[i]?.bounds.isEmpty ?? true) }
    private func answered(_ i: Int) -> Bool {
        !(picks[i] ?? []).isEmpty || !(texts[i] ?? "").trimmingCharacters(in: .whitespaces).isEmpty || hasBoard(i) || !(photos[i] ?? []).isEmpty
    }
    private var anyAnswer: Bool { qs.indices.contains { answered($0) } }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                switch phase {
                case .loading: ProgressView("正在从数据库取题…")
                case .drill: DrillView(topic: topicOfPath, like: nil) { sheet = .chat($0) }
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
                        if phase == .doing && anyAnswer { confirmExit = true } else { dismiss() }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .doing, qs.indices.contains(idx) {
                        let qid = qs[idx].int("id")
                        Button { Task { await toggleMark(qid) } } label: { Image(systemName: marked.contains(qid) ? "flag.fill" : "flag") }
                            .accessibilityLabel("标记这道题")
                    }
                }
            }
            .confirmationDialog("退出后这次作答不会保存", isPresented: $confirmExit, titleVisibility: .visible) { Button("退出", role: .destructive) { dismiss() } }
        }
        .interactiveDismissDisabled(phase == .doing)
        .sheet(item: $sheet) { SheetHost(kind: $0).environmentObject(router) }
        .fullScreenCover(item: $cover) { c in
            switch c {
            case .sketch(let s):
                SketchBoard(title: s.title, kind: s.kind, scratch: s.scratch, drawing: Binding(get: { (s.scratch ? scratches[s.idx] : boards[s.idx]) ?? PKDrawing() }, set: { if s.scratch { scratches[s.idx] = $0 } else { boards[s.idx] = $0 } }))
            case .camera(let i):
                ImagePicker(camera: true) { photos[i, default: []].append($0) }.ignoresSafeArea()
            }
        }
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
                    if q.has("fig"), let fig = q["fig"], !(fig is NSNull) { FigView(fig: fig) }
                    answerArea(q)
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
        } else if type == "short" {
            // 简答 / 计算 / 解答：直接写在这里，交卷后 Max 批改
            let bind = Binding(get: { texts[idx] ?? "" }, set: { texts[idx] = $0 })
            ZStack(alignment: .topLeading) {
                TextEditor(text: bind)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 200)
                    .padding(10)
                    .accessibilityIdentifier("shortAnswer")
                if (texts[idx] ?? "").isEmpty {
                    Text("写出你的解答过程和答案…").foregroundStyle(Color.mute.opacity(0.7)).padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
                }
            }
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.6))
            boardTools(q)
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

    /// 画板 / 手写 / 拍照：作图、函数、电路、光路、受力、证明的画板就是答案；其余题的「手写答案」也交给老师看图，「草稿纸」不交
    @ViewBuilder private func boardTools(_ q: J) -> some View {
        let tag = q.str("tag"), kind = BoardKind.forTag(tag), drawn = drawnTags.contains(tag)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { cover = .sketch(SketchSpec(idx: idx, title: drawn ? "画板作答" : "手写答案", kind: kind, scratch: false)) } label: { Label(drawn ? "画板作答" : "手写答案", systemImage: "pencil.tip.crop.circle").lineLimit(1) }
                    .buttonStyle(BrandButtonStyle(filled: drawn))
                if !drawn { Button { cover = .sketch(SketchSpec(idx: idx, title: "草稿纸", kind: kind, scratch: true)) } label: { Label("草稿纸", systemImage: "square.and.pencil").lineLimit(1) }.buttonStyle(BrandButtonStyle()) }
                Button { cover = .camera(idx) } label: { Label("拍照作答", systemImage: "camera").lineLimit(1) }.buttonStyle(BrandButtonStyle())
            }
            if let d = boards[idx], !d.bounds.isEmpty, let img = BoardRender.image(d, kind: kind, full: false) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 180).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) { Button { boards[idx] = nil } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Color.mute) }.padding(6) }
            }
            if let ps = photos[idx], !ps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(Array(ps.enumerated()), id: \.offset) { n, p in
                        Image(uiImage: p).resizable().scaledToFill().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) { Button { photos[idx]?.remove(at: n) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Color.mute) }.padding(3) }
                    } }
                }
            }
            Text(drawn ? "画出来的 / 拍的就是答案，交卷后由 Claude 看图批改；也可以再打字补充。" : "打字写的由 Max 批改；用了手写答案或拍照，则由 Claude 看图批改。草稿纸不会交。").font(.caption).foregroundStyle(Color.mute)
        }
    }

    private func webOnly(_ q: J) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("这道题要作图或看题图，用网页版作答", systemImage: "pencil.and.scribble").font(.subheadline).foregroundStyle(.secondary)
            Button("在网页版作答") { sheet = .web(WebSpec(path: "/quiz?ids=\(q.int("id"))", title: "作答")) }.buttonStyle(GlassButtonStyle(prominent: true))
        }
        .padding(16).glassCard(cornerRadius: 18)
    }

    @ViewBuilder private func hintArea(_ q: J) -> some View {
        let hs = hints[idx] ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(hs.enumerated()), id: \.offset) { i, h in
                Label { Text(plain(h)).font(.subheadline) } icon: { Image(systemName: "lightbulb.fill").foregroundStyle(Color.brand) }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 14)
            }
            if hs.count < 3 {
                Button { Task { await hint(q) } } label: { Label(hinting ? "思考中…" : (hs.isEmpty ? "卡住了？给个提示" : "再给点提示"), systemImage: "lightbulb") }
                    .buttonStyle(BrandButtonStyle()).disabled(hinting)
            } else {
                Button { sheet = .chat(ChatSpec(title: "问 Max", study: false, ctx: ["q": q.int("id")], prompt: "这题我还是不会，再给我讲讲思路（先别说答案）")) } label: { Label("还是不会，问 Max", systemImage: "sparkles") }.buttonStyle(BrandButtonStyle())
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
                // 「练这组」在题库里没有同类题：让 Max 现场出题（临时题不进题库）
                phase = topicOfPath.isEmpty ? .empty : .drill
                return
            }
            idx = 0; started = [0: Date()]
            withAnimation { phase = .doing }
        } catch { self.error = error.localizedDescription; phase = .failed }
    }

    /// 标记：交卷后进「标记的题」，可以让 Max / Claude 解析
    private func toggleMark(_ id: Int) async {
        let on = !marked.contains(id)
        if on { marked.insert(id) } else { marked.remove(id) }
        Haptic.select()
        _ = try? await API.shared.any("/api/mark", method: "POST", json: ["question_id": id, "on": on])
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
        guard anyAnswer else { error = "还没有作答的题"; Haptic.bad(); return }
        phase = .submitting
        do {
            var items: [[String: Any]] = []
            for (i, q) in qs.enumerated() where isNative(q) && answered(i) {
                let type = q.str("type"), tag = q.str("tag")
                let ans: Any = (type == "fill" || type == "short") ? (texts[i] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : Array(picks[i] ?? []).sorted()
                var keys: [String] = []
                // 拍照作答：直接传
                for p in photos[i] ?? [] {
                    if let d = ImageUtil.jpeg(p, maxSide: 1280) { keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", images: [d]).str("key")) }
                }
                // 画板 / 手写答案：整张图自己看（view），裁出来的小图交给 Claude（board）
                var hand = false
                if let d = boards[i], !d.bounds.isEmpty {
                    let kind = BoardKind.forTag(tag)
                    hand = true
                    if let full = BoardRender.image(d, kind: kind, full: true), let fd = ImageUtil.jpeg(full, maxSide: 1280, maxBytes: 900_000) {
                        keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", fields: ["kind": "view"], images: [fd]).str("key"))
                    }
                    if let small = BoardRender.image(d, kind: kind, full: false), let sd = ImageUtil.jpeg(small, maxSide: 1024, maxBytes: 600_000) {
                        keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", fields: ["kind": "board"], images: [sd]).str("key"))
                    }
                }
                var it: [String: Any] = ["question_id": q.int("id"), "answer": ans, "photo_keys": keys, "time_spent_sec": Int(Date().timeIntervalSince(started[i] ?? Date()))]
                if hand { it["hand"] = true; it["work"] = "[手写答案] 见附图" }
                items.append(it)
            }
            let r = try await API.shared.obj("/api/submit", method: "POST", json: ["items": items])
            attemptIds = (r["attempt_ids"] as? [Int]) ?? []
            Haptic.ok()
            await refreshResults()
            withAnimation { phase = .result }
            NotificationCenter.default.post(name: .bankChanged, object: nil)
            await pollPending()
        } catch { self.error = error.localizedDescription; phase = .doing; Haptic.bad() }
    }

    private var topicOfPath: String { URLComponents(string: spec.path)?.queryItems?.first { $0.name == "topic" }?.value ?? "" }

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
                    .foregroundStyle(pending ? Color.mute : ok ? Color.ink : Color.brand).font(.title3)
                Text(pending ? (r.str("grader").isEmpty ? "等 Claude 批改" : "Max 批改中") : ok ? "答对了" : "答错了").font(.headline)
                Spacer()
                if !r.str("topic").isEmpty { Chip(text: r.str("topic"), tint: .secondary) }
            }
            Text(plain(r.str("stem").replacingOccurrences(of: "^[^·]*·", with: "", options: .regularExpression))).font(.subheadline).lineLimit(3)
            Text("你的答案：" + (r.str("answer_text").isEmpty ? "（空）" : plain(r.str("answer_text")))).font(.subheadline)
            if !ok && !pending { Text("正确答案：" + plain(r.strs("answer").joined(separator: " / "))).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink) }
            if !r.str("comment").isEmpty { Text(r.str("comment")).font(.footnote).foregroundStyle(.secondary) }
            if !r.str("error_reason").isEmpty { Chip(text: "错因：" + r.str("error_reason"), tint: Color.brand) }
            if let e = expl { Text("解析：" + plain(e)).font(.footnote) }
            HStack {
                Button("问 Max") { sheet = .chat(ChatSpec(title: "问 Max", study: false, ctx: ["explain": r.int("id")], prompt: "讲讲这道题")) }.buttonStyle(BrandButtonStyle())
                if expl == nil { Button("解析") { Task { await loadExpl() } }.buttonStyle(BrandButtonStyle()) }
                if r.int("prev") != 0 { Button("和上次比") { sheet = .chat(ChatSpec(title: "问 Max", study: false, ctx: ["explain": r.int("id"), "cmp": true], prompt: "这次和上次比怎么样？")) }.buttonStyle(BrandButtonStyle()) }
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
