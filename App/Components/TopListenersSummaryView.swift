import SwiftUI

private struct TopListenersProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any TopListenersProviding)? = nil
}

extension EnvironmentValues {
    var topListenersProvider: (any TopListenersProviding)? {
        get { self[TopListenersProviderEnvironmentKey.self] }
        set { self[TopListenersProviderEnvironmentKey.self] = newValue }
    }
}

/// A small on-demand community view for a single canonical MusicBrainz entity.
struct TopListenersSummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.topListenersProvider) private var provider
    @State private var model: TopListenersModel?
    @State private var showsAll: Bool
    @State private var retryTask: Task<Void, Never>?

    let entity: TopListenersEntity
    let viewer: Account
    private let initiallyExpanded: Bool

    init(entity: TopListenersEntity, viewer: Account, initiallyExpanded: Bool = false) {
        self.entity = entity
        self.viewer = viewer
        self.initiallyExpanded = initiallyExpanded
        _showsAll = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        Group {
            switch model?.phase ?? .idle {
            case .idle, .loading:
                loadingCard
            case let .loaded(value):
                listenersCard(value)
            case .unavailable:
                EmptyView()
            case .failed:
                failureCard
            }
        }
        .task(id: entity) {
            let current: TopListenersModel
            if let provider {
                current = TopListenersModel(
                    entity: entity,
                    scope: .authenticated(token: viewer.token),
                    provider: provider
                )
            } else {
                current = TopListenersModel(entity: entity, token: viewer.token)
            }
            model = current
            showsAll = initiallyExpanded
            await current.load()
        }
        .onDisappear {
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private var loadingCard: some View {
        card {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top listeners")
                        .font(.headline)
                    Text("Loading top listeners…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func listenersCard(_ result: TopListeners) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TOP LISTENERS")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("Up to 10 listeners on ListenBrainz · all time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model?.refreshMessage != nil {
                    Label("Couldn’t refresh. Showing saved rankings.", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    let listeners = visibleListeners(result)
                    ForEach(Array(listeners.enumerated()), id: \.element.id) { index, listener in
                        NavigationLink(value: listener.user) {
                            listenerRow(listener, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                        if listener.id != listeners.last?.id {
                            Divider().padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 46)
                        }
                    }
                }

                if result.listeners.count > 5 {
                    Button(
                        showsAll
                            ? String(localized: "Show fewer listeners")
                            : String(localized: "Show all available listeners")
                    ) {
                        withAnimation(.snappy) { showsAll.toggle() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        showsAll
                            ? String(localized: "Shows the first five listeners")
                            : String(localized: "Shows every listener returned by ListenBrainz")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func listenerRow(_ listener: TopListener, rank: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("#\(rank)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    listenerAvatar(listener, size: 44)
                    Spacer(minLength: 8)
                    disclosureIndicator
                }
                Text(listener.username)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(listenCountLabel(listener))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(localized: "\(rank). \(listener.username), \(listenCountLabel(listener))")
            )
            .accessibilityHint("Opens this listener’s profile")
        } else {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
                    .accessibilityHidden(true)
                listenerAvatar(listener, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(listener.username)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    Text(listenCountLabel(listener))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                disclosureIndicator
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(localized: "\(rank). \(listener.username), \(listenCountLabel(listener))")
            )
            .accessibilityHint("Opens this listener’s profile")
        }
    }

    private func listenerAvatar(_ listener: TopListener, size: CGFloat) -> some View {
        Circle()
            .fill(AppTheme.artworkGradient(seed: listener.username))
            .frame(width: size, height: size)
            .overlay {
                Text(listener.username.prefix(1).uppercased())
                    .font(.caption.bold())
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.forward")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func listenCountLabel(_ listener: TopListener) -> String {
        String(localized: "\(listener.listenCount) listens")
    }

    private var failureCard: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top listeners couldn’t load")
                        .font(.subheadline.weight(.semibold))
                    Text("ListenBrainz couldn’t load this ranking. Try again in a moment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Try again") {
                    guard let model else { return }
                    retryTask?.cancel()
                    retryTask = Task { await model.retry() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func visibleListeners(_ result: TopListeners) -> [TopListener] {
        Array(result.listeners.prefix(showsAll ? result.listeners.count : 5))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }
}
