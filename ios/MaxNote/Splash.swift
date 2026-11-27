import SwiftUI

/// 开屏：珊瑚色底 + 放大的大 M（和图标同一个 M）。先轻轻弹出，停一下，再继续放大淡出，露出 App
struct SplashView: View {
    let onDone: () -> Void
    @State private var shown = false
    @State private var leaving = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.89, green: 0.60, blue: 0.47), Color(red: 0.80, green: 0.42, blue: 0.29), Color(red: 0.70, green: 0.32, blue: 0.20)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(shown ? 1 : 0)
                Color("LaunchBG").opacity(shown ? 0 : 1) // 和系统启动画面同色，衔接没有闪烁
                Image("SplashM")
                    .resizable().scaledToFit()
                    .frame(width: min(geo.size.width * 0.66, 420))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    .scaleEffect(leaving ? 2.4 : (shown ? 1 : 0.72))
                    .opacity(leaving ? 0 : (shown ? 1 : 0))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .opacity(leaving ? 0 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!leaving)
        .task {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { shown = true }
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            withAnimation(.easeIn(duration: 0.5)) { leaving = true }
            try? await Task.sleep(nanoseconds: 520_000_000)
            onDone()
        }
    }
}
