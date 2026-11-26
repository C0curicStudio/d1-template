import XCTest

/// 自动把每个页面截图存到 /tmp/maxshots（云端模拟器跑，演示数据模式）
final class ShotsTests: XCTestCase {
    let dir = "/tmp/maxshots"

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    func shot(_ n: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(n).png"))
    }

    @discardableResult
    func tap(_ e: XCUIElement, _ t: TimeInterval = 4) -> Bool {
        guard e.waitForExistence(timeout: t) else { return false }
        e.tap(); return true
    }

    func any(_ app: XCUIApplication, _ label: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch }
    func begins(_ app: XCUIApplication, _ label: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch }

    func top(_ app: XCUIApplication) { for _ in 0..<3 { app.swipeDown() } }

    func run(_ mode: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + (mode == "dark" ? ["-AppleInterfaceStyle", "Dark"] : ["-AppleInterfaceStyle", "Light"])
        app.launch()
        sleep(3)
        let p = mode + "-"

        // 首页
        shot(p + "01-home")
        app.swipeUp(); sleep(1); shot(p + "02-home-b")
        app.swipeUp(); sleep(1); shot(p + "03-home-c")
        top(app)

        // 其他标签
        for (i, name) in ["题库", "错题本", "学习台"].enumerated() {
            top(app)
            if tap(app.tabBars.buttons[name]) || tap(any(app, name)) {
                sleep(2); shot(p + "1\(i)-\(name)-a")
                app.swipeUp(); sleep(1); shot(p + "1\(i)-\(name)-b")
                top(app)
            }
        }

        // 题库「全集」、详情
        top(app)
        if tap(app.tabBars.buttons["题库"]) {
            sleep(1)
            if tap(app.segmentedControls.buttons.element(boundBy: 1), 2) { sleep(2); shot(p + "20-bank-all") }
            top(app)
            if tap(begins(app, "化学"), 2) || tap(app.cells.element(boundBy: 1), 2) { sleep(2); shot(p + "21-detail") ; app.navigationBars.buttons.firstMatch.tap() }
        }

        // 学习台：微课
        top(app)
        if tap(app.tabBars.buttons["学习台"]) {
            sleep(1)
            if tap(app.buttons["学"].firstMatch, 3) || tap(any(app, "学"), 3) { sleep(4); shot(p + "30-lesson"); tap(app.buttons["完成"], 2) }
        }

        // 悬浮球 → 聊天（键盘要自动弹出）
        top(app)
        tap(app.tabBars.buttons["首页"], 2)
        sleep(1)
        if tap(any(app, "问 Max"), 3) {
            sleep(2); shot(p + "40-chat-open")
            let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
            if input.waitForExistence(timeout: 3) {
                input.tap(); input.typeText("我最该先补什么")
                shot(p + "41-chat-typed")
                tap(app.buttons["chatSend"], 2)
                sleep(5); shot(p + "42-chat-reply")
            }
            tap(app.buttons["关闭"], 2)
        }

        // 做题
        sleep(1)
        if tap(begins(app, "今日练习"), 3) {
            sleep(3); shot(p + "50-quiz-1")
            if tap(begins(app, "卡住了"), 2) { sleep(2); shot(p + "50b-quiz-hint") }
            tap(begins(app, "B."), 2); sleep(1); shot(p + "51-quiz-picked")
            tap(app.buttons["下一题"], 2); sleep(1); shot(p + "52-quiz-2")
            tap(begins(app, "A."), 1); tap(begins(app, "B."), 1)
            tap(app.buttons["下一题"], 2); sleep(1)
            let f = app.textFields["你的答案"]
            if f.waitForExistence(timeout: 2) { f.tap(); f.typeText("2,3"); shot(p + "53-quiz-fill") }
            app.swipeDown()
            tap(app.buttons["下一题"], 2); sleep(1); shot(p + "54-quiz-short")
            if tap(begins(app, "交卷"), 2) { sleep(4); shot(p + "55-quiz-result"); app.swipeUp(); sleep(1); shot(p + "56-quiz-result-b") }
            tap(app.buttons["完成"], 2)
        }

        // 设置 / 打印
        sleep(1)
        top(app)
        if tap(app.navigationBars.buttons.firstMatch, 3) {
            if tap(any(app, "设置"), 2) { sleep(2); shot(p + "60-settings"); app.swipeUp(); sleep(1); shot(p + "61-settings-b"); tap(app.buttons["完成"], 2) }
        }
        sleep(1)
        if tap(app.navigationBars.buttons.firstMatch, 3) {
            if tap(any(app, "A4 排版打印"), 2) {
                sleep(2); shot(p + "70-print")
                if tap(begins(app, "选题（已选"), 2) { sleep(1); tap(app.buttons["全选"], 2); shot(p + "71-print-pick"); tap(begins(app, "选题（已选"), 2) }
                top(app)
                if tap(begins(app, "生成 A4 预览"), 2) { sleep(4); shot(p + "72-print-preview") }
            }
        }
        app.terminate()
    }

    func testLight() { run("light") }
    func testDark() { run("dark") }
}
