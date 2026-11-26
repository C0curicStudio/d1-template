import SwiftUI
import UIKit

// MAX NOTE 的颜色：暖米色底 + 珊瑚色强调（和网站一致），深色模式自动切换。
// 不依赖资源目录里的 AccentColor（上一版它被渲染成近黑色，按钮和图标全看不见），颜色都在代码里写死。
private func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

extension Color {
    static let brand = dyn(UIColor(red: 0.788, green: 0.392, blue: 0.259, alpha: 1), UIColor(red: 0.878, green: 0.541, blue: 0.416, alpha: 1))
    static let cream = dyn(UIColor(red: 0.957, green: 0.937, blue: 0.902, alpha: 1), UIColor(red: 0.122, green: 0.114, blue: 0.102, alpha: 1))
    static let card = dyn(UIColor(white: 1, alpha: 0.62), UIColor(red: 0.165, green: 0.153, blue: 0.137, alpha: 1))
    static let hairline = dyn(UIColor(white: 0, alpha: 0.07), UIColor(white: 1, alpha: 0.09))
    static let ink = dyn(UIColor(red: 0.169, green: 0.149, blue: 0.133, alpha: 1), UIColor(red: 0.929, green: 0.910, blue: 0.875, alpha: 1))
    static let mute = dyn(UIColor(red: 0.431, green: 0.396, blue: 0.357, alpha: 1), UIColor(red: 0.639, green: 0.608, blue: 0.565, alpha: 1))
}

struct WarmBackground: View {
    var body: some View {
        ZStack {
            Color.cream
            LinearGradient(colors: [Color.brand.opacity(0.10), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
        }
        .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.hairline, lineWidth: 0.6))
    }
}
extension View {
    func card(_ padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// 页面里的小节标题
struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    init(_ t: String, trailing: String? = nil) { text = t; self.trailing = trailing }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
            Spacer()
            if let t = trailing { Text(t).font(.footnote).foregroundStyle(Color.mute) }
        }
        .padding(.horizontal, 4).padding(.top, 10)
    }
}

/// 品牌按钮：实心珊瑚 / 淡珊瑚。不用系统 .bordered（放进列表行里会和整行点击抢事件、颜色也不对）
struct BrandButtonStyle: ButtonStyle {
    var filled = false
    var small = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .padding(.horizontal, small ? 14 : 20).padding(.vertical, small ? 7 : 13)
            .frame(maxWidth: small ? nil : .infinity)
            .foregroundStyle(filled ? Color.white : Color.brand)
            .background(filled ? Color.brand : Color.brand.opacity(0.15), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Max 的标志：12 道长短不一的放射光芒（和网站、图标一样）。
/// active：光芒缓缓呼吸、慢慢转；busy（思考中）：转得更快、伸缩更大
struct MaxLogo: View {
    var size: CGFloat = 30
    var active = false
    var busy = false

    var body: some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in canvas(t: tl.date.timeIntervalSinceReferenceDate) }
        } else {
            canvas(t: 0)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { ctx, sz in
            let s = sz.width / 24, c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let radii: [CGFloat] = [10, 7.6, 9.4, 7.2, 10, 8, 9.2, 7.4, 10, 7.8, 9.6, 7.3]
            let speed = busy ? 2.6 : 0.9, amp = busy ? 0.2 : 0.07, spin = t / (busy ? 5 : 40) * 2 * .pi
            for (i, r0) in radii.enumerated() {
                let a = Double(i) / 12 * 2 * .pi - .pi / 2 + (active ? spin : 0)
                let r = r0 * (1 + CGFloat(active ? amp * sin(t * speed + Double(i) * 0.9) : 0))
                var p = Path()
                p.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * 2.4 * s, y: c.y + CGFloat(sin(a)) * 2.4 * s))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r * s, y: c.y + CGFloat(sin(a)) * r * s))
                ctx.stroke(p, with: .color(Color.brand), style: StrokeStyle(lineWidth: 2.3 * s, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
