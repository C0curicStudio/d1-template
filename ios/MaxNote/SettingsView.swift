import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: Router
    @StateObject private var sync = LibrarySync.shared
    @State private var site = Site.text
    @State private var cfg: J = [:]
    @State private var provider = "DeepSeek"
    @State private var key = ""
    @State private var base = "https://api.deepseek.com"
    @State private var model = "deepseek-chat"
    @State private var reasoner = "deepseek-reasoner"
    @State private var prefer = true
    @State private var busy = false
    @State private var note: String?
    @State private var confirmClear = false
    @State private var clearMsg = ""
    @State private var showOffline = false

    private let presets: [String: (String, String, String)] = [
        "DeepSeek": ("https://api.deepseek.com", "deepseek-chat", "deepseek-reasoner"),
        "通义千问": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus", ""),
        "智谱": ("https://open.bigmodel.cn/api/paas/v4", "glm-4-flash", ""),
        "Kimi": ("https://api.moonshot.cn/v1", "moonshot-v1-8k", ""),
        "自定义": ("", "", ""),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(cfg.bool("on") ? "已接入：\(cfg.str("name")) · \(cfg.str("model")) · 密钥 …\(cfg.str("tail"))" : "还没接入：填一个模型密钥，批改、讲题、出题、分析都会用它（不填也能用 Cloudflare 免费额度）。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("服务商", selection: $provider) { ForEach(presets.keys.sorted(), id: \.self) { Text($0).tag($0) } }
                        .onChange(of: provider) { p in if let v = presets[p] { base = v.0; model = v.1; reasoner = v.2 } }
                    SecureField(cfg.bool("on") ? "密钥已保存（不改就留空）" : "密钥（sk-…）", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("接口地址", text: $base).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("模型名", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("深度思考模型（可空）", text: $reasoner).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("默认优先用它（更聪明），Cloudflare 兜底", isOn: $prefer)
                    Button(busy ? "测试中…" : "保存并测试") { Task { await saveCfg() } }.disabled(busy)
                    if cfg.bool("on") { Button("清除密钥", role: .destructive) { Task { await clearKey() } } }
                    if let n = note { Text(n).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("接入模型") } footer: { Text("密钥存在你自己的服务器数据库里，不会再传回手机；后台批改任务也能用。") }

                Section("数据") {
                    HStack { Text("本地题库副本"); Spacer(); Text("\(sync.count) 题").foregroundStyle(.secondary) }
                    if let d = sync.lastSync { HStack { Text("上次同步"); Spacer(); Text(d, style: .relative).foregroundStyle(.secondary) } }
                    Button("立即同步题库") { sync.refresh(force: true) }
                    Button("离线题库") { showOffline = true }
                    Button("清空缓存") { LocalStore.shared.clearCache(); note = "缓存已清空" }
                    Button("清空历史记录…", role: .destructive) { Task { await clearHistory(dry: true) } }
                }

                Section("网页版") {
                    Button("打开完整网页版（拍照上传、Max 悬浮球等）") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.web = WebSpec(path: "/", title: "MAX NOTE 网页版") } }
                }

                Section("服务器") {
                    TextField("https://…", text: $site).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("保存地址") { if Site.save(site) { note = "已保存，重新打开 App 生效" } }
                    Button("退出登录", role: .destructive) { dismiss(); API.shared.logout() }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await loadCfg() }
            .alert("清空历史记录", isPresented: $confirmClear) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { Task { await clearHistory(dry: false) } }
            } message: { Text(clearMsg) }
            .sheet(isPresented: $showOffline) { OfflineLibraryView() }
        }
    }

    private func loadCfg() async {
        guard let c = try? await API.shared.obj("/api/ai/config") else { return }
        cfg = c
        if c.bool("on") {
            provider = presets[c.str("name")] != nil ? c.str("name") : "自定义"
            base = c.str("base"); model = c.str("model"); reasoner = c.str("reasoner"); prefer = c.bool("prefer")
        }
    }

    private func saveCfg() async {
        busy = true; note = nil
        defer { busy = false }
        do {
            cfg = try await API.shared.obj("/api/ai/config", method: "POST", json: ["name": provider == "自定义" ? "我的模型" : provider, "key": key, "base": base, "model": model, "reasoner": reasoner, "prefer": prefer])
            key = ""; note = "接入成功"; Haptic.ok()
        } catch { note = error.localizedDescription; Haptic.bad() }
    }

    private func clearKey() async {
        if let c = try? await API.shared.obj("/api/ai/config", method: "DELETE") { cfg = c; note = "已清除" }
    }

    private func clearHistory(dry: Bool) async {
        do {
            let r = try await API.shared.obj("/api/max/do", method: "POST", json: ["name": "清空历史记录", "arg": "", "dry": dry])
            if dry { if r.bool("empty") { note = r.str("msg") } else { clearMsg = r.str("msg"); confirmClear = true } }
            else { note = r.str("msg"); Haptic.ok(); NotificationCenter.default.post(name: .bankChanged, object: nil) }
        } catch { note = error.localizedDescription }
    }
}
