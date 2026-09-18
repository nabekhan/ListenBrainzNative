import SwiftUI

private struct MediaDestinations: ViewModifier {
    @Bindable var model: ListeningModel

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Recording.self) { recording in
                RecordingDetailView(recording: recording, model: model)
            }
            .navigationDestination(for: RankedArtist.self) { artist in
                ArtistDetailView(artist: artist, model: model)
            }
            .navigationDestination(for: ReleaseSeed.self) { release in
                ReleaseDetailView(release: release)
            }
            .navigationDestination(for: SearchReleaseGroup.self) { group in
                ReleaseGroupDetailView(group: group, token: model.account.token)
            }
    }
}
extension View {
    func mediaDestinations(model: ListeningModel) -> some View {
        modifier(MediaDestinations(model: model))
    }
}
