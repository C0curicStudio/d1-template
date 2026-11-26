import SwiftUI
import UIKit

struct ChatMsg: Identifiable { let id = UUID(); let role: String; var text: String }
struct PendingAlert: Identifiable { let id = UUID(); let action: MaxAction; let message: String }

/// 和 Max 对话的逻辑（悬浮面板和做题页里的面板共用）：流式回复、带学习数据 / 题目上下文
@MainActor
final class ChatModel: ObservableObject {
    @Published var msgs: [ChatMsg] = []
    @Published var input = ""
    @Published var busy = false
    @Published var deep = false
    @Published var web = false
    @Published var pending: PendingAlert?
    @Published var attaching = false
    var spec = ChatSpec()
    private var task: Task<Void, Never>?

    func send(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if busy { task?.cancel(); busy = false; return }
        guard !t.isEmpty else { return }
        Haptic.tap(); input = ""
        msgs.append(ChatMsg(role: "user", text: t))
        let history = msgs.suffix(6).map { ["role": $0.role, "content": String($0.text.prefix(800))] }
        msgs.append(ChatMsg(role: "assistant", text: ""))
        let idx = msgs.count - 1
        var ctx = spec.ctx
        ctx["study"] = spec.study; ctx["topic"] = spec.topic; ctx["deep"] = deep; ctx["web"] = web
        let ud = UserDefaults.standard
        ctx["len"] = ud.string(forKey: "maxLen") ?? (spec.study ? "l" : "m"); ctx["pref"] = ud.string(forKey: "maxPref") ?? "auto"
        busy = true
        task = Task {
            do { try await API.shared.stream("/api/max/chat", json: ["messages": history, "ctx": ctx]) { text in if idx < self.msgs.count { self.msgs[idx].text = text } } }
            catch is CancellationError {}
            catch { if idx < msgs.count { msgs[idx].text = error.localizedDescription } }
            busy = false
            Haptic.soft()
        }
    }

    func clear() { task?.cancel(); busy = false; msgs.removeAll() }

    /// 发图：先让看图模型把图转写成文字，再连同问题一起问 Max
    func attach(_ img: UIImage) {
        guard let d = ImageUtil.jpeg(img, maxSide: 1280, maxBytes: 1_800_000) else { return }
        attaching = true
        let q = input
        Task {
            do {
                let r = try await API.shared.obj("/api/max/see", method: "POST", json: ["image": ImageUtil.dataURL(d), "q": String(q.prefix(200))])
                send("【我发了一张图，内容转写如下】\n" + r.str("text") + "\n\n" + (q.isEmpty ? "帮我看看这张图，讲讲怎么做。" : q))
            } catch { msgs.append(ChatMsg(role: "assistant", text: error.localizedDescription)) }
            attaching = false
        }
    }

    /// Max 给的网站动作：先数一数、确认才做
    func run(_ a: MaxAction, dry: Bool) async {
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

/// 消息列表（含「可以问我」）
struct ChatBody: View {
    @ObservedObject var model: ChatModel
    let onAction: (MaxAction) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.msgs.isEmpty { suggestions }
                    ForEach(model.msgs) { m in bubble(m).id(m.id).transition(.move(edge: .bottom).combined(with: .opacity)) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.msgs.last?.text) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.msgs.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .alert(item: $model.pending) { p in
            Alert(title: Text(p.action.arg), message: Text(p.message), primaryButton: .default(Text("确定")) { Task { await model.run(p.action, dry: false) } }, secondaryButton: .cancel())
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可以问我").font(.footnote).foregroundStyle(Color.mute)
            ForEach(model.spec.study ? ["我现在最该先补哪块？", "用一个例子讲讲我最薄弱的考点", "我总是犯哪类错？怎么改？"] : ["这题考什么知识点？", "我错在哪一步？", "给我一道类似的题"], id: \.self) { s in
                Button { model.send(s) } label: { Text(s).font(.subheadline).foregroundStyle(Color.ink).padding(.horizontal, 14).padding(.vertical, 9).background(Color.card, in: Capsule()).overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.6)) }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatMsg) -> some View {
        if m.role == "user" {
            Text(m.text).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 44)
        } else {
            let (body, acts) = splitActions(m.text)
            let last = m.id == model.msgs.last?.id
            VStack(alignment: .leading, spacing: 8) {
                if m.text.isEmpty { HStack(spacing: 8) { MaxLogo(size: 22, active: true, busy: true); Text("思考中…").foregroundStyle(Color.mute) } }
                else { Text(md(body)).foregroundStyle(Color.ink).lineSpacing(4).textSelection(.enabled) }
                if !(model.busy && last) {
                    ForEach(acts) { a in
                        Button { onAction(a) } label: { Label(a.title, systemImage: a.kind == .practice ? "play.fill" : a.kind == .doit ? "checkmark.circle" : "arrow.right") }
                            .buttonStyle(BrandButtonStyle())
                    }
                }
            }
            .padding(14).card(0)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 20)
        }
    }
}

