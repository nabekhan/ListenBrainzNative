# ListenBrainzKit

ListenBrainzKit is a Swift wrapper around the [ListenBrainz API](https://listenbrainz.readthedocs.io/en/latest/users/api/index.html) originally built for my iOS music app, [Jewelcase](https://apps.apple.com/us/app/jewelcase/id6642683626).

## Requirements
- Swift 6
- iOS 16+
- macOS 13+
- tvOS 16+
- visionOS 1+
- watchOS 9+

## Setup

Add ListenBrainzKit as a dependency in your Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/samglt/ListenBrainzKit.git", from: "0.1.0"),
],
```

Or add it in XCode by selecting `File > Add Package Dependencies...` and entering `https://github.com/samglt/ListenBrainzKit`

## Usage

You can initialize a client with a ListenBrainz token and an optional custom root URL if you're not using the official ListenBrainz endpoint (eg. if you're running your own instance).

```swift
import ListenBrainzKit

let client = LBClient(token: token)
// or:
let client = LBClient(
    token: token,
    customRoot: URL(string: "https://listenbrainz.example.com")!,
    allowsTokenToCustomRoot: true // explicit because this sends the token to that origin
)
```

Submitting listens:

```swift
// Submit a single listen
try await client.core.submitListen(meta: .init(artist: "Kylie Minogue",
                                               track: "Come Into My World",
                                               release: "Fever",
                                               tracknumber: 7),
                                   at: time)

// Submit a batch of past listens
try await client.core.submitListens([
    .init(meta: .init(artist: "Kylie Minogue",
                      track: "Fever"),
          listenedAt: Date.now.addingTimeInterval(-180)),
    .init(meta: .init(artist: "Kylie Minogue",
                      track: "More More More"),
          listenedAt: Date.now.addingTimeInterval(-360))
])
```

## Development

Running integration tests requires setting a ListenBrainz token in the environment variable `LISTENBRAINZ_TOKEN"`

## Supported Endpoints

- Core
  - [x] GET  /1/search/users/
  - [x] POST /1/submit-listens
  - [x] GET  /1/user/(user_name)/listens
  - [x] GET  /1/user/(user_name)/listen-count
  - [x] GET  /1/user/(user_name)/playing-now
  - [x] GET  /1/user/(user_name)/similar-users
  - [x] GET  /1/user/(user_name)/similar-to/(other_user_name)
  - [x] GET  /1/validate-token
  - [x] POST /1/delete-listen
  - [x] GET  /1/user/(playlist_user_name)/playlists
  - [x] GET  /1/user/(playlist_user_name)/playlists/createdfor
  - [x] GET  /1/user/(playlist_user_name)/playlists/collaborator
  - [x] GET  /1/user/(playlist_user_name)/playlists/recommendations
  - [x] GET  /1/user/(playlist_user_name)/playlists/search
  - [x] GET  /1/user/(user_name)/services
  - [x] GET  /1/lb-radio/tags
  - [x] GET  /1/lb-radio/artist/(seed_artist_mbid)
  - [x] GET  /1/latest-import
  - [x] POST /1/latest-import
- Metadata
  - [x] GET  /1/metadata/recording/
  - [x] POST /1/metadata/recording/
  - [x] GET  /1/metadata/release_group/
  - [x] GET  /1/metadata/lookup/
  - [x] POST /1/metadata/lookup/
  - [x] GET  /1/metadata/artist/
  - [x] POST /1/metadata/submit_manual_mapping/
  - [x] GET  /1/metadata/get_manual_mapping/
- Statistics
  - [x] GET  /1/stats/user/(user_name)/artists
  - [x] GET  /1/stats/user/(user_name)/releases
  - [x] GET  /1/stats/user/(user_name)/release-groups
  - [x] GET  /1/stats/user/(user_name)/recordings
  - [x] GET  /1/stats/user/(user_name)/listening-activity
  - [x] GET  /1/stats/user/(user_name)/daily-activity
  - [x] GET  /1/stats/user/(user_name)/artist-map
  - [x] GET  /1/stats/artist/(artist_mbid)/listeners
  - [x] GET  /1/stats/release-group/(release_group_mbid)/listeners
  - [x] GET  /1/stats/sitewide/artists
  - [x] GET  /1/stats/sitewide/releases
  - [x] GET  /1/stats/sitewide/release-groups
  - [x] GET  /1/stats/sitewide/recordings
  - [x] GET  /1/stats/sitewide/listening-activity
  - [x] GET  /1/stats/sitewide/artist-map
  - [x] GET  /1/stats/user/(user_name)/year-in-music/(int: year)
  - [x] GET  /1/stats/user/(user_name)/year-in-music
