import ListenBrainzKit
import SwiftUI

struct CustomArtworkComposerSheet: View {
    let username: String
    let albums: [CustomArtworkAlbum]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: CustomArtworkDraft
    @State private var generation: Generation?

    private let provider: any GeneratedArtworkProviding

    init(
        username: String,
        albums: [CustomArtworkAlbum],
        provider: any GeneratedArtworkProviding
    ) {
        self.username = username
        self.albums = albums
        self.provider = provider
        _draft = State(
            initialValue: CustomArtworkDraft(
                albumIDs: albums.map(\.releaseMBID)
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if albums.isEmpty {
                    ContentUnavailableView(
                        "No matched albums yet",
                        systemImage: "square.grid.2x2",
                        description: Text(
                            "ListenBrainz needs MusicBrainz matches for your top albums before it can build a collage."
                        )
                    )
                } else {
                    Form {
                        layoutSection
                        styleSection
                        orderSection
                        albumSection
                    }
                }
            }
            .navigationTitle("Album collage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createArtwork() }
                        .disabled(!draft.canGenerate)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $generation) { value in
            GeneratedArtworkSheet(
                presentation: .customAlbumCollage(
                    username: username,
                    albumCount: value.albumCount
                ),
                request: value.request,
                provider: provider
            )
        }
    }

    private var layoutSection: some View {
        Section {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft.layout.title)
                            .font(.headline)
                        Text(draft.layout.coverCountLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: draft.layout.symbolName)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 52, height: 52)
                            .background(AppTheme.accent.opacity(0.12), in: .rect(cornerRadius: 14))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.layout.title)
                                .font(.headline)
                            Text(draft.layout.coverCountLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            NavigationLink {
                CustomArtworkLayoutSelectionView(
                    presets: draft.availableLayouts,
                    selection: layoutBinding
                )
            } label: {
                Label("Change layout", systemImage: "square.grid.3x3")
            }
        } header: {
            Text("Layout")
        }
    }

    private var styleSection: some View {
        Section("Style") {
            Picker("Background", selection: $draft.background) {
                ForEach(CustomArtworkBackground.allCases) { background in
                    Text(background.title).tag(background)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Show album and artist names", isOn: $draft.captions)
        }
    }

    private var orderSection: some View {
        Section {
            NavigationLink {
                CustomArtworkOrderView(
                    albums: albums,
                    draft: $draft
                )
            } label: {
                Label("Arrange covers", systemImage: "arrow.up.arrow.down")
            }
            .disabled(draft.selectedReleaseMBIDs.count < 2)
        } header: {
            Text("Cover order")
        } footer: {
            Text("Covers follow this order. Some layouts feature more than one.")
        }
    }

    private var albumSection: some View {
        Section {
            ForEach(albums) { album in
                albumButton(album)
            }
        } header: {
            HStack {
                Text("Top albums")
                Spacer()
                Text(selectionCountLabel)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        } footer: {
            Text(selectionGuidance)
        }
    }

    private func albumButton(_ album: CustomArtworkAlbum) -> some View {
        let index = draft.selectedReleaseMBIDs.firstIndex(of: album.releaseMBID)
        let isSelected = index != nil
        let selectionIsFull = draft.selectedReleaseMBIDs.count >= draft.layout.requiredCoverCount

        return Button {
            draft.toggle(album.releaseMBID)
        } label: {
            HStack(spacing: 12) {
                CustomArtworkPlaceholder(title: album.title, cornerRadius: 8)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 64 : 48,
                       height: dynamicTypeSize.isAccessibilitySize ? 64 : 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    Text(album.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }

                Spacer(minLength: 8)

                if let index {
                    Text((index + 1).formatted())
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.accent, in: .circle)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isSelected && selectionIsFull)
        .opacity(!isSelected && selectionIsFull ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "\(album.title) by \(album.artistName)")
        )
        .accessibilityValue(
            index.map {
                String(localized: "Selected as cover \(($0 + 1).formatted())")
            } ?? String(localized: "Not selected")
        )
        .accessibilityHint(
            isSelected
                ? String(localized: "Removes this album from the collage")
                : String(localized: "Adds this album to the collage")
        )
    }

    private var layoutBinding: Binding<CustomArtworkLayoutPreset> {
        Binding(
            get: { draft.layout },
            set: { draft.selectLayout($0) }
        )
    }

    private var selectionCountLabel: String {
        String(
            localized: "\(draft.selectedReleaseMBIDs.count.formatted()) of \(draft.layout.requiredCoverCount.formatted())"
        )
    }

    private var selectionGuidance: String {
        switch draft.remainingCoverCount {
        case 0:
            String(localized: "All covers selected. Arrange them before creating your artwork.")
        default:
            String(localized: "Choose \(draft.remainingCoverCount) more albums.")
        }
    }

    private func createArtwork() {
        guard let request = draft.request else { return }
        generation = Generation(
            request: request,
            albumCount: draft.selectedReleaseMBIDs.count
        )
    }

    private struct Generation: Identifiable {
        let id = UUID()
        let request: GeneratedArtworkRequest
        let albumCount: Int
    }
}

private struct CustomArtworkOrderView: View {
    let albums: [CustomArtworkAlbum]
    @Binding var draft: CustomArtworkDraft

    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    private var albumsByID: [UUID: CustomArtworkAlbum] {
        Dictionary(uniqueKeysWithValues: albums.map { ($0.releaseMBID, $0) })
    }

    var body: some View {
        List {
            ForEach(draft.selectedReleaseMBIDs, id: \.self) { id in
                if let album = albumsByID[id] {
                    HStack(spacing: 12) {
                        CustomArtworkPlaceholder(title: album.title, cornerRadius: 7)
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title)
                                .font(.body.weight(.medium))
                            Text(album.artistName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .onMove { offsets, destination in
                draft.moveSelection(fromOffsets: offsets, toOffset: destination)
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Arrange covers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct CustomArtworkLayoutSelectionView: View {
    let presets: [CustomArtworkLayoutPreset]
    @Binding var selection: CustomArtworkLayoutPreset

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(presets) { preset in
            Button {
                selection = preset
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.title)
                            .font(.body.weight(.semibold))
                        Text(preset.coverCountLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if preset == selection {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(preset == selection ? .isSelected : [])
        }
        .navigationTitle("Choose layout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension CustomArtworkLayoutPreset {
    var title: LocalizedStringResource {
        switch self {
        case .single: "Single cover"
        case .grid2: "2 × 2 grid"
        case .spotlightLeft3: "3 × 3 left feature"
        case .spotlightRight3: "3 × 3 right feature"
        case .grid3: "3 × 3 grid"
        case .feature4: "4 × 4 feature"
        case .split4: "4 × 4 split"
        case .centered4: "4 × 4 centered"
        case .grid4: "4 × 4 grid"
        case .feature5: "5 × 5 feature"
        }
    }

    var symbolName: String {
        switch dimension {
        case 1: "square"
        case 2: "square.grid.2x2"
        default: "square.grid.3x3"
        }
    }

    var coverCountLabel: String {
        String(localized: "Uses \(requiredCoverCount) album covers")
    }

}

private struct CustomArtworkPlaceholder: View {
    let title: String
    let cornerRadius: CGFloat

    var body: some View {
        // Keep draft editing request-free. ListenBrainz resolves the real
        // covers only after the user explicitly creates the collage.
        AppTheme.artworkGradient(seed: title)
            .overlay {
                Image(systemName: "square.stack")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

private extension CustomArtworkBackground {
    var title: LocalizedStringResource {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .transparent: "Clear"
        }
    }
}

#if DEBUG
struct CustomArtworkComposerVisualQAScreen: View {
    var body: some View {
        CustomArtworkComposerSheet(
            username: "visual-listener",
            albums: Self.albums,
            provider: VisualQAGeneratedArtworkProvider(fixture: .populated)
        )
    }

    private static let albums: [CustomArtworkAlbum] = [
        album(1, "Midnight Atlas", "Harbour Signals"),
        album(2, "Soft Static", "June Meridian"),
        album(3, "The Long Way Home", "Northern Lines"),
        album(4, "After the Rain", "Mara Vale"),
        album(5, "Paper Satellites", "Quiet Geometry"),
        album(6, "Everything Glows at Dusk", "Solstice Arcade"),
        album(7, "Blue Hours", "Nia Bloom"),
        album(8, "Small Revolutions", "The Side Streets"),
        album(9, "Glass Gardens", "Iris Current"),
        album(10, "Open Water", "Night Ferry"),
        album(11, "Borrowed Light", "Field Notes"),
        album(12, "Far From Ordinary", "Theo North"),
        album(13, "Colour Memory", "Analog Hearts"),
        album(14, "A Map of Echoes", "Kite Assembly"),
        album(15, "Weather Systems", "Lowland Choir"),
        album(16, "Still Moving", "Common Ground"),
    ]

    private static func album(
        _ number: Int,
        _ title: String,
        _ artistName: String
    ) -> CustomArtworkAlbum {
        CustomArtworkAlbum(
            releaseMBID: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    number
                )
            )!,
            title: title,
            artistName: artistName
        )
    }
}
#endif
