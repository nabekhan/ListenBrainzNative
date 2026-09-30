# Brainz privacy policy

Last updated: September 30, 2026.

Brainz is an independent, open-source iOS client for ListenBrainz. It is not operated by the MetaBrainz Foundation.

## What Brainz stores on your device

- If you sign in, Brainz stores your ListenBrainz user token and canonical username in the iOS Keychain. The item is available only while the device is unlocked and cannot migrate to another device.
- Brainz stores preferences, recently loaded listening data, and small recovery records needed to avoid repeating uncertain changes. Recently viewed public ListenBrainz profiles are usable from the app cache for seven days so they can open while a refresh is underway. Expired files are removed the next time Brainz reads or maintains this cache, and iOS may remove them sooner. This cache does not contain tokens, private playlists, or account-only data.
- Brainz caches public cover art to reduce repeated downloads and show recently viewed artwork offline. Its cleanup threshold is 128 MB; cleanup runs periodically, so the cache may temporarily use more space. The cache contains no token or private account data. iOS may clear it when storage is needed, and deleting Brainz removes it.
- CritiqueBrainz review recovery records contain only opaque fingerprints and timestamps. They do not contain review text, ratings, tokens, or credentials.
- When you request your ListenBrainz data, Brainz can download a private ZIP archive containing listening history, profile data, feedback, and pins. Brainz stores a verified, protected, non-backed-up copy. Copies become eligible for removal after 24 hours and are removed during the next successful launch or export-storage cleanup, when you disconnect, or sooner if iOS clears temporary data. Opening the share sheet creates a separate protected temporary copy with the same cleanup schedule.
- When you export a playlist, Brainz creates a protected temporary JSON file containing its details, tracks, and contributor names. Brainz removes export folders after 24 hours; iOS may remove temporary files sooner.
- Choosing **Disconnect account** cancels data-export work and removes the saved credential, account listening snapshot, downloaded data archives, and export share copies. Small mutation-safety records may remain until an uncertain action is resolved or the app's local data is removed. To remove the Keychain credential and other local app data, disconnect first and then delete the app.

## What leaves your device

Brainz has no intermediary account service. It sends requests directly to the services needed for its features:

- ListenBrainz receives your username and, while you are signed in, your user token with authenticated ListenBrainz requests. Actions such as submitting or deleting listens, feedback, pins, recommendations, social actions, manual mappings, and playlist changes are stored by ListenBrainz.
- ListenBrainz and MusicBrainz receive searches and music identifiers needed to return results and metadata. Brainz deliberately omits your ListenBrainz token from user, playlist, artist, album, and track searches. MetaBrainz access logs may still contain request parameters and network information as described below.
- Opening published reviews may send the canonical entity identifier directly to CritiqueBrainz. Publishing a review sends its text, optional rating, language, and canonical entity identity to ListenBrainz, which uses your linked CritiqueBrainz account to publish it publicly.
- Requesting a data archive asks ListenBrainz to prepare it. Brainz checks its status only when you open or refresh the export screen; it does not poll. ListenBrainz keeps the server copy until its displayed expiry unless you remove it there.
- Choosing **Show linked services** may send one authenticated request to ListenBrainz to check which supported services are connected. Confirming an export sends one authenticated request; ListenBrainz creates a separate public or private copy in the Spotify, Apple Music, or SoundCloud account you linked there. Later changes do not sync automatically.
- Choosing **Load Spotify playlists** may send one authenticated request to ListenBrainz, which uses your linked Spotify account to retrieve playlist summaries. Visible playlist covers may load directly from Spotify's image CDN without your ListenBrainz token and are not saved in Brainz's artwork caches. Confirming an import sends the chosen Spotify playlist identifier to ListenBrainz, which creates a separate ListenBrainz copy. Later changes do not sync automatically.
- The Cover Art Archive, the Internet Archive, Google Fonts, and Spotify's image CDN may receive the requested resource URL and ordinary network information, such as your IP address, when those features are opened.
- Links to music services open only after you choose them. Those services then apply their own privacy policies.
- Files leave Brainz only when you choose a destination in the system share sheet. Anyone you share a playlist or account-data archive with can read its contents. Treat a data archive as private because it may contain your complete listening history and account data.

ListenBrainz makes listening data public and uses it to build recommendations. Other submitted content may be public or restricted according to each feature's visibility controls, so review those settings before submitting text. MetaBrainz records normal web and API access logs—including IP address, user agent, endpoint, and parameters—and says IP addresses are retained for seven days. Read the [ListenBrainz terms](https://listenbrainz.org/terms-of-service/) and [MetaBrainz privacy policy](https://metabrainz.org/privacy) before submitting data.

## Tracking and advertising

Brainz contains no advertising, analytics, crash-reporting, or tracking SDK. It does not use your data for advertising or cross-app tracking.

## Your choices

- Browse a public ListenBrainz profile without providing a token.
- Use **Disconnect account** to remove the saved credential from Brainz.
- Use **Download your data** to create, download, share, or remove Brainz's local copy of a ListenBrainz archive. Removing the local copy does not remove the server copy.
- Manage connected services and account data through [ListenBrainz settings](https://listenbrainz.org/settings/).
- Request account access, export, correction, or deletion under the [MetaBrainz GDPR policy](https://metabrainz.org/gdpr).

For a privacy or security concern in Brainz, use [private vulnerability reporting](https://github.com/nabekhan/ListenBrainzNative/security/advisories/new). For a non-sensitive problem, you may open a public issue. Never include a ListenBrainz token or personal data in a public report.