- Popularity
  - [ ] GET  /1/popularity/top-recordings-for-artist/(artist_mbid)
  - [ ] GET  /1/popularity/top-release-groups-for-artist/(artist_mbid)
  - [x] POST /1/popularity/recording
  - [x] POST /1/popularity/artist
  - [x] POST /1/popularity/release
  - [x] POST /1/popularity/release-group
- Playlists
  - [x] GET  /1/user/(playlist_user_name)/playlists
  - [x] GET  /1/user/(playlist_user_name)/playlists/createdfor
  - [x] GET  /1/user/(playlist_user_name)/playlists/collaborator
  - [x] POST /1/playlist/create
  - [x] GET  /1/playlist/search
  - [x] POST /1/playlist/edit/(playlist_mbid)
  - [x] GET  /1/playlist/(playlist_mbid)
  - [ ] GET  /1/playlist/(playlist_mbid)/xspf
  - [x] POST /1/playlist/(playlist_mbid)/item/add
  - [ ] POST /1/playlist/(playlist_mbid)/item/add/(int: offset)
  - [ ] POST /1/playlist/(playlist_mbid)/item/move
  - [ ] POST /1/playlist/(playlist_mbid)/item/delete
  - [ ] POST /1/playlist/(playlist_mbid)/delete
  - [x] POST /1/playlist/(playlist_mbid)/copy
  - [ ] POST /1/playlist/(playlist_mbid)/export/(service)
  - [ ] GET  /1/playlist/import/(service)
  - [ ] GET  /1/playlist/(service)/(playlist_id)/tracks
  - [ ] POST /1/playlist/export-jspf/(service)
- Recordings
  - [x] POST /1/feedback/recording-feedback
  - [x] GET  /1/feedback/user/(user_name)/get-feedback
  - [x] GET  /1/feedback/recording/(recording_mbid)/get-feedback-mbid
  - [x] GET  /1/feedback/recording/(recording_msid)/get-feedback
  - [x] GET  /1/feedback/user/(user_name)/get-feedback-for-recordings
  - [x] POST /1/feedback/user/(user_name)/get-feedback-for-recordings
  - [ ] POST /1/feedback/import
  - Pinned Recording API
    - [x] POST /1/pin
    - [x] POST /1/pin/unpin
    - [x] POST /1/pin/delete/(row_id)
    - [x] GET  /1/(user_name)/pins
    - [x] GET  /1/(user_name)/pins/following
    - [x] GET  /1/(user_name)/pins/current
    - [x] POST /1/pin/update/(row_id)
- Social
  - [x] POST /1/user/(user_name)/timeline-event/create/recording
  - [ ] POST /1/user/(user_name)/timeline-event/create/notification
  - [ ] POST /1/user/(user_name)/timeline-event/create/review
  - [x] GET  /1/user/(user_name)/feed/events
  - [x] GET  /1/user/(user_name)/feed/events/listens/following
  - [x] GET  /1/user/(user_name)/feed/events/listens/similar
  - [x] POST /1/user/(user_name)/feed/events/delete
  - [x] POST /1/user/(user_name)/feed/events/hide
  - [x] POST /1/user/(user_name)/feed/events/unhide
  - [x] POST /1/user/(user_name)/timeline-event/create/recommend-personal
  - [x] POST /1/user/(user_name)/timeline-event/create/thanks
  - Follow API
    - [x] GET  /1/user/(user_name)/followers
    - [x] GET  /1/user/(user_name)/following
    - [x] POST /1/user/(user_name)/follow
    - [x] POST /1/user/(user_name)/unfollow
- Recommendations
  - [x] GET  /1/cf/recommendation/user/(user_name)/recording
  - Feedback
    - [x] POST /1/recommendation/feedback/submit
    - [x] POST /1/recommendation/feedback/delete
    - [x] GET  /1/recommendation/feedback/user/(user_name)
    - [x] GET  /1/recommendation/feedback/user/(user_name)/recordings
- Art
  - [ ] POST /1/art/grid/
  - [x] GET  /1/art/grid-stats/(user_name)/(time_range)/(int: dimension)/(int: layout)/(int: image_size)
  - [x] GET  /1/art/artist-grid/(artist_mbid)/(int: dimension)/(int: layout)/(int: image_size)
  - [x] POST /1/art/playlist/(playlist_mbid)/(int: dimension)/(int: layout)
  - [ ] GET  /1/art/(custom_name)/(user_name)/(time_range)/(int: image_size)
  - [x] GET  /1/art/year-in-music/(int: year)/(user_name)
- Misc
  - Explore
    - [x] GET  /1/explore/fresh-releases/
    - [ ] GET  /1/explore/color/(color)
    - [x] GET  /1/explore/lb-radio
  - Status
    - [ ] GET  /1/status/get-dump-info
