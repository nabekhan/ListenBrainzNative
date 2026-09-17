import SwiftUI

struct RootView: View {
    @Bindable var session: SessionModel

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                LaunchView()
            case .signedOut:
                AuthenticationView(session: session)
            case let .active(account):
                MainTabView(account: account, session: session)
                    .id(account)
            }
        }
        .task { await session.restore() }
    }
}
private struct LaunchView: View {
    var body: some View {
        ZStack {
            AppTheme.heroGradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 68, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text("Brainz")
                    .font(.largeTitle.bold())
            }
            .foregroundStyle(.white)
        }
    }
}
