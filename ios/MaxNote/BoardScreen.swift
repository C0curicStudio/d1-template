import SwiftUI

/// 智能画板的种类：几何函数板 / 光学力学板 / 电路图板 / 计算板
enum SmartBoard {
    case geo(GeoBoard), circuit(CircuitBoard), calc(CalcBoard)

    @MainActor var answer: BoardAnswer {
        switch self { case .geo(let b): return b; case .circuit(let b): return b; case .calc(let b): return b }
    }

    /// 按题型标签选画板：电路 → 电路板；光路 / 受力 → 光学力学板；函数 → 带坐标轴的几何板；作图 / 证明 → 几何板
    @MainActor static func make(tag: String, subject: String) -> SmartBoard {
        switch tag {
        case "电路": return .circuit(CircuitBoard())
        case "光路", "受力": return .geo(GeoBoard(mode: .phys))
        case "函数": return .geo(GeoBoard(mode: .geo, axes: true))
        case "作图", "证明": return .geo(GeoBoard(mode: .geo))
        default: return .calc(CalcBoard(subject: subject))
        }
    }

    var title: String {
        switch self { case .geo(let b): return b.mode == .phys ? "光学力学板" : "几何函数板"; case .circuit: return "电路图板"; case .calc: return "计算解答板" }
    }
}

struct BoardScreen: View {
    let board: SmartBoard
    let scratch: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch board {
                    case .geo(let b): GeoBoardPanel(board: b, canvasHeight: 420)
                    case .circuit(let b): CircuitBoardPanel(board: b, canvasHeight: 420)
                    case .calc(let b): CalcBoardPanel(calc: b)
                    }
                    Text(scratch ? "草稿纸：不会交给老师" : "画出来的会交卷：文字描述交给 Max / Claude 批改，再配一张图").font(.caption).foregroundStyle(Color.mute)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WarmBackground())
            .navigationTitle(board.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
