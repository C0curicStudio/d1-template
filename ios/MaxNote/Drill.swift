import SwiftUI

/// Max 现场出题：题库里没有这个考点的同类题时，让 Max 出 3-10 道临时题（不进题库、不进错题本），答完当场判分
struct DrillView: View {
    let topic: String
    var like: Int? = nil
    let onAsk: (ChatSpec) -> Void

    private enum Phase { case intro, making, doing, done, failed }
    @State private var phase: Phase = .intro
    @State private var n = 5
    @State private var qs: [J] = []
    @State private var i = 0
    @State private var right = 0
    @State private var pick: String?
    @State private var text = ""
    @State private var checked = false
    @State private var ok = false
    @State private var showAnswer = false
    @State private var err: String?

    private func norm(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if u.value >= 0xFF01 && u.value <= 0xFF5E, let c = Unicode.Scalar(u.value - 0xFEE0) { out.unicodeScalars.append(c) }
            else if u.value == 0x3000 || CharacterSet.whitespacesAndNewlines.contains(u) { continue }
            else { out.unicodeScalars.append(u) }
        }
        return out
    }
    private func bare(_ s: String) -> String { norm(s).replacingOccurrences(of: "^[a-zA-Z]=", with: "", options: .regularExpression) }
    private func judge(_ q: J, _ mine: String) -> Bool {
        if q.str("type") == "single" { return norm(mine).uppercased() == (q.strs("answer").first ?? "").uppercased() }
        return !bare(mine).isEmpty && q.strs("answer").contains { bare($0) == bare(mine) }
    }
    private func shown(_ q: J) -> String { q.str("type") == "single" ? (q.strs("answer").first ?? "") : q.strs("answer").joined(separator: " / ") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch phase {
                case .intro: intro
                case .making: HStack(spacing: 12) { MaxLogo(size: 34, active: true, busy: true); Text("Max 出题中…（\(n) 道，约 10 秒）").foregroundStyle(Color.mute) }.frame(maxWidth: .infinity, minHeight: 200)
                case .doing: if qs.indices.contains(i) { question(qs[i]) }
                case .done: done
                case .failed: VStack(spacing: 12) { EmptyHint(icon: "wifi.exclamationmark", text: err ?? "出题失败"); Button("重试") { Task { await make() } }.buttonStyle(BrandButtonStyle(filled: true)) }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("题库里还没有「\(topic.split(separator: "/").last.map(String.init) ?? topic)」的同类题").font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
            Text("让 Max 现场出几道练一练：临时的，不进题库，也不计入错题本。").font(.subheadline).foregroundStyle(Color.mute)
            HStack(spacing: 8) {
                ForEach([3, 5, 8, 10], id: \.self) { k in
                    Button("\(k) 题") { Haptic.select(); n = k }.buttonStyle(BrandButtonStyle(filled: n == k))
                }
            }
            Button("让 Max 出题") { Task { await make() } }.buttonStyle(BrandButtonStyle(filled: true, small: false))
        }
        .card()
    }

    private func question(_ q: J) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Chip(text: "\(q.str("subject")) · \(q.str("topic"))"); Spacer(); Text("\(i + 1) / \(qs.count)").font(.footnote).foregroundStyle(Color.mute) }
            Text(plain(q.str("stem"))).font(.title3).foregroundStyle(Color.ink).lineSpacing(5)
            if q.str("type") == "single" {
                ForEach(q.strs("options"), id: \.self) { opt in
                    let letter = String(opt.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
                    let on = pick == letter
                    let isRight = checked && letter == (q.strs("answer").first ?? "").uppercased()
                    Button {
                        guard !checked else { return }
                        Haptic.select(); pick = letter; finish(q, letter)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: isRight ? "checkmark.circle.fill" : on && checked ? "xmark.circle.fill" : on ? "largecircle.fill.circle" : "circle").foregroundStyle(isRight || on ? Color.brand : Color.mute).font(.title3)
                            Text(plain(opt)).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(isRight ? Color.brand.opacity(0.14) : Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isRight || (on && checked) ? Color.brand : Color.hairline, lineWidth: isRight ? 1.5 : 0.6))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                TextField("你的答案", text: $text).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).card(0).disabled(checked)
                if !checked { Button("提交") { finish(q, text) }.buttonStyle(BrandButtonStyle(filled: true, small: false)).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            if checked {
                VStack(alignment: .leading, spacing: 8) {
                    Label(ok ? "答对了" : "这题没对", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill").font(.headline).foregroundStyle(ok ? Color.ink : Color.brand)
                    if ok, !q.str("explanation").isEmpty { Text(plain(q.str("explanation"))).font(.subheadline).foregroundStyle(Color.mute) }
                    if !ok {
                        HStack {
                            Button("让 Max 分析") { onAsk(ChatSpec(title: "问 Max", study: false, ctx: ["tmp": tmp(q, mine: pick ?? text, done: true)], prompt: "这题我做错了，帮我分析错在哪、怎么避免")) }.buttonStyle(BrandButtonStyle())
                            if !showAnswer { Button("看答案") { showAnswer = true }.buttonStyle(BrandButtonStyle()) }
                        }
                        if showAnswer { Text("正确答案：" + plain(shown(q)) + (q.str("explanation").isEmpty ? "" : "\n" + plain(q.str("explanation")))).font(.subheadline).foregroundStyle(Color.ink) }
                    }
                    Button(i + 1 < qs.count ? "下一题" : "完成") { next() }.buttonStyle(BrandButtonStyle(filled: true, small: false))
                }
                .card()
            }
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            EmptyHint(icon: "checkmark.seal", text: "答完了：对 \(right) / \(qs.count) · Bravo !")
            Button("再来一组") { phase = .intro; qs = []; i = 0; right = 0 }.buttonStyle(BrandButtonStyle(filled: true, small: false))
        }
    }

    private func tmp(_ q: J, mine: String, done: Bool) -> J {
        ["stem": q.str("stem"), "options": q.strs("options"), "answer": shown(q), "mine": mine, "exp": q.str("explanation"), "done": done]
    }

    private func finish(_ q: J, _ mine: String) {
        ok = judge(q, mine); checked = true
        if ok { right += 1; Haptic.ok() } else { Haptic.bad() }
    }

    private func next() {
        if i + 1 < qs.count { i += 1; pick = nil; text = ""; checked = false; ok = false; showAnswer = false } else { phase = .done }
    }

    private func make() async {
        phase = .making; err = nil
        do {
            var body: J = ["topic": topic, "n": n]
            if let l = like { body["like"] = l }
            let r = try await API.shared.obj("/api/max/gen", method: "POST", json: body)
            qs = r.arr("questions"); i = 0; right = 0; pick = nil; text = ""; checked = false
            if qs.isEmpty { throw NetError.server("Max 这次没出好题，再试一次") }
            phase = .doing
        } catch { err = error.localizedDescription; phase = .failed }
    }
}
