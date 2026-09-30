import SwiftUI

struct RecommendationPreferencesView: View {
    @State private var model: RecommendationPreferencesModel
    @State private var changes: RecommendationPreferenceChanges
    @State private var readActionTask: Task<Void, Never>?
    @State private var removalTask: Task<Void, Never>?
    @State private var itemPendingRemoval: RecommendationPreference?
    @State private var failedRemoval: RecommendationPreference?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        account: Account,
        provider: (any DoNotRecommendProviding)? = nil,
        cache: EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage> = RecommendationPreferencesCaches.pages,
        pageSize: Int = 25,
        changes: RecommendationPreferenceChanges = .shared
    ) {
        _changes = State(initialValue: changes)
        _model = State(initialValue: RecommendationPreferencesModel(
            account: account,
            provider: provider,
            cache: cache,
            pageSize: pageSize,
            changes: changes
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize { hero }
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .accessibilityIdentifier("recommendation-preferences-screen")
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recommendation preferences")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { await model.load() }
        .onChange(of: changes.event(for: model.account.username)) { _, event in
            guard let event else { return }
            model.observeExternalChange(event)
        }
        .onDisappear {
            readActionTask?.cancel()
            removalTask?.cancel()
            model.cancel()
        }
        .confirmationDialog(
            "Remove preference?",
            isPresented: Binding(
                get: { itemPendingRemoval != nil },
                set: { if !$0 { itemPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove preference", role: .destructive) {
                guard let item = itemPendingRemoval else { return }
                itemPendingRemoval = nil
                startRemoval(item)
            }
            Button("Keep preference", role: .cancel) { itemPendingRemoval = nil }
        } message: {
            Text("This removes the saved choice from ListenBrainz.")
        }
        .alert(
            model.notice?.kind == .confirmation ? "Preference removed" : "Couldn’t remove preference",
            isPresented: Binding(
                get: { model.notice != nil },
                set: {
                    if !$0 {
                        model.dismissNotice()
                        failedRemoval = nil
                    }
                }
            )
        ) {
            if model.notice?.kind == .confirmation {
                Button("Done", role: .cancel) {
                    model.dismissNotice()
                    failedRemoval = nil
                }
            } else {
                Button("Try again") {
                    guard let item = failedRemoval else { return }
                    model.dismissNotice()
                    failedRemoval = nil
                    startRemoval(item)
                }
                Button("Not now", role: .cancel) {
                    model.dismissNotice()
                    failedRemoval = nil
                }
            }
        } message: {
            Text(model.notice?.message ?? "")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(AppTheme.heroGradient, in: .rect(cornerRadius: 17, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Your saved choices")
                    .font(.headline)
                Text("ListenBrainz saves these choices. They may not affect every recommendation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch model.state.phase {
        case .idle, .loading:
            ProgressView("Loading recommendation preferences…")
                .frame(maxWidth: .infinity, minHeight: 260)
        case let .failed(message):
            ContentUnavailableView {
                Label("Preferences couldn’t load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { startReadAction { await model.refresh() } }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        case .refreshing, .ready:
            if model.state.items.isEmpty { emptyContent } else { preferenceList }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = model.state.refreshMessage { warning(message) { await model.refresh() } }
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No saved preferences",
            systemImage: "slider.horizontal.3",
            description: Text("Save a choice from a recording to see it here.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var preferenceList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saved preferences").font(.title3.bold())
                Spacer(minLength: 8)
                Text("Showing \(model.state.items.count) of \(model.state.totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let message = model.state.refreshMessage { warning(message) { await model.refresh() } }
            ForEach(model.state.items) { item in
                RecommendationPreferenceRow(
                    item: item,
                    isRemoving: model.state.removingID == item.id,
                    removalIsBlocked: model.state.removingID != nil,
                    remove: { itemPendingRemoval = item }
                )
            }
            if model.state.isLoadingMore {
                ProgressView("Loading more preferences…").frame(maxWidth: .infinity).padding(.vertical, 8)
            } else if let message = model.state.loadMoreError {
                warning(message) { await model.loadMore() }
            } else if model.state.hasMore {
                Button("Load more") { startReadAction { await model.loadMore() } }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("recommendation-preferences-load-more")
            }
        }
    }

    @ViewBuilder
    private func warning(_ message: String, retry: @escaping @MainActor () async -> Void) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    warningLabel(message)
                    Button("Retry", action: { startReadAction(retry) })
                        .font(.footnote.weight(.semibold))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    warningLabel(message)
                    Spacer(minLength: 8)
                    Button("Retry", action: { startReadAction(retry) })
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func warningLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func startReadAction(_ action: @escaping @MainActor () async -> Void) {
        readActionTask?.cancel()
        readActionTask = Task { await action() }
    }

    private func startRemoval(_ item: RecommendationPreference) {
        guard removalTask == nil else { return }
        removalTask = Task { @MainActor in
            let succeeded = await model.remove(item)
            if !succeeded, !Task.isCancelled, model.notice?.kind == .error {
                failedRemoval = item
            }
            removalTask = nil
        }
    }
}

private struct RecommendationPreferenceRow: View {
    let item: RecommendationPreference
    let isRemoving: Bool
    let removalIsBlocked: Bool
    let remove: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(item.entity.displayName, systemImage: "music.note")
                    .font(.headline)
                Spacer(minLength: 8)
                if isRemoving { ProgressView().accessibilityLabel("Removing preference") }
            }
            Text(verbatim: item.entityMBID.uuidString.lowercased())
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .accessibilityLabel("MusicBrainz ID \(item.entityMBID.uuidString)")
            metadata
            if dynamicTypeSize.isAccessibilitySize {
                buttons
            } else {
                HStack(spacing: 12) { buttons }
            }
        }
        .padding(15)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Saved \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
            if let expiresAt = item.expiresAt {
                Text("Ends \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
            } else {
                Text("Until you remove it")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var buttons: some View {
        Link(destination: item.musicBrainzURL) {
            Label("Open in MusicBrainz", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.bordered)
        Button(role: .destructive, action: remove) {
            Label("Remove preference", systemImage: "minus.circle")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(removalIsBlocked)
        .accessibilityIdentifier(
            "remove-recommendation-preference-\(item.entity.pathComponent)-\(item.entityMBID.uuidString.lowercased())"
        )
    }
}

#if DEBUG
struct RecommendationPreferencesVisualQAScreen: View {
    enum State { case populated, empty, failure }
    let state: State

    var body: some View {
        NavigationStack {
            RecommendationPreferencesView(
                account: Account(username: "visual-listener", token: "visual-token"),
                provider: RecommendationPreferencesVisualProvider(state: state),
                cache: EntityDetailCache()
            )
        }
    }
}

struct RecommendationPreferencesVisualProvider: DoNotRecommendProviding {
    let state: RecommendationPreferencesVisualQAScreen.State
    func entries(username: String, offset: Int, count: Int) async throws -> RecommendationPreferencePage {
        if state == .failure { throw DoNotRecommendProviderError.readUnavailable }
        let entries: [RecommendationPreference] = state == .populated ? [
            .init(entity: .artist, entityMBID: UUID(uuidString: "1f9df192-a621-4f54-8850-2c5373b7eac9")!, createdAt: .now.addingTimeInterval(-86_400 * 5), expiresAt: nil),
            .init(entity: .recording, entityMBID: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!, createdAt: .now.addingTimeInterval(-86_400), expiresAt: .now.addingTimeInterval(86_400 * 7))
        ] : []
        return .init(username: username, items: entries, serverCount: entries.count, offset: offset, totalCount: entries.count)
    }
    func add(entity: RecommendationPreferenceEntity, entityMBID: UUID, until: Date?) async throws {}
    func remove(entity: RecommendationPreferenceEntity, entityMBID: UUID) async throws {}
}
#endif