enum PickSource: String, Identifiable { case camera, library; var id: String { rawValue } }

struct ChatInputBar: View {
    @ObservedObject var model: ChatModel
    var focus: FocusState<Bool>.Binding
    @State private var source: PickSource?

    private func tag(_ title: String, _ icon: String, _ on: Binding<Bool>) -> some View {
        Button { Haptic.select(); withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { on.wrappedValue.toggle() } } label: {
            Label(title, systemImage: icon).font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on.wrappedValue ? Color.white : Color.mute)
                .background(on.wrappedValue ? Color.brand : Color.card, in: Capsule())
                .overlay(Capsule().strokeBorder(on.wrappedValue ? Color.clear : Color.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tag("深度思考", "brain", $model.deep)
                tag("联网搜索", "globe", $model.web)
                Spacer()
            }
            .padding(.leading, 4)
            field
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Menu {
                Button { source = .camera } label: { Label("拍照", systemImage: "camera") }
                Button { source = .library } label: { Label("从相册选", systemImage: "photo") }
            } label: {
                Group { if model.attaching { ProgressView() } else { Image(systemName: "photo.badge.plus").font(.system(size: 20)).foregroundStyle(Color.mute) } }
                    .frame(width: 40, height: 40)
            }
            .padding(.leading, 4).padding(.bottom, 1)
            .accessibilityLabel("发图片")
            TextField(model.deep && model.web ? "深度思考 + 联网搜索…" : model.deep ? "深度思考…" : model.web ? "联网搜索…" : "问 Max…", text: $model.input, axis: .vertical)
                .lineLimit(1...5)
                .focused(focus)
                .accessibilityIdentifier("chatInput")
                .padding(.horizontal, 14).padding(.vertical, 10)
            Button { model.send(model.input) } label: {
                Image(systemName: model.busy ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 32))
                    .foregroundStyle(model.input.trimmingCharacters(in: .whitespaces).isEmpty && !model.busy ? Color.mute.opacity(0.6) : Color.brand)
            }
            .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty && !model.busy)
            .accessibilityIdentifier("chatSend")
            .padding(.trailing, 6).padding(.bottom, 4)
        }
        .background(Color.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.6))
        .fullScreenCover(item: $source) { s in ImagePicker(camera: s == .camera) { model.attach($0) }.ignoresSafeArea() }
    }
}

/// 整页对话（做题页里用的面板）
struct ChatView: View {
    let spec: ChatSpec
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ChatModel()
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            ChatBody(model: model) { a in
                switch a.kind {
                case .practice, .go: dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.open(a) }
                case .doit: Task { await model.run(a, dry: true) }
                case .note: break
                }
            }
            .background(WarmBackground())
            .navigationTitle(spec.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { model.clear() } label: { Image(systemName: "trash") }
                }
            }
            .safeAreaInset(edge: .bottom) { ChatInputBar(model: model, focus: $focus).padding(.horizontal, 12).padding(.bottom, 6) }
            .task {
                model.spec = spec
                if let p = spec.prompt, model.msgs.isEmpty { model.send(p) } else { try? await Task.sleep(nanoseconds: 450_000_000); focus = true }
            }
        }
        .presentationDetents([.large])
    }
}

/// 悬浮的 Max：平时是一个会呼吸的小球（可拖动、松手贴边、闲置变淡）；点一下，从球的位置展开成对话面板，
/// iOS 26 上用系统液态玻璃做「球 ⇄ 面板」的形变，更早的系统用缩放 + 淡入
struct MaxIsland: View {
    @EnvironmentObject private var router: Router
    @StateObject private var model = ChatModel()
    @AppStorage("ballRight") private var right = true
    @AppStorage("ballY2") private var yFrac = 0.74
    @State private var drag: CGPoint?
    @State private var pressed = false
    @State private var idle = false
    @State private var kb: CGFloat = 0
    @State private var wake = 0
    @State private var showSettings = false
    @FocusState private var focus: Bool
    @Namespace private var ns

    private let d: CGFloat = 54

    private var open: Bool { router.island != nil }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, top = geo.safeAreaInsets.top
            let lo = top + d, hi = h - 120
            let rest = CGPoint(x: right ? w - d / 2 - 10 : d / 2 + 10, y: min(max(yFrac * h, lo), hi))
            let pw = min(w - 24, 420)
            // 面板贴着底部（标签栏上方；键盘弹出时贴着键盘上沿），不再悬在屏幕上半截
            let bottom = kb > 0 ? h - kb - 8 : h - 96
            let ph = min(max(260, bottom - top - 14), min(h * 0.68, 600))
            let px = right ? w - 12 - pw / 2 : 12 + pw / 2
            let py = bottom - ph / 2
            let anchor = UnitPoint(x: (rest.x - (px - pw / 2)) / pw, y: (rest.y - (py - ph / 2)) / ph)

