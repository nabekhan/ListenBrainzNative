import SwiftUI

@main
struct ListenBrainzNativeApp: App {
    @State private var session = SessionModel()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .tint(AppTheme.accent)
        }
    }
}
