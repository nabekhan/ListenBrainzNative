# Native account-data export

Snapshot: ListenBrainz server `v-2026-09-24.0` (`71f92e1`).

## Contract

- `GET /1/export/list` returns the authenticated user's export jobs.
- `POST /1/export/` creates one full or inclusive timestamp-range export. Only one job may be waiting or in progress.
- `GET /1/export/{id}` returns one status; `GET /1/export/{id}/download` returns a completed ZIP; `POST /1/export/{id}/delete` explicitly removes the server copy.
- Status is one of waiting, in progress, completed, or failed. Brainz never parses the human-readable progress string.
- The ZIP contains monthly JSONL listens plus profile, feedback, and pin data. It is a live snapshot, not a transactional backup.

## Native decision

- Settings opens a dedicated authenticated screen. Opening it performs one list read; only an explicit refresh makes another. There is no polling or row hydration.
- Creation is one serialized, no-retry POST after a recent list. A token-free durable reservation prevents replay after timeout, cancellation, or relaunch until an explicit list reconciles server state.
- A completed archive streams directly into a 4 GiB-bounded generated path. Transport validates status, MIME, declared and received size, and ZIP signature. App storage verifies size and SHA-256, uses complete file protection, excludes backups, and makes the local copy eligible for removal after 24 hours. Removal occurs during the next successful launch or export-storage maintenance, on disconnect, or sooner if iOS clears temporary data.
- Account transitions invalidate old provider leases, close operation admission, cancel and drain active work, remove archive/share files, then remove or replace the credential.
- Sharing requires a deliberate system-share action after a visible private-data warning. Removing the downloaded copy never implies that the ListenBrainz copy was deleted.

## Deliberate omissions

- No archive extraction, indexing, automatic history import, resume/range download, background polling, automatic retry, or automatic server deletion.
- Server deletion is typed but not exposed in this first surface; the local and server actions need clearly separate destructive UX.
- Physical-device locked-file and share-extension handoff checks remain a release validation step.

## Sources

- `listenbrainz/webserver/views/export_api.py`
- `listenbrainz/db/user_data_export.py`
- `docs/users/api/export.rst`