            ZStack {
                if open {
                    Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { close() }.transition(.opacity)
                }
                morph {
                    if open {
                        panel(width: pw, height: ph)
                            .glassMorph("max", ns, radius: 30, interactive: false)
                            .position(x: px, y: py)
                            .transition(.scale(scale: 0.12, anchor: anchor).combined(with: .opacity))
                    } else {
                        ball
                            .glassMorph("max", ns, radius: nil, interactive: true)
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                            .scaleEffect(pressed ? 1.14 : 1)
                            .opacity(drag == nil && !pressed && idle ? 0.4 : 1)
                            .position(drag ?? rest)
                            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: drag == nil)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
                            .animation(.easeInOut(duration: 0.5), value: idle)
                            .gesture(
                                DragGesture(minimumDistance: 6)
                                    .onChanged { v in
                                        if drag == nil { Haptic.soft() }
                                        pressed = true; idle = false; drag = v.location
                                    }
                                    .onEnded { v in
                                        right = v.location.x > w / 2
                                        yFrac = Double(min(max(v.location.y, lo), hi) / h)
                                        pressed = false; drag = nil; Haptic.tap(); wake += 1
                                    }
                            )
                            .onTapGesture { Haptic.tap(); idle = false; wake += 1; router.ask(study: true) }
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: open)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: wake) { try? await Task.sleep(nanoseconds: 3_000_000_000); if !pressed { idle = true } }
        .onChange(of: router.island?.id) { _ in
            guard let spec = router.island else { return }
            model.spec = spec
            if let p = spec.prompt { model.send(p) } else { Task { try? await Task.sleep(nanoseconds: 500_000_000); focus = true } }
        }
        .onChange(of: router.tab) { _ in idle = false; wake += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let v = max(0, UIScreen.main.bounds.height - f.minY)
            withAnimation(.easeOut(duration: 0.25)) { kb = v }
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(router).tint(Color.brand) }
    }

    private func close() {
        focus = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { router.island = nil }
        wake += 1
    }

    /// iOS 26：把球和面板放进同一个玻璃容器，它们之间会像液体一样形变
    @ViewBuilder private func morph<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 30) { content() } } else { content() }
        #else
        content()
        #endif
    }

    private var ball: some View {
        MaxLogo(size: 34, active: true, busy: model.busy)
            .frame(width: d, height: d)
            .contentShape(Circle())
            .accessibilityLabel("问 Max")
            .accessibilityAddTraits(.isButton)
    }

    private func panel(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MaxLogo(size: 26, active: true, busy: model.busy)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Max").font(.headline).foregroundStyle(Color.ink)
                    Text(router.island?.study == true ? "能看到你的掌握度和错因" : "只给提示，不直接说答案").font(.caption2).foregroundStyle(Color.mute)
                }
                Spacer()
                Menu {
                    Button { showSettings = true } label: { Label("模型与设置", systemImage: "gearshape") }
                    Button(role: .destructive) { model.clear() } label: { Label("清空对话", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").font(.body.weight(.bold)).foregroundStyle(Color.mute).frame(width: 34, height: 34) }
                Button { close() } label: { Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(Color.mute).frame(width: 34, height: 34) }
                    .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ChatBody(model: model) { a in
                switch a.kind {
                case .practice, .go: close(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.open(a) }
                case .doit: Task { await model.run(a, dry: true) }
                case .note: break
                }
            }
            ChatInputBar(model: model, focus: $focus).padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 4)
        }
        .frame(width: width, height: height)
        .background { RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.cream.opacity(0.55)) }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
    }
}

extension View {
    /// 球 / 面板用的玻璃：iOS 26 系统液态玻璃（带形变 id），旧系统用超薄材质
    @ViewBuilder
    func glassMorph(_ id: String, _ ns: Namespace.ID, radius: CGFloat?, interactive: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let r = radius {
                self.glassEffect(.regular, in: .rect(cornerRadius: r)).glassEffectID(id, in: ns)
            } else {
                self.glassEffect(interactive ? .regular.interactive() : .regular, in: .circle).glassEffectID(id, in: ns)
            }
        } else {
            self.legacyGlass(radius)
        }
        #else
        self.legacyGlass(radius)
        #endif
    }

    @ViewBuilder fileprivate func legacyGlass(_ radius: CGFloat?) -> some View {
        if let r = radius { self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: r, style: .continuous)) }
        else { self.background(.ultraThinMaterial, in: Circle()) }
    }
}
