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
    @AppStorage("theme") private var theme = "system"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("ballShow") private var ballShow = true
    @AppStorage("ballFade") private var ballFade = true
    @AppStorage("autoCache") private var autoCache = true
    @AppStorage("wifiOnly") private var wifiOnly = false
    @AppStorage("maxDeep") private var maxDeep = false
    @AppStorage("maxWeb") private var maxWeb = false
    @StateObject private var pre = Prefetcher.shared
    @State private var cacheInfo = (count: 0, bytes: 0)
    @AppStorage("maxLen") private var maxLen = "m"
    @AppStorage("maxPref") private var maxPref = "auto"
    @State private var status: J = [:]
    @State private var kimi: String?

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
                Section("外观与操作") {
                    Picker("主题", selection: $theme) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    Toggle("触感反馈", isOn: $haptics)
                    Toggle("显示 Max 悬浮球", isOn: $ballShow)
                    Toggle("悬浮球闲置时变淡", isOn: $ballFade).disabled(!ballShow)
                    Button("悬浮球回到默认位置") { UserDefaults.standard.set(true, forKey: "ballRight"); UserDefaults.standard.set(0.74, forKey: "ballY2"); Haptic.tap() }.disabled(!ballShow)
                }

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

                Section {
                    Picker("回答长短", selection: $maxLen) { Text("简洁省额度").tag("s"); Text("标准").tag("m"); Text("详细").tag("l") }
                    Picker("优先用", selection: $maxPref) { Text("自动").tag("auto"); Text("我的模型").tag("ds"); Text("只用 Cloudflare").tag("cf") }
                    let cf = status.dict("cfu") ?? [:], ds = status.dict("ds") ?? [:]
                    if !status.isEmpty {
                        HStack { Text("Cloudflare 今日用量"); Spacer(); Text("\(cf.int("pct"))%").foregroundStyle(Color.mute) }
                        HStack { Text((ds.str("name").isEmpty ? "我的模型" : ds.str("name")) + " 今日用量"); Spacer(); Text(ds.bool("on") ? "\(ds.int("pct"))%" : "未接入").foregroundStyle(Color.mute) }
                        if let ch = status.dict("chats") { HStack { Text("今天和 Max 聊了"); Spacer(); Text("\(ch.int("used")) / \(ch.int("cap")) 次").foregroundStyle(Color.mute) } }
                    }
                    Toggle("默认开启深度思考", isOn: $maxDeep)
                    Toggle("默认开启联网搜索", isOn: $maxWeb)
                    Button("Max 自检（出错时让 AI 看日志）") { Task { await runKimi() } }
                    if let k = kimi { Text(k).font(.footnote).foregroundStyle(Color.mute) }
                } header: { Text("Max 助手") }

                Section {
                    Toggle("自动缓存题目（今日题、各科题、题库、错题本）", isOn: $autoCache)
                    Toggle("仅在 Wi-Fi 下自动缓存", isOn: $wifiOnly).disabled(!autoCache)
                    HStack { Text("已缓存"); Spacer(); Text("\(cacheInfo.count) 项 · \(ByteCountFormatter.string(fromByteCount: Int64(cacheInfo.bytes), countStyle: .file))").foregroundStyle(Color.mute) }
                    HStack { Text("上次缓存"); Spacer(); if let t = pre.lastRun { Text(t, style: .relative).foregroundStyle(Color.mute) } else { Text("还没有").foregroundStyle(Color.mute) } }
                    HStack { Text("网络"); Spacer(); Text(pre.online ? (pre.onWifi ? "Wi-Fi / 有线" : "蜂窝网络") : "离线").foregroundStyle(Color.mute) }
                    Button(pre.running ? (pre.progress.isEmpty ? "缓存中…" : pre.progress) : "立即缓存题目") { Task { await pre.run(force: true); cacheInfo = LocalStore.shared.cacheStats() } }.disabled(pre.running || !pre.online)
                    if pre.pending > 0 {
                        HStack { Text("没网时交的卷，等待补交"); Spacer(); Text("\(pre.pending) 份").foregroundStyle(Color.brand) }
                        Button("现在补交") { Task { await pre.flush() } }.disabled(!pre.online)
                    }
                    Button("清空缓存", role: .destructive) { LocalStore.shared.clearCache(); cacheInfo = LocalStore.shared.cacheStats() }
                } header: { Text("缓存与离线") } footer: { Text("缓存下来的题没网也能做；没网时交的卷先存在手机里，联网后自动补交。带画板或照片的答案需要联网才能交。") }

                Section("数据") {
                    HStack { Text("本地题库副本"); Spacer(); Text("\(sync.count) 题").foregroundStyle(.secondary) }
                    if let d = sync.lastSync { HStack { Text("上次同步"); Spacer(); Text(d, style: .relative).foregroundStyle(.secondary) } }
                    Button("立即同步题库") { sync.refresh(force: true) }
                    Button("离线题库") { showOffline = true }
                    Button("清空历史记录…", role: .destructive) { Task { await clearHistory(dry: true) } }
                }

                Section("网站") {
                    Link("在浏览器里打开网站", destination: Site.url)
                }

                Section("服务器") {
                    TextField("https://…", text: $site).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("保存地址") { if Site.save(site) { note = "已保存，重新打开 App 生效" } }
                    Button("退出登录", role: .destructive) { dismiss(); API.shared.logout() }
                }

                Section("关于") {
                    HStack { Text("MAX NOTE"); Spacer(); Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))").foregroundStyle(Color.mute) }
                    HStack { Text("服务器"); Spacer(); Text(Site.url.host ?? "").foregroundStyle(Color.mute) }
                    Text("题目、作答、错题都存在你自己的服务器（Cloudflare D1）；App 只在手机上缓存，不上传到别处。").font(.footnote).foregroundStyle(Color.mute)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { cacheInfo = LocalStore.shared.cacheStats(); await loadCfg() }
            .alert("清空历史记录", isPresented: $confirmClear) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { Task { await clearHistory(dry: false) } }
            } message: { Text(clearMsg) }
            .sheet(isPresented: $showOffline) { OfflineLibraryView() }
        }
    }

    private func runKimi() async {
        kimi = "自检中…"
        do { let r = try await API.shared.obj("/api/max/kimi", method: "POST", json: [:]); kimi = r.str("text").isEmpty ? "一切正常" : r.str("text") } catch { kimi = error.localizedDescription }
    }

    private func loadCfg() async {
        if let s = try? await API.shared.obj("/api/max/status") { status = s }
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
