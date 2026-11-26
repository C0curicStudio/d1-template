import SwiftUI

struct RootView: View {
    @StateObject private var web = Web()
    @StateObject private var bt = BTPrinter()
    @StateObject private var sync = LibrarySync.shared
    @State private var showOffline = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            // 底色和网站一致（暖米色 / 深色），下拉回弹和加载时不露白
            (scheme == .dark ? Color(red: 0.122, green: 0.114, blue: 0.102) : Color(red: 0.957, green: 0.937, blue: 0.902))
                .ignoresSafeArea()
            WebViewHost(web: web)
                .ignoresSafeArea()

            if web.progress < 1 && web.failed == nil {
                ProgressView(value: web.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .transition(.opacity)
            }

            if let msg = web.failed {
                ErrorCard(message: msg, offlineCount: sync.count, retry: { web.load() }, settings: { web.showSettings = true }, offline: { showOffline = true })
                    .padding(24)
                    .frame(maxHeight: .infinity)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: web.failed)
        .animation(.easeOut(duration: 0.2), value: web.progress < 1)
        .sheet(isPresented: $web.showPrinter) {
            PrinterSheet(web: web, bt: bt)
        }
        .sheet(isPresented: $web.showSettings) {
            SettingsSheet(web: web)
        }
        .sheet(isPresented: $showOffline) {
            OfflineLibraryView()
        }
        .onChange(of: phase) { p in
            if p == .active { sync.refresh() } // 回到前台：看看题库有没有更新（没变化只回 304）
        }
    }
}

struct ErrorCard: View {
    let message: String
    let offlineCount: Int
    let retry: () -> Void
    let settings: () -> Void
    let offline: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text("无法连接 MAX NOTE")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button("重试", action: retry).buttonStyle(GlassButtonStyle(prominent: true))
                if offlineCount > 0 {
                    Button("离线题库（\(offlineCount) 题）", action: offline).buttonStyle(GlassButtonStyle())
                }
                Button("修改网址", action: settings).buttonStyle(GlassButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .glassCard(cornerRadius: 28)
    }
}

struct SettingsSheet: View {
    @ObservedObject var web: Web
    @Environment(\.dismiss) private var dismiss
    @State private var text = Site.text

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("网站地址")
                } footer: {
                    Text("填你部署的 Workers 地址。留空恢复默认。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if Site.save(text) { web.load(); dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
