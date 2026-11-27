import SwiftUI

/// 开屏：和系统启动画面（奶油底 + 居中的 M）完全重合，所以从图标点开时没有跳变；停一下，M 轻轻放大淡出，露出 App
struct SplashView: View {
    let onDone: () -> Void
    @State private var leaving = false

    var body: some View {
        ZStack {
            Color("LaunchBG")
            Image("LaunchM")                      // 和启动画面同一张图、同样大小、同在屏幕正中
                .scaleEffect(leaving ? 1.6 : 1)
                .opacity(leaving ? 0 : 1)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .allowsHitTesting(!leaving)
        .task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeInOut(duration: 0.45)) { leaving = true }
            try? await Task.sleep(nanoseconds: 480_000_000)
            onDone()
        }
    }
}
