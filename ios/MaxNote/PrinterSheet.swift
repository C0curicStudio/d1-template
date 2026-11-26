import SwiftUI
import PDFKit

/// 打印机面板：蓝牙自动搜索 + 一键 AirPrint
struct PrinterSheet: View {
    let pdf: PDFDocument
    @ObservedObject var bt: BTPrinter
    @Environment(\.dismiss) private var dismiss

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
                                        .foregroundStyle(d.likelyPrinter ? Color.brand : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name).font(.body).foregroundStyle(.primary)
                                        Text(d.likelyPrinter ? "像是打印机" : "其他设备").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: signal(d.rssi))
                                        .foregroundStyle(.secondary)
                                    if bt.connectedName == d.name && bt.ready {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
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
                        ProgressView(value: p).tint(Color.brand)
                    }

                    VStack(spacing: 10) {
                        Button { bt.print(pdf) } label: { Text("蓝牙打印（\(pdf.pageCount) 页）") }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                            .disabled(!bt.ready)
                            .opacity(bt.ready ? 1 : 0.5)
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
