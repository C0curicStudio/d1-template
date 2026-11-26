import SwiftUI

struct RootView: View {
    @StateObject private var api = API.shared
    @StateObject private var router = Router()
    @StateObject private var sync = LibrarySync.shared
    @Environment(\.scenePhase) private var phase
    @State private var booted = false

    var body: some View {
        Group {
            if !booted {
                ZStack { WarmBackground(); ProgressView() }
            } else if api.authed == false {
                LoginView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .environmentObject(router)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: api.authed)
        .task {
            await api.bootstrap()
            booted = true
            if api.authed == true { sync.refresh(force: true) }
        }
        .onChange(of: phase) { p in
            if p == .active, api.authed == true { sync.refresh() }
        }
        .onChange(of: api.authed) { a in
            if a == true { sync.refresh(force: true) }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        tabs
            .tint(Color.brand)
            .overlay { MaxBall() }
            .fullScreenCover(item: $router.quiz) { QuizView(spec: $0).environmentObject(router) }
            .sheet(item: $router.sheet) { SheetHost(kind: $0).environmentObject(router) }
    }

    @ViewBuilder
    private var tabs: some View {
        let base = TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)
            BankView(mode: .bank)
                .tabItem { Label("题库", systemImage: "books.vertical.fill") }
                .tag(1)
            BankView(mode: .wrong)
                .tabItem { Label("错题本", systemImage: "xmark.square.fill") }
                .tag(2)
            StudyView()
                .tabItem { Label("学习台", systemImage: "sparkles") }
                .tag(3)
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            base.tabBarMinimizeBehavior(.onScrollDown) // iOS 26：往下滑，玻璃标签栏自动收起
        } else {
            base
        }
        #else
        base
        #endif
    }
}

struct LoginView: View {
    @StateObject private var api = API.shared
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showSite = false
    @FocusState private var focus: Bool

    var body: some View {
        ZStack {
            WarmBackground()
            VStack(spacing: 22) {
                Spacer()
                Image("LoginMark")
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                Text("MAX NOTE").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("不积跬步，无以至千里").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    SecureField("口令", text: $code)
                        .textContentType(.password)
                        .focused($focus)
                        .submitLabel(.go)
                        .onSubmit(go)
                        .padding(14)
                        .glassCard(cornerRadius: 16)
                    if let e = error {
                        Text(e).font(.footnote).foregroundStyle(.red).transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Button(action: go) {
                        Text(busy ? "登录中…" : "进入")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(code.isEmpty || busy)
                    .opacity(code.isEmpty ? 0.6 : 1)
                }
                .frame(maxWidth: 340)
                Spacer()
                Button("服务器地址") { showSite = true }
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: error)
        .sheet(isPresented: $showSite) { SiteSheet() }
        .onAppear { focus = true }
    }

    private func go() {
        guard !code.isEmpty, !busy else { return }
        busy = true; error = nil
        Task {
            do { try await api.login(code); Haptic.ok() }
            catch { self.error = error.localizedDescription; Haptic.bad() }
            busy = false
        }
    }
}

struct SiteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = Site.text
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                } header: { Text("服务器地址") } footer: { Text("填你部署的 Workers 地址，留空恢复默认。") }
            }
            .navigationTitle("服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if Site.save(text) { dismiss() } } }
            }
        }
        .presentationDetents([.medium])
    }
}
