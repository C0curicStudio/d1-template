import SwiftUI

/// 离线题库：没网时直接读本地 SQLite 副本（搜索、看答案和解析）
struct OfflineLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var subject = ""
    @State private var rows: [QRow] = []
    @State private var subjects: [String] = []

    var body: some View {
        NavigationStack {
            List(rows) { r in
                NavigationLink(value: r) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(r.subject).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                            if !r.topic.isEmpty { Text(r.topic).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if r.wrongs > 0 { Text("错 \(r.wrongs)").font(.caption).foregroundStyle(.red) }
                            Text(r.state).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(plain(r.stem)).font(.body).lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if rows.isEmpty { Text(LocalStore.shared.count() == 0 ? "还没有同步过题库，联网打开一次就会自动保存。" : "没有符合的题").foregroundStyle(.secondary).padding() }
            }
            .searchable(text: $query, prompt: "搜索题干、考点、解析")
            .navigationTitle("离线题库")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: QRow.self) { QDetail(row: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("科目", selection: $subject) {
                            Text("全部科目").tag("")
                            ForEach(subjects, id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .task(id: query + "|" + subject) {
                if subjects.isEmpty { subjects = LocalStore.shared.subjects() }
                rows = LocalStore.shared.search(query, subject: subject)
            }
        }
    }
}

struct QDetail: View {
    let row: QRow
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(row.subject).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                    if !row.topic.isEmpty { Text("· " + row.topic).font(.subheadline).foregroundStyle(.secondary) }
                    if !row.tag.isEmpty { Text(row.tag).font(.caption).padding(.horizontal, 8).padding(.vertical, 2).glassCapsule(interactive: false) }
                }
                Text(plain(row.stem)).font(.title3)
                if !row.options.isEmpty {
                    VStack(alignment: .leading, spacing: 6) { ForEach(row.options, id: \.self) { Text(plain($0)) } }
                }
                block("正确答案", row.answer.joined(separator: " / "))
                if !row.explanation.isEmpty { block("解析", row.explanation) }
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(plain(body)).font(.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }
}

/// 公式在原生里不渲染：去掉 $ 和常见 LaTeX 记号，保证可读
func plain(_ s: String) -> String {
    var t = s.replacingOccurrences(of: "$", with: "")
    for (a, b) in [("\\ce{", "{"), ("\\times", "×"), ("\\cdot", "·"), ("\\Omega", "Ω"), ("\\circ", "°"), ("\\leq", "≤"), ("\\geq", "≥"), ("\\pi", "π"), ("\\sqrt", "√"), ("\\frac", ""), ("\\left", ""), ("\\right", "")] {
        t = t.replacingOccurrences(of: a, with: b)
    }
    return t
}
