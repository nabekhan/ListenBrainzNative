import SwiftUI

struct PlaylistExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: PlaylistDetail
    private let exportError: PlaylistExportError?

    init(detail: PlaylistDetail) {
        self.detail = detail
        do {
            try PlaylistJSPFEncoder.validate(detail)
            exportError = nil
        } catch let error as PlaylistExportError {
            exportError = error
        } catch {
            exportError = .tooLarge
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 84, height: 84)
                        .background(AppTheme.accent.opacity(0.12), in: .circle)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Playlist file")
                            .font(.title2.bold())
                        Text("Includes playlist details, tracks, and contributor names.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if !detail.isPublic {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Private playlist", systemImage: "lock.fill")
                                .font(.headline)
                            Text("Anyone you share the file with can read its contents.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
                    }

                    if let exportError {
                        Label(exportError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
                    } else {
                        ShareLink(
                            item: PlaylistJSPFShareItem(detail: detail),
                            preview: SharePreview(
                                detail.title,
                                image: Image(systemName: "music.note.list")
                            )
                        ) {
                            Label("Share playlist file", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    Text("The file is created on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Export playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
struct PlaylistExportVisualQAScreen: View {
    var body: some View {
        PlaylistExportSheet(detail: Self.detail)
    }

    private static let detail = PlaylistDetail(
        mbid: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        title: "Soft Focus — late-night favorites",
        creator: "visual-listener",
        annotation: "Dream pop, ambient edges, and songs that make the room feel quieter.",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastModifiedAt: Date(timeIntervalSince1970: 1_789_689_600),
        isPublic: false,
        createdFor: nil,
        collaborators: ["cassetteclub", "softstatic"],
        copiedFrom: nil,
        tracks: [
            track(1, "Myth", "Beach House", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
            track(2, "Cherry-coloured Funk", "Cocteau Twins", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
            track(3, "Myth", "Beach House", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
        ]
    )

    private static func track(
        _ position: Int,
        _ title: String,
        _ artist: String,
        _ mbid: String
    ) -> PlaylistTrack {
        PlaylistTrack(
            position: position,
            recording: Recording(
                identity: .init(mbid: UUID(uuidString: mbid), msid: nil),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            addedAt: nil,
            addedBy: "visual-listener"
        )
    }
}
#endif
