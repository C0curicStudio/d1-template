import SwiftUI
import PDFKit

/// 打印机面板：蓝牙自动搜索 + 一键 AirPrint
struct PrinterSheet: View {
    @ObservedObject var web: Web
    @ObservedObject var bt: BTPrinter
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("蓝牙打印机", systemImage: "printer")
                                .font(.headline)
                            Spacer()
                            if bt.scanning { ProgressView() }
                            else { Button("重新搜索") { bt.start() }.font(.subheadline) }
                        }
                        Text(bt.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if bt.found.isEmpty {
                            Text("打开打印机电源并靠近手机，会自动出现在这里。")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 6)
                        }
                        ForEach(bt.found) { d in
                            Button { bt.connect(d.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: d.likelyPrinter ? "printer.fill" : "dot.radiowaves.left.and.right")
                                        .foregroundStyle(d.likelyPrinter ? Color.accentColor : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name).font(.body).foregroundStyle(.primary)
                                        Text(d.likelyPrinter ? "像是打印机" : "其他设备").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: signal(d.rssi))
                                        .foregroundStyle(.secondary)
                                    if bt.connectedName == d.name && bt.ready {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 26)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("纸宽（点数）").font(.subheadline.weight(.semibold))
                        Picker("纸宽", selection: $bt.paper) {
                            ForEach(BTPrinter.PaperWidth.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text("A4 宽适合便携 A4 热敏打印机；小票机选 58mm / 80mm，页面会按纸宽缩小。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 26)

                    if let p = bt.progress {
                        ProgressView(value: p).tint(.accentColor)
                    }

                    VStack(spacing: 10) {
                        Button {
                            busy = true
                            web.sheetsPDF { doc in
                                busy = false
                                if let doc = doc { bt.print(doc) } else { bt.status = "没有可打印的页面，先在 A4 排版里选题" }
                            }
                        } label: {
                            Text(busy ? "正在生成页面…" : "蓝牙打印")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .disabled(!bt.ready || busy)
                        .opacity(bt.ready ? 1 : 0.5)

                        Button("用 AirPrint 打印（Wi-Fi 打印机）") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { web.printSheets() }
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(20)
            }
            .navigationTitle("打印")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onAppear { bt.start() }
        .onDisappear { bt.stop() }
    }

    private func signal(_ rssi: Int) -> String {
        rssi > -60 ? "wifi" : rssi > -80 ? "wifi" : "wifi.slash"
    }
}
