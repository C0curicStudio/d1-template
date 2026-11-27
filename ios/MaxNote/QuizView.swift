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
    @State private var photos: [Int: [UIImage]] = [:]    // 拍照作答
    @State private var cover: Cover?
    @State private var smart: [Int: SmartBoard] = [:]      // 画板作答（作图 / 函数 / 电路 / 光路 / 受力 / 证明）：交卷
    @State private var calcScratch: [Int: CalcBoard] = [:] // 计算草稿板：不交
    @State private var fromCache = false
    @State private var queued = false
    @State private var pads: [Int: Pad] = [:]            // 每题当前显示的是 手写 / 草稿 / 拍照
    @State private var handSize: [Int: CGSize] = [:]     // 手写纸的实际大小：导出图用
    @State private var touching = false                  // 正在纸上画：页面先别滚动

    enum Pad: String, CaseIterable { case hand = "手写", calc = "草稿", photo = "拍照" }

    enum Cover: Identifiable {
        case camera(Int)
        var id: String { switch self { case .camera(let i): return "c-\(i)" } }
    }

    enum Phase { case loading, doing, submitting, result, empty, failed, drill }

    private func isNative(_ q: J) -> Bool { ["single", "multi", "fill", "short"].contains(q.str("type")) }
    private func hasBoard(_ i: Int) -> Bool { !(boards[i]?.bounds.isEmpty ?? true) }
    private func hasSmart(_ i: Int) -> Bool { !(smart[i]?.answer.isEmpty ?? true) }
    private func answered(_ i: Int) -> Bool {
        !(picks[i] ?? []).isEmpty || !(texts[i] ?? "").trimmingCharacters(in: .whitespaces).isEmpty || hasBoard(i) || hasSmart(i) || !(photos[i] ?? []).isEmpty
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
                case .doing: doing.overlay(alignment: .top) { if fromCache { Label("离线：使用本机缓存的题", systemImage: "wifi.slash").font(.caption).foregroundStyle(Color.mute).padding(.top, 2) } }
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
            .scrollDisabled(touching)
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
            shortArea(q)
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

    // MARK: 简答 / 计算 / 作图：答题区直接铺开，不再点按钮跳页面
    /// 作图 / 函数 / 电路 / 光路 / 受力 / 证明：画板直接在题下面，画的就是答案；其余题：打字框 + 下面的 手写 / 草稿 / 拍照 切换
    @ViewBuilder private func shortArea(_ q: J) -> some View {
        let tag = q.str("tag"), drawn = drawnTags.contains(tag), i = idx
        if drawn, let b = smart[i] {
            paperCard { smartPanel(b) }
            if !b.answer.isEmpty { Text(b.answer.describe()).font(.footnote).foregroundStyle(Color.mute).lineLimit(3) }
            typedBox(minHeight: 80, prompt: "补充说明（可不写）")
            photoRow(i, title: "拍照补充")
            note("画板里画的会随答案交卷：文字描述 + 图，Max / Claude 批改。")
        } else {
            typedBox(minHeight: 120, prompt: "写出你的解答过程和答案…")
            Picker("", selection: Binding(get: { pads[i] ?? .hand }, set: { v in Haptic.select(); withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pads[i] = v } })) {
                ForEach(Pad.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch pads[i] ?? .hand {
            case .hand:
                handPad(q, i)
                note("写在纸上的会交给 Claude 看图批改；打字的由 Max 批改。")
            case .calc:
                if let c = calcScratch[i] { paperCard { CalcBoardPanel(calc: c, onTouch: { touching = $0 }) } }
                note("草稿纸：随便算，不会交。")
            case .photo:
                photoRow(i, title: "拍照作答")
                note("拍下写好的解答，交给 Claude 批改。")
            }
        }
    }

    private func typedBox(minHeight: CGFloat, prompt: String) -> some View {
        let i = idx
        let bind = Binding(get: { texts[i] ?? "" }, set: { texts[i] = $0 })
        return ZStack(alignment: .topLeading) {
            TextEditor(text: bind)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(10)
                .accessibilityIdentifier("shortAnswer")
            if (texts[i] ?? "").isEmpty {
                Text(prompt).foregroundStyle(Color.mute.opacity(0.7)).padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
            }
        }
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.6))
    }

    private func handPad(_ q: J, _ i: Int) -> some View {
        let kind = BoardKind.forTag(q.str("tag"))
        return SketchCanvas(drawing: Binding(get: { boards[i] ?? PKDrawing() }, set: { boards[i] = $0 }), kind: kind,
                            onSize: { handSize[i] = $0 }, onTouch: { touching = $0 })
            .frame(height: 300)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.6))
            .overlay(alignment: .topTrailing) {
                if hasBoard(i) {
                    Button { boards[i] = nil; Haptic.soft() } label: { Image(systemName: "trash.circle.fill").font(.title2).foregroundStyle(Color.mute, Color.white) }
                        .padding(8).transition(.opacity)
                }
            }
    }

    @ViewBuilder private func smartPanel(_ b: SmartBoard) -> some View {
        switch b {
        case .geo(let g): GeoBoardPanel(board: g, canvasHeight: 360, onTouch: { touching = $0 })
        case .circuit(let c): CircuitBoardPanel(board: c, canvasHeight: 360, onTouch: { touching = $0 })
        case .calc(let c): CalcBoardPanel(calc: c, onTouch: { touching = $0 })
        }
    }

    private func paperCard<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding(8).background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.6))
    }

    private func note(_ t: String) -> some View { Text(t).font(.caption).foregroundStyle(Color.mute) }

    private func photoRow(_ i: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { cover = .camera(i) } label: { Label(title, systemImage: "camera").lineLimit(1) }.buttonStyle(BrandButtonStyle())
            if let ps = photos[i], !ps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(Array(ps.enumerated()), id: \.offset) { n, p in
                        Image(uiImage: p).resizable().scaledToFill().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) { Button { photos[i]?.remove(at: n) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Color.mute) }.padding(3) }
                    } }
                }
            }
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
                if queued { Label("没有网络：答案已存在本机，联网后会自动交卷并批改", systemImage: "icloud.and.arrow.up").font(.subheadline).foregroundStyle(Color.mute).card() }
                if wait > 0 && polling { ProgressView("Max 批改中…").font(.footnote) }
                claudeCard
                ForEach(Array(results.enumerated()), id: \.offset) { _, r in ResultCard(r: r, sheet: $sheet) }
            }
            .padding(16)
        }
    }

    /// 做完后直达 Claude：Claude 通过「练习本」连接器自己取作答、批改、讲解
    @ViewBuilder private var claudeCard: some View {
        let toGrade = results.contains { $0.str("status") == "待批改" && $0.str("grader").isEmpty }
        let wrong = results.contains { $0.int("is_correct") == 0 && $0.str("status") != "待批改" }
        if toGrade || wrong || !marked.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("交给 Claude", systemImage: "arrow.up.forward.app").font(.subheadline.weight(.semibold))
                if toGrade { Button { openClaude("用练习本：批改我刚交的待批改作答（手写 / 拍照 / 作图），写评语") } label: { Label("批改手写 / 拍照的题", systemImage: "checkmark.seal").frame(maxWidth: .infinity) }.buttonStyle(BrandButtonStyle(filled: true)) }
                if wrong { Button { openClaude("用练习本：讲讲我这次做错的题，指出错因并给同类练习") } label: { Label("讲解做错的题", systemImage: "text.book.closed").frame(maxWidth: .infinity) }.buttonStyle(BrandButtonStyle()) }
                if !marked.isEmpty { Button { openClaude("用练习本：解析我标记的题") } label: { Label("解析标记的题（\(marked.count)）", systemImage: "flag").frame(maxWidth: .infinity) }.buttonStyle(BrandButtonStyle()) }
                Text("点一下会打开 Claude 并带好指令（已复制，没带出来就粘贴）。").font(.caption).foregroundStyle(Color.mute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: 数据
    private func load() async {
        phase = .loading; error = nil
        do {
            do { qs = (try await API.shared.fresh(spec.path)) as? [J] ?? [] }
            catch NetError.offline {
                // 没网：用本机缓存的题（后台自动缓存过的今日题 / 各科题 / 指定题）
                guard let c = API.shared.cached(spec.path) as? [J], !c.isEmpty else { throw NetError.offline }
                qs = c; fromCache = true
            }
            if qs.isEmpty {
                // 「练这组」在题库里没有同类题：让 Max 现场出题（临时题不进题库）
                phase = topicOfPath.isEmpty ? .empty : .drill
                return
            }
            idx = 0; started = [0: Date()]
            prepareBoards()
            withAnimation { phase = .doing }
        } catch { self.error = error.localizedDescription; phase = .failed }
    }

    /// 每道简答题先备好画板：作图类是答案画板，其余是计算草稿板
    @MainActor private func prepareBoards() {
        smart = [:]; calcScratch = [:]
        for (i, q) in qs.enumerated() where q.str("type") == "short" {
            let tag = q.str("tag")
            if drawnTags.contains(tag) { smart[i] = SmartBoard.make(tag: tag, subject: q.str("subject")) }
            else { calcScratch[i] = CalcBoard(subject: q.str("subject")) }
        }
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
        var items: [[String: Any]] = []
        var needsPhotos = false
        do {
            for (i, q) in qs.enumerated() where isNative(q) && answered(i) {
                let type = q.str("type"), tag = q.str("tag")
                let ans: Any = (type == "fill" || type == "short") ? (texts[i] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : Array(picks[i] ?? []).sorted()
                var keys: [String] = []
                if !(photos[i] ?? []).isEmpty || hasBoard(i) { needsPhotos = true }
                // 拍照作答：直接传
                for p in photos[i] ?? [] {
                    if let d = ImageUtil.jpeg(p, maxSide: 1280) { keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", images: [d]).str("key")) }
                }
                // 画板 / 手写答案：整张图自己看（view），裁出来的小图交给 Claude（board）
                var hand = false
                if let d = boards[i], !d.bounds.isEmpty {
                    let kind = BoardKind.forTag(tag)
                    hand = true
                    if let full = BoardRender.image(d, kind: kind, full: true, size: handSize[i] ?? boardSize), let fd = ImageUtil.jpeg(full, maxSide: 1280, maxBytes: 900_000) {
                        keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", fields: ["kind": "view"], images: [fd]).str("key"))
                    }
                    if let small = BoardRender.image(d, kind: kind, full: false, size: handSize[i] ?? boardSize), let sd = ImageUtil.jpeg(small, maxSide: 1024, maxBytes: 600_000) {
                        keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", fields: ["kind": "board"], images: [sd]).str("key"))
                    }
                }
                // 智能画板：文字描述 + 整图（自己看）+ 画了笔迹时再附一张裁剪小图（给 Claude）
                var work = ""
                if let sb = smart[i], !sb.answer.isEmpty {
                    needsPhotos = true
                    let a = sb.answer
                    work = a.tag + " " + a.describe()
                    if let full = a.image(full: true), let fd = ImageUtil.jpeg(full, maxSide: 1280, maxBytes: 900_000) {
                        keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", fields: ["kind": "view"], images: [fd]).str("key"))
                    }
                    if a.hasPen, let small = a.image(full: false), let sd = ImageUtil.jpeg(small, maxSide: 1024, maxBytes: 600_000) {
                        keys.append(try await API.shared.upload("/api/attempt-photo", field: "file", fields: ["kind": "board"], images: [sd]).str("key"))
                    }
                }
                var it: [String: Any] = ["question_id": q.int("id"), "answer": ans, "photo_keys": keys, "time_spent_sec": Int(Date().timeIntervalSince(started[i] ?? Date()))]
                if hand { it["hand"] = true; work = (work.isEmpty ? "" : work + "\n") + "[手写答案] 见附图" }
                if !work.isEmpty { it["work"] = work }
                items.append(it)
            }
            let r = try await API.shared.obj("/api/submit", method: "POST", json: ["items": items])
            attemptIds = (r["attempt_ids"] as? [Int]) ?? []
            Haptic.ok()
            await refreshResults()
            withAnimation { phase = .result }
            NotificationCenter.default.post(name: .bankChanged, object: nil)
            await pollPending()
        } catch NetError.offline where !needsPhotos && !items.isEmpty {
            // 没网：答案先存在本机，联网后自动补交（带图的答案要联网才能交）
            if let d = try? JSONSerialization.data(withJSONObject: ["items": items]), let s = String(data: d, encoding: .utf8) { LocalStore.shared.outboxAdd(s) }
            Prefetcher.shared.refreshPending()
            queued = true; Haptic.ok()
            withAnimation { phase = .result }
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
