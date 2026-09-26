import SwiftUI

struct CurrentPinSection: View {
    @Environment(PinsModel.self) private var pins
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isOwner: Bool
    let subtitle: LocalizedStringResource

    init(isOwner: Bool, subtitle: LocalizedStringResource? = nil) {
        self.isOwner = isOwner
        self.subtitle = subtitle ?? (isOwner
            ? "A note you want visitors to hear"
            : "A track this listener wants to share")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    historyLink
                }
            } else {
                HStack(alignment: .top) {
                    header
                    Spacer(minLength: 12)
                    historyLink
                }
            }
            switch pins.phase {
            case .idle where pins.currentPin == nil, .loading where pins.currentPin == nil:
                ProgressView().frame(maxWidth: .infinity, minHeight: 96)
            case .failed where pins.currentPin == nil:
                ContentUnavailableView {
                    Label("Pins unavailable", systemImage: "pin.slash")
                } description: {
                    Text("We couldn’t load this pinned track. Try again in a moment.")
                } actions: {
                    Button("Try again") { Task { await pins.refreshCurrent() } }
                }
                    .frame(maxWidth: .infinity, minHeight: 120)
            default:
                if let pin = pins.currentPin {
                    PinCard(pin: pin, isOwner: isOwner)
                } else {
                    ContentUnavailableView("No pinned track", systemImage: "pin", description: Text(isOwner ? "Pin a track to share it here." : "This listener does not have a current pin."))
                        .frame(maxWidth: .infinity, minHeight: 130)
                        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    private var header: some View {
        SectionHeader(title: "Pinned track", subtitle: subtitle)
    }

    private var historyLink: some View {
        NavigationLink("History") { PinsHistoryView() }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(.rect)
            .accessibilityLabel("View pinned track history")
    }
}

struct PinsHistoryView: View {
    @Environment(PinsModel.self) private var pins
    @State private var editingPin: PinnedRecording?
    @State private var editedBlurb = ""
    @State private var deletingPin: PinnedRecording?

    var body: some View {
        List {
            if let current = pins.currentPin {
                Section("Current") {
                    PinRow(pin: current)
                        .contextMenu {
                            if pins.account.isAuthenticated { ownerActions(current) }
                        }
                }
            }
            Section(pins.currentPin == nil ? "Pin history" : "Earlier pins") {
                let earlier = pins.history.filter { $0.rowID != pins.currentPin?.rowID }
                if earlier.isEmpty {
                    switch pins.historyPhase {
                    case .idle, .loading:
                        HStack { Spacer(); ProgressView("Loading pin history…"); Spacer() }
                            .listRowBackground(Color.clear)
                    case .failed:
                        ContentUnavailableView {
                            Label("Pin history unavailable", systemImage: "wifi.exclamationmark")
                        } actions: {
                            Button("Try again") { Task { await pins.refreshHistory() } }
                        }
                        .listRowBackground(Color.clear)
                    case .ready:
                        ContentUnavailableView("No earlier pins", systemImage: "clock.arrow.circlepath")
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(earlier) { pin in
                    PinRow(pin: pin)
                        .contextMenu {
                            if pins.account.isAuthenticated { ownerActions(pin) }
                        }
                        .onAppear {
                            if pin.rowID == earlier.last?.rowID { Task { await pins.loadMore() } }
                        }
                }
                if pins.isLoadingMore { HStack { Spacer(); ProgressView(); Spacer() } }
            }
        }
        .navigationTitle("Pinned tracks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await pins.load()
            await pins.loadHistory()
        }
        .refreshable { await pins.refresh() }
        .sheet(item: $editingPin) { pin in
            NavigationStack {
                PinBlurbEditor(title: "Edit note", blurb: $editedBlurb) {
                    Task { await pins.updateBlurb(for: pin, to: editedBlurb) }
                }
            }
        }
        .confirmationDialog("Delete this pin permanently?", isPresented: Binding(get: { deletingPin != nil }, set: { if !$0 { deletingPin = nil } }), titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                if let deletingPin { Task { await pins.delete(deletingPin) } }
                deletingPin = nil
            }
        } message: { Text("This removes the pin from your ListenBrainz history and cannot be undone.") }
    }

    @ViewBuilder private func ownerActions(_ pin: PinnedRecording) -> some View {
        Button { editedBlurb = pin.blurb ?? ""; editingPin = pin } label: { Label("Edit note", systemImage: "square.and.pencil") }
            .disabled(!pins.canMutate)
        if pin.isCurrent {
            Button { Task { await pins.unpin() } } label: { Label("Unpin", systemImage: "pin.slash") }
                .disabled(!pins.canMutate)
        }
        Button(role: .destructive) { deletingPin = pin } label: { Label("Delete permanently", systemImage: "trash") }
            .disabled(!pins.canMutate)
    }
}

private struct PinCard: View {
    let pin: PinnedRecording
    let isOwner: Bool
    @Environment(PinsModel.self) private var pins
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            NavigationLink(value: pin.recording) { pinDestination }
            .buttonStyle(.plain)
            if let blurb = pin.blurb, !blurb.isEmpty { Text(blurb).font(.subheadline).foregroundStyle(.secondary) }
            if isOwner {
                Button { Task { await pins.unpin() } } label: { Label("Unpin", systemImage: "pin.slash").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .disabled(!pins.canMutate)
            }
        }
        .padding(15)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var pinDestination: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ArtworkView(url: pin.recording.artworkURL, title: pin.recording.title, cornerRadius: 12)
                    .frame(width: 74, height: 74)
                pinDetails
            }
        } else {
            HStack(alignment: .top, spacing: 13) {
                ArtworkView(url: pin.recording.artworkURL, title: pin.recording.title, cornerRadius: 12)
                    .frame(width: 74, height: 74)
                pinDetails
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var pinDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Pinned now", systemImage: "pin.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.accent)
            Text(pin.recording.title).font(.headline).lineLimit(2)
            Text(pin.recording.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if let until = pin.pinnedUntil {
                Text("Until \(until, format: .dateTime.month(.abbreviated).day())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PinRow: View {
    let pin: PinnedRecording
    var body: some View {
        NavigationLink(value: pin.recording) {
            HStack(spacing: 12) {
                ArtworkView(url: pin.recording.artworkURL, title: pin.recording.title, cornerRadius: 9).frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.recording.title).font(.body.weight(.semibold)).lineLimit(1)
                    Text(pin.recording.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let blurb = pin.blurb, !blurb.isEmpty { Text(blurb).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if pin.isCurrent { Image(systemName: "pin.fill").foregroundStyle(AppTheme.accent) }
                    Text(pin.created, format: .dateTime.year().month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PinBlurbEditor: View {
    let title: LocalizedStringResource
    @Binding var blurb: String
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section { TextEditor(text: $blurb).frame(minHeight: 130) } footer: {
                Text("\(blurb.count)/280")
                    .foregroundStyle(blurb.count > 280 ? .red : .secondary)
            }
        }
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() }.disabled(blurb.count > 280) }
        }
    }
}
