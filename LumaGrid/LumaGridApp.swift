import SwiftUI

@main
struct LumaGridApp: App {
    @State private var app = AppModel.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { app.start() }
        }
    }
}
