import SwiftUI

struct PersonalRecommendationSheet: View {
    @Bindable var model: RecordingShareModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var sentSuccessfully = false

    var body: some View {
        NavigationStack {
            List {
                Section { recordingHeader }
                    .listRowBackground(Color.clear)

                if let notice = model.notice, notice.kind == .error {
                    Section {
                        Label(notice.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Couldn’t send recommendation. \(notice.message)")
                    }
                }

                followersSection
                noteSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "Recommend" : "Recommend Personally")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search followers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.dismissNotice()
                        dismiss()
                    }
                        .disabled(model.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await model.recommendPersonally() {
                                sentSuccessfully = true
                                dismiss()
                            }
                        }
                    } label: {
                        if model.isSubmitting {
                            ProgressView()
                                .accessibilityLabel("Sending recommendation")
                        } else {
                            Text(model.selectedCount > 0
                                ? String(localized: "Send (\(model.selectedCount))")
                                : String(localized: "Send"))
                        }
                    }
                    .disabled(!model.canSendPersonally)
                }
            }
            .task { await model.loadFollowers() }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isSubmitting)
        .onDisappear {
            if !sentSuccessfully { model.dismissNotice() }
        }
    }

    private var recordingHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    ArtworkView(url: model.recording.artworkURL, title: model.recording.title, cornerRadius: 13)
                        .frame(width: 76, height: 76)
                    recordingText
                }
            } else {
                HStack(spacing: 14) {
                    ArtworkView(url: model.recording.artworkURL, title: model.recording.title, cornerRadius: 13)
                        .frame(width: 66, height: 66)
                    recordingText
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var recordingText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.recording.title)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            Text(model.recording.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var followersSection: some View {
        Section {
            switch model.followersPhase {
            case .idle, .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading followers…")
                        .foregroundStyle(.secondary)
                }
            case let .failed(message):
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { Task { await model.refreshFollowers() } }
                }
                .padding(.vertical, 4)
            case .ready:
                if filteredFollowers.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No followers yet" : "No matching followers",
                        systemImage: query.isEmpty ? "person.2.slash" : "magnifyingglass",
                        description: Text(query.isEmpty
                            ? "Personal recommendations can be sent only to people who follow you."
                            : "Try a different username.")
                    )
                } else {
                    ForEach(filteredFollowers) { user in
                        followerRow(user)
                    }
                }
            }
        } header: {
            HStack {
                Text("Followers")
                Spacer()
                if model.selectedCount > 0 {
                    Text(model.selectedCount == 1
                        ? String(localized: "1 selected")
                        : String(localized: "\(model.selectedCount) selected"))
                        .textCase(nil)
                }
            }
        } footer: {
            Text("ListenBrainz permits personal recommendations only to listeners who follow you.")
        }
    }

    private var noteSection: some View {
        Section("Optional note") {
            ZStack(alignment: .topLeading) {
                if model.blurb.isEmpty {
                    Text("Why should they hear this?")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.blurb)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Recommendation note")
            }
            Text(String(localized: "\(model.blurb.count) / 280"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(model.blurb.count > 280 ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(String(localized: "\(model.blurb.count) of 280 characters"))
        }
    }

    private func followerRow(_ user: SearchUser) -> some View {
        let isSelected = model.isSelected(user)
        return Button {
            model.toggle(user)
        } label: {
            HStack(spacing: 13) {
                UserAvatar(username: user.username)
                Text(user.username)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(user.username)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double-tap to remove" : "Double-tap to select")
    }

    private var filteredFollowers: [SearchUser] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.followers }
        return model.followers.filter { $0.username.localizedCaseInsensitiveContains(query) }
    }
}
