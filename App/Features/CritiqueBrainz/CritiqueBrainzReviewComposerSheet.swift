import ListenBrainzKit
import SwiftUI

struct CritiqueBrainzReviewComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CritiqueBrainzReviewComposerModel
    @State private var showPublishConfirmation = false
    @State private var showRetryWarning = false
    @State private var showPriorAttemptWarning = false
    @State private var showGlobalRecoveryWarning = false
    @State private var submitTask: Task<Void, Never>?
    private let onPublished: @MainActor () -> Void

    init(
        account: Account,
        entity: CritiqueBrainzEntity,
        entityName: String,
        onPublished: @escaping @MainActor () -> Void = {}
    ) {
        _model = State(
            initialValue: .init(
                account: account,
                entity: entity,
                entityName: entityName
            )
        )
        self.onPublished = onPublished
    }

    init(
        model: CritiqueBrainzReviewComposerModel,
        onPublished: @escaping @MainActor () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.onPublished = onPublished
    }

    var body: some View {
        NavigationStack {
            Form {
                reviewSection
                publishingTermsSection
                statusSection
            }
            .navigationTitle("Write a review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog(
                "Publish this review?",
                isPresented: $showPublishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Publish review") { startSubmission(retryingIndeterminate: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your review will be public under CC BY-SA 3.0. MetaBrainz may also license it commercially outside Creative Commons to support its work.")
            }
            .confirmationDialog(
                "Send this review again?",
                isPresented: $showRetryWarning,
                titleVisibility: .visible
            ) {
                Button("Send again", role: .destructive) {
                    startSubmission(retryingIndeterminate: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("We can’t tell whether the earlier request worked. Sending it again may create a duplicate review.")
            }
            .confirmationDialog(
                "Clear this review’s safety record?",
                isPresented: $showPriorAttemptWarning,
                titleVisibility: .visible
            ) {
                Button("Clear after checking", role: .destructive) {
                    model.clearPriorAttemptAfterChecking()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("First confirm that this item has no review from you. Clearing the record lets you start again and could create a duplicate if the earlier request worked.")
            }
            .confirmationDialog(
                "Reset all review safety records?",
                isPresented: $showGlobalRecoveryWarning,
                titleVisibility: .visible
            ) {
                Button("Reset all records", role: .destructive) {
                    model.resetAllSafetyRecordsAfterChecking()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("First check your recent CritiqueBrainz activity. This clears every pending safety record and could allow duplicate reviews on other items.")
            }
        }
        .interactiveDismissDisabled(model.state == .submitting)
        .onDisappear {
            submitTask?.cancel()
            submitTask = nil
        }
    }

    private var reviewSection: some View {
        Section("Your review") {
            TextEditor(text: $model.text)
                .frame(minHeight: 160)
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Share what stood out…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Review text")
                .disabled(model.isLocked)

            characterCount

            Picker("Rating", selection: $model.rating) {
                Text("No rating").tag(Int?.none)
                ForEach(1 ... 5, id: \.self) { value in
                    Text("\(value) stars").tag(Int?.some(value))
                }
            }
            .disabled(model.isLocked)

            NavigationLink {
                CritiqueBrainzLanguagePicker(selection: $model.language)
            } label: {
                LabeledContent(
                    "Review language",
                    value: Locale.current.localizedString(
                        forLanguageCode: model.language
                    ) ?? model.language
                )
            }
            .disabled(model.isLocked)
        }
    }

    private var publishingTermsSection: some View {
        Section("Publishing terms") {
            Text("By publishing, you confirm that you own or control the necessary rights, the review does not infringe anyone else’s rights, and you have permission to share and license it. You license the review under CC BY-SA 3.0 and also permit the MetaBrainz Foundation to license it for commercial use outside Creative Commons to help fund its operations.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                "I agree to these publishing terms.",
                isOn: $model.acknowledgedLicense
            )
            .disabled(model.isLocked)

            Link(
                "Read the CC BY-SA 3.0 license",
                destination: Self.licenseURL
            )
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.state {
        case let .failed(failure):
            Section("Couldn’t publish review") {
                Text(failure.message)
                    .foregroundStyle(.red)
                if failure.showsConnectionSettings {
                    Link("Open ListenBrainz settings", destination: Self.connectionSettingsURL)
                }
            }
        case .outcomeUnknown:
            Section("Review status") {
                Text("We couldn’t confirm whether your review was published. Check CritiqueBrainz before sending this same review again.")
                Link("Check this item on CritiqueBrainz", destination: model.entity.browseURL)
                Button("Send the same review again", role: .destructive) {
                    showRetryWarning = true
                }
                Link("Manage CritiqueBrainz connection", destination: Self.connectionSettingsURL)
            }
        case .priorAttemptNeedsReview:
            Section("Review needs checking") {
                Text("A previous publishing attempt for this item wasn’t confirmed. Check CritiqueBrainz before starting again.")
                Link("Check this item on CritiqueBrainz", destination: model.entity.browseURL)
                Button("Clear after checking", role: .destructive) {
                    showPriorAttemptWarning = true
                }
            }
        case let .published(reviewID):
            Section {
                Label("Review published", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Link(
                    "View published review",
                    destination: Self.reviewURL(reviewID)
                )
            }
        case .safetyRecovery:
            Section("Publishing paused") {
                Text("Brainz couldn’t safely read its review publishing records. Publishing is paused for every item to prevent duplicates.")
                Link("Open CritiqueBrainz", destination: Self.critiqueBrainzURL)
                Button("Reset all after checking", role: .destructive) {
                    showGlobalRecoveryWarning = true
                }
            }
        case .editing, .submitting:
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .disabled(model.state == .submitting)
        }
        if model.showsPublishAction {
            ToolbarItem(placement: .confirmationAction) {
                Button("Publish") { showPublishConfirmation = true }
                    .disabled(!model.canPublish)
            }
        }
    }

    @ViewBuilder
    private var characterCount: some View {
        let count = model.trimmedText.unicodeScalars.count
        if count < LBCritiqueBrainzReviewLimits.minimumTextScalars {
            Text("\(LBCritiqueBrainzReviewLimits.minimumTextScalars - count) more characters needed")
                .foregroundStyle(.orange)
        } else if count > LBCritiqueBrainzReviewLimits.maximumTextScalars
                    || model.trimmedText.utf8.count
                    > LBCritiqueBrainzReviewLimits.maximumTextUTF8Bytes {
            Text("100,000 characters maximum")
                .foregroundStyle(.orange)
        } else {
            Text("\(count) characters")
                .foregroundStyle(.secondary)
        }
    }

    private func startSubmission(retryingIndeterminate: Bool) {
        guard submitTask == nil || submitTask?.isCancelled == true else { return }
        submitTask = Task {
            await model.publish(retryingIndeterminate: retryingIndeterminate)
            if case .published = model.state {
                await CritiqueBrainzReviewCaches.invalidate(afterPublishing: model.entity)
                onPublished()
            }
            submitTask = nil
        }
    }

    private static let licenseURL = URL(
        string: "https://creativecommons.org/licenses/by-sa/3.0/"
    )!
    private static let connectionSettingsURL = URL(
        string: "https://listenbrainz.org/settings/music-services/details/"
    )!
    private static let critiqueBrainzURL = URL(string: "https://critiquebrainz.org/")!

    private static func reviewURL(_ id: UUID) -> URL {
        URL(string: "https://critiquebrainz.org/review/\(id.uuidString.lowercased())")!
    }
}

private struct CritiqueBrainzLanguagePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var search = ""

    private static let codes = CritiqueBrainzReviewComposerModel.supportedLanguageCodes
        .sorted {
            displayName(for: $0).localizedStandardCompare(displayName(for: $1))
                == .orderedAscending
        }

    private var visibleCodes: [String] {
        guard !search.isEmpty else { return Self.codes }
        return Self.codes.filter { code in
            "\(code) \(Self.displayName(for: code))"
                .localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List(visibleCodes, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                HStack {
                    Text(Self.displayName(for: code))
                    Spacer()
                    if selection == code {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityValue(selection == code ? "Selected" : "Not selected")
        }
        .navigationTitle("Review language")
        .searchable(text: $search, prompt: "Search languages")
    }

    private static func displayName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
