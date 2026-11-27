import SwiftUI

@main
struct MaxNoteApp: App {
    @AppStorage("theme") private var theme = "system"
    init() { Site.migrate() }
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.brand)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        }
    }
}
