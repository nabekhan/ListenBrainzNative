import SwiftUI

struct LogListenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ListenSubmissionModel
    @State private var isResetConfirmationPresented = false

    init(account: Account, recording: Recording? = nil, mode: ListenSubmissionMode = .listen,
         provider: (any ListenSubmitting)? = nil, journal: ListenSubmissionJournal = .shared,
         initialFixturePhase: ListenSubmissionPhase? = nil,
         initialFixtureRequiresSafetyRecovery: Bool = false) {
        let value = ListenSubmissionModel(account: account, recording: recording, mode: mode, provider: provider, journal: journal)
        #if DEBUG
        if let initialFixturePhase { value.installFixturePhase(initialFixturePhase) }
        if initialFixtureRequiresSafetyRecovery { value.installFixtureSafetyRecovery() }
        #endif
        _model = State(initialValue: value)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("What are you sharing?", selection: $model.draft.mode) {
                        Text("Listen").tag(ListenSubmissionMode.listen)
                        Text("Playing now").tag(ListenSubmissionMode.playingNow)
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isFormLocked)
                } footer: {
                    if model.draft.mode == .playingNow {
                        Text("Playing Now is temporary. It won’t add a listen to History.")
                    }
                }
                Section {
                    TextField("Track title", text: $model.draft.track, axis: .vertical)
                        .textInputAutocapitalization(.words).lineLimit(1...3).disabled(model.isFormLocked)
                    TextField("Artist", text: $model.draft.artist, axis: .vertical)
                        .textInputAutocapitalization(.words).lineLimit(1...3).disabled(model.isFormLocked)
                    TextField("Release (optional)", text: $model.draft.release, axis: .vertical)
                        .textInputAutocapitalization(.words).lineLimit(1...3).disabled(model.isFormLocked)
                } header: { Text("Track details") } footer: {
                    Text("Names are sent directly to ListenBrainz. ListenBrainz doesn’t search for or change them.")
                }
                if model.draft.mode == .listen {
                    Section {
                        DatePicker(
                            "Playback started",
                            selection: $model.draft.playbackStartedAt,
                            in: ListenSubmissionDraft.minimumDate...Date.now,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .disabled(model.isFormLocked)
                    } footer: { Text("Use the time playback started.") }
                }
                statusSection
            }
            .navigationTitle("Log a listen")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.draft.mode) { _, _ in model.modeDidChange() }
            .onChange(of: model.draft.track) { _, _ in model.textDidChange() }
            .onChange(of: model.draft.artist) { _, _ in model.textDidChange() }
            .onChange(of: model.draft.release) { _, _ in model.textDidChange() }
            .interactiveDismissDisabled(model.isSubmitting)
            .alert("Reset safety record?", isPresented: $isResetConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { model.resetSafetyRecord() }
            } message: {
                Text("An earlier listen may already have been sent. Check History first. Resetting could let you send it twice.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.phase == .sent ? "Done" : "Cancel") { dismiss() }
                        .disabled(model.isSubmitting)
                }
                if model.phase != .sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await model.send() } } label: {
                            if model.isSubmitting { ProgressView() }
                            else { Text(model.draft.mode == .listen ? "Send listen" : "Update") }
                        }
                        .disabled(!model.canSend)
                        .accessibilityLabel(model.draft.mode == .listen ? "Send listen to ListenBrainz" : "Share Playing Now with ListenBrainz")
                    }
                }
            }
        }
    }

    @ViewBuilder private var statusSection: some View {
        if model.requiresSafetyRecovery {
            Section {
                Label("Manual listens are paused", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Brainz couldn’t verify whether an earlier listen was sent. Reset only after checking History.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset safety record", role: .destructive) { isResetConfirmationPresented = true }
            }
        } else {
            switch model.phase {
            case .editing, .submitting: EmptyView()
            case .sent:
                Section {
                    Label(model.draft.mode == .listen ? "Listen sent" : "Playing Now updated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(model.draft.mode == .listen ? "It may take a moment to appear in History." : "Playing Now is temporary and doesn’t add a listen to History.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            case let .failed(message):
                Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            case .indeterminate:
                Section {
                    Label("We couldn’t confirm this request.", systemImage: "questionmark.circle")
                    Text("It may have reached ListenBrainz. Check History or your profile before sending it again.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.draft.mode == .listen {
                        Button("Send this listen again") { Task { await model.send(retryIndeterminate: true) } }
                            .disabled(model.isSubmitting)
                    }
                }
            }
        }
    }
}

#if DEBUG
struct LogListenVisualQAScreen: View {
    let mode: ListenSubmissionMode
    private var arguments: [String] { ProcessInfo.processInfo.arguments }
    private var fixturePhase: ListenSubmissionPhase? {
        if arguments.contains("-brainz-log-listen-success-demo") { return .sent }
        if arguments.contains("-brainz-log-listen-indeterminate-demo") { return .indeterminate }
        if arguments.contains("-brainz-log-listen-error-demo") { return .failed("ListenBrainz couldn’t accept this listen. Check the details and try again.") }
        return nil
    }
    private var previewRecording: Recording? {
        arguments.contains("-brainz-log-listen-demo") ? nil : Self.preview
    }
    var body: some View {
        LogListenSheet(
            account: .init(username: "visual-listener", token: "visual-token"),
            recording: previewRecording,
            mode: mode,
            provider: PreviewSubmissionProvider(),
            journal: .init(),
            initialFixturePhase: fixturePhase,
            initialFixtureRequiresSafetyRecovery: arguments.contains("-brainz-log-listen-recovery-demo")
        )
    }
    static let preview = Recording(identity: .init(mbid: UUID(), msid: nil), title: "A Very Long Song Title for a Small Screen", artistName: "The Example Artists", artistMBIDs: [UUID()], releaseTitle: "A Beautiful Album", releaseMBID: UUID(), releaseGroupMBID: UUID(), artworkReleaseMBID: nil, durationMilliseconds: 234_000, source: nil)
}
private struct PreviewSubmissionProvider: ListenSubmitting { func submit(_ payload: ListenSubmissionPayload) async throws {} }
#endif
