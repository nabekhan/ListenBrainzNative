import SwiftUI

@main
struct ListenBrainzNativeApp: App {
    @State private var session = SessionModel()
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    init() {
        PlaylistExportStaging.cleanupStaleFiles()
        UserDataExportShareStaging.cleanupStaleFiles()
        Task { await UserDataExportStorage.shared.cleanupExpired() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .tint(AppTheme.accent)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
    }
}
