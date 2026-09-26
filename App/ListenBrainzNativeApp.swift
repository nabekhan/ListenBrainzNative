import SwiftUI

@main
struct ListenBrainzNativeApp: App {
    @State private var session = SessionModel()
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    init() {
        PlaylistExportStaging.cleanupStaleFiles()
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .tint(AppTheme.accent)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
    }
}
