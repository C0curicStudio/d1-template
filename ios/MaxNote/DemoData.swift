import Foundation

#if DEBUG
/// 演示数据：只在调试构建里、带 -demo 启动参数时用（云端模拟器自动截图检查界面）。正式 IPA 不包含。
enum Demo {
    static var on: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    private static func parse(_ s: String) -> Any { (try? JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed])) ?? [:] }

    static func data(_ path: String, _ method: String) -> Data? {
        let p = path.split(separator: "?").first.map(String.init) ?? path
        let body: String?
        switch p {
        case "/api/home": body = home
        case "/api/study": body = study
        case "/api/study/plan": body = plan
        case "/api/bank": body = bank
        case "/api/wrong": body = wrong
        case "/api/max/wrongsum": body = wrongsum
        case "/api/practice": body = practice
        case "/api/submit": body = #"{"attempt_ids":[1,2,3]}"#
        case "/api/attempts": body = attempts
        case "/api/library": body = bank
        case "/api/print": body = printItems
        case "/api/ai/config": body = #"{"on":false}"#
        case "/api/max/hint": body = #"{"text":"先想想：用过氧化氢制氧不需要加热，而且要「较纯净」，该选哪种收集方法？"}"#
        case "/api/max/organize": body = #"{"done":3,"left":0}"#
        case "/api/max/classify": body = #"{"status":"done","n":2}"#
        case "/api/max/do": body = #"{"msg":"演示模式","n":0,"empty":true}"#
        default:
            if p.hasPrefix("/api/question/") { body = question } else { body = nil }
        }
        return body.map { Data($0.utf8) }
    }

    static let chatText = "你最该先补的是 **化学 › 制取氧气**：近 60 天练了 4 题，只对 1 题，掌握度 25%。\n\n典型错因有两个：\n1. **除杂方法选错**：过氧化氢制氧不需要加热\n2. **缺气体符号**：方程式 $\\ce{2H2O2 ->[MnO2] 2H2O + O2 ^}$ 要标 ↑\n\n先看微课再练 5 题：\n[[练:化学/制取氧气]]"
    static let lessonText = "**一句话讲清**：实验室制氧，看「反应物状态 + 是否加热」选发生装置，看「气体性质」选收集装置。\n\n**核心知识**\n1. 过氧化氢 + 二氧化锰：固液常温型，$\\ce{2H2O2 ->[MnO2] 2H2O + O2 ^}$\n2. 高锰酸钾加热：固固加热型，试管口放一团棉花\n3. 氧气不易溶于水 → 排水法（较纯净）；密度比空气大 → 向上排空气法（较干燥）\n\n**一道例题**\n题：用 $\\frac{1}{2}$ mol 过氧化氢制氧，理论上得到多少 mol 氧气？\n思路：$2:1$ 的关系 → 答案 $\\frac{1}{4}$ mol。\n\n**最容易错的 2 点**\n1. 忘记标气体符号 ↑\n2. 收集「较纯净」的氧气误选向上排空气法\n\n[[练:化学/制取氧气]]"

    private static let home = #"""
    {"today_count":15,"pending_uploads":0,"pending_grades":0,"queue_count":15,"marked":0,"today":"2026-11-26","streak":0,"done_today":false,"right7":0,
     "subjects":[{"subject":"化学","total":6,"undone":3,"due":2},{"subject":"数学","total":5,"undone":2,"due":1},{"subject":"物理","total":4,"undone":1,"due":1},{"subject":"语文","total":3,"undone":3,"due":0}],
     "recent":[{"id":1,"subject":"化学","tag":"选择","stem":"化学·用过氧化氢溶液和二氧化锰制取较纯净的氧气，应选（　）","created_at":"2026-11-26 03:00:00"},
               {"id":2,"subject":"数学","tag":"填空","stem":"数学·解方程 $x^2-5x+6=0$，则 $x=$ ______","created_at":"2026-11-26 03:00:00"},
               {"id":3,"subject":"物理","tag":"计算","stem":"物理·两电阻 $R_1=10\\Omega$、$R_2=20\\Omega$ 串联，电源电压 6V，求电路中的电流","created_at":"2026-11-26 03:00:00"}],
     "brief":{"say":"先做化学制氧基础题，再穿插旧错题。","order":[1,2,3,4],"weakIds":[1,2],"cands":15,
              "topics":[{"subject":"化学","topic":"制取氧气","n":4,"wrong":3},{"subject":"物理","topic":"电荷及其守恒定律","n":4,"wrong":3},{"subject":"数学","topic":"一次函数的图像","n":5,"wrong":2}]}}
    """#

    private static let study = #"""
    {"n":125,"right":79,"ai":{"on":false},
     "plan":{"say":"按最薄弱的先来：先讲后练","ai":false,"steps":[
        {"kind":"learn","topic":"化学/制取氧气","why":"掌握度 25%，先把概念弄懂","n":0},
        {"kind":"practice","topic":"化学/制取氧气","why":"讲完马上练","n":5},
        {"kind":"learn","topic":"物理/电荷及其守恒定律","why":"掌握度 25%，先把概念弄懂","n":0},
        {"kind":"practice","topic":"数学/一次函数的图像","why":"掌握度 60%，再巩固一下","n":5}]},
     "rows":[{"subject":"化学","topic":"制取氧气","n":4,"r":1,"total":6,"wrong":3,"mastery":33,"level":"薄弱"},
             {"subject":"化学","topic":"物质的变化","n":3,"r":3,"total":2,"wrong":0,"mastery":80,"level":"练习中"},
             {"subject":"数学","topic":"一次函数的图像","n":5,"r":3,"total":3,"wrong":2,"mastery":57,"level":"薄弱"},
             {"subject":"数学","topic":"一元二次方程","n":8,"r":7,"total":2,"wrong":0,"mastery":90,"level":"熟练"},
             {"subject":"物理","topic":"电荷及其守恒定律","n":4,"r":1,"total":4,"wrong":3,"mastery":33,"level":"薄弱"},
             {"subject":"物理","topic":"串联电路","n":0,"r":0,"total":1,"wrong":0,"level":"未练"}]}
    """#

    private static let plan = #"""
    {"say":"AI 排的：先补制取氧气","ai":true,"steps":[{"kind":"learn","topic":"化学/制取氧气","why":"概念最弱","n":0},{"kind":"practice","topic":"化学/制取氧气","why":"讲完马上练","n":5}]}
    """#

    private static let items = #"""
    [{"id":1,"subject":"化学","category":"实验","topic":"制取氧气","type":"single","tag":"选择","stem":"化学·用过氧化氢溶液和二氧化锰制取较纯净的氧气，应选（　）","tries":2,"wrongs":2,"pending":0,"last":0,"max_reason":"除杂方法选错","due":null,"state":"在用"},
     {"id":2,"subject":"化学","category":"实验","topic":"制取氧气","type":"short","tag":"简答","stem":"化学·写出高锰酸钾加热制取氧气的化学方程式 $\\ce{KMnO4}$","tries":1,"wrongs":1,"pending":0,"last":0,"max_reason":"缺气体符号","due":null,"state":"在用"},
     {"id":3,"subject":"化学","category":"实验","topic":"制取氧气","type":"single","tag":"选择","stem":"化学·高锰酸钾制氧：试管口放一团棉花的作用是（　）","tries":1,"wrongs":1,"pending":0,"last":0,"max_reason":"词类活用不明","due":null,"state":"在用"},
     {"id":4,"subject":"数学","category":"方程","topic":"一元二次方程","type":"fill","tag":"填空","stem":"数学·解方程 $x^2-5x+6=0$，则 $x=$ ______","tries":0,"wrongs":0,"pending":0,"last":null,"max_reason":null,"due":null,"state":"在用"},
     {"id":5,"subject":"数学","category":"函数","topic":"一次函数的图像","type":"fill","tag":"填空","stem":"数学·一次函数 $y=2x-3$ 的图像与 $y$ 轴交点坐标为 ______","tries":2,"wrongs":1,"pending":0,"last":1,"max_reason":"计算错误","due":null,"state":"在用"},
     {"id":6,"subject":"物理","category":"电学","topic":"电荷及其守恒定律","type":"single","tag":"选择","stem":"物理·用丝绸摩擦过的玻璃棒带正电，是因为（　）","tries":2,"wrongs":2,"pending":0,"last":0,"max_reason":"概念不清","due":null,"state":"在用"},
     {"id":7,"subject":"物理","category":"电学","topic":"串联电路","type":"short","tag":"计算","stem":"物理·两电阻 $R_1=10\\Omega$、$R_2=20\\Omega$ 串联，电源电压 6V，求电路中的电流","tries":0,"wrongs":0,"pending":1,"last":null,"max_reason":null,"due":"2026-11-28","state":"已隐藏"}]
    """#
    private static var bank: String { "{\"today\":\"2026-11-26\",\"total\":7,\"items\":" + items + "}" }
    private static var wrong: String { "{\"today\":\"2026-11-26\",\"items\":" + items + "}" }

    private static let wrongsum = #"""
    {"total":15,"max":{"审题不清":4,"化学方程式书写不规范":3,"概念不清":3,"待分析":2},"summary":"主要问题：审题不清、化学方程式书写不规范。下一步：先补「制取氧气」，做 5 道题，再练方程式配平。","todo":2,"thinking":false,"stale":false}
    """#

    private static let question = #"""
    {"id":1,"subject":"化学","category":"实验","topic":"制取氧气","tag":"选择","type":"single","stem":"化学·用过氧化氢溶液和二氧化锰制取较纯净的氧气，应选（　）",
     "options":["A. 向上排空气法收集","B. 排水法收集","C. 加热高锰酸钾","D. 向下排空气法收集"],"answer":["B"],"explanation":"要「较纯净」用排水法；过氧化氢制氧是固液常温型，不用加热。",
     "attempts":[{"id":9,"answer_text":"A","is_correct":0,"status":"已判","error_reason":"除杂方法选错","comment":"排空气法收集的氧气不够纯净","created_at":"2026-11-25 10:00:00"},
                 {"id":8,"answer_text":"C","is_correct":0,"status":"已判","error_reason":"概念不清","comment":"","created_at":"2026-11-24 10:00:00"}]}
    """#

    private static let practice = #"""
    [{"id":1,"subject":"化学","topic":"制取氧气","type":"single","tag":"选择","stem":"用过氧化氢溶液和二氧化锰制取较纯净的氧气，应选（　）","options":["A. 向上排空气法收集","B. 排水法收集","C. 加热高锰酸钾","D. 向下排空气法收集"]},
     {"id":6,"subject":"物理","topic":"电荷及其守恒定律","type":"multi","tag":"选择","stem":"关于电荷，下列说法正确的是（　）（多选）","options":["A. 同种电荷相互排斥","B. 异种电荷相互吸引","C. 摩擦起电创造了电荷","D. 电荷守恒"]},
     {"id":4,"subject":"数学","topic":"一元二次方程","type":"fill","tag":"填空","stem":"解方程 $x^2-5x+6=0$，则 $x=$ ______（填两个根）","options":[]},
     {"id":7,"subject":"物理","topic":"串联电路","type":"short","tag":"计算","stem":"两电阻 $R_1=10\\Omega$、$R_2=20\\Omega$ 串联，电源电压 6V，求电路中的电流并写出过程。","options":[]}]
    """#

    private static let attempts = #"""
    [{"id":1,"question_id":1,"subject":"化学","topic":"制取氧气","type":"single","status":"已判","is_correct":1,"answer_text":"B","stem":"化学·用过氧化氢溶液和二氧化锰制取较纯净的氧气，应选（　）","answer":["B"],"comment":"","error_reason":""},
     {"id":2,"question_id":6,"subject":"物理","topic":"电荷及其守恒定律","type":"multi","status":"已判","is_correct":0,"answer_text":"AC","stem":"物理·关于电荷，下列说法正确的是（　）（多选）","answer":["A","B","D"],"comment":"摩擦起电只是转移电荷，不创造电荷","error_reason":"概念不清"},
     {"id":3,"question_id":4,"subject":"数学","topic":"一元二次方程","type":"fill","status":"已判","is_correct":1,"answer_text":"2,3","stem":"数学·解方程 $x^2-5x+6=0$，则 $x=$ ______","answer":["2,3"],"comment":"","error_reason":""}]
    """#

    private static let printItems = #"""
    {"items":[{"id":1,"subject":"化学","topic":"制取氧气","type":"single","tag":"选择","stem":"用过氧化氢溶液和二氧化锰制取较纯净的氧气，应选（　）","options":["A. 向上排空气法收集","B. 排水法收集","C. 加热高锰酸钾","D. 向下排空气法收集"],"answer":["B"],"explanation":"要较纯净用排水法"},
              {"id":4,"subject":"数学","topic":"一元二次方程","type":"fill","tag":"填空","stem":"解方程 $x^2-5x+6=0$，则 $x=$ ______","options":[],"answer":["2,3"],"explanation":"因式分解 $(x-2)(x-3)=0$"}]}
    """#
}
#endif
