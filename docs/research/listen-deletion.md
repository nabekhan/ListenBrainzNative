# Listen deletion

Snapshot: 2026-09-18.

## Current behavior

- ListenBrainz accepts an authenticated `POST /1/delete-listen` containing the listen's whole-second `listened_at` timestamp and `recording_msid` UUID.
- A successful response schedules work; the server documentation says deletion usually happens shortly after the next hour. Listen counts become consistent after deletion, while derived statistics can take longer.
- The current website and official Android/KMP client expose this operation. The inspected official iOS client does not.
- ListenBrainzKit already implements the exact request, so the app reuses it rather than adding another HTTP client. A focused package test fixes the path, method, authorization, body, timestamp truncation, and accepted status contract.

## Native decision

History exposes a destructive context action only for authenticated, submitted, non-Playing-Now rows with an MSID. The confirmation names the recording and explains the asynchronous consequence. Immediately before the mutation, the token is validated and its canonical username must match the history owner.

| Outcome | Visible history | Durable state | Replay policy |
|---|---|---|---|
| Definite pre-acceptance rejection or cancellation before transport | Keep listen | Clear a new provisional record | A later ordinary attempt is allowed |
| Accepted response | Hide every matching timestamp/MSID occurrence and rewrite cached history | Confirmed | Never resend |
| Transport started but response is missing, cancelled, malformed, or otherwise uncertain | Keep listen | Indeterminate | Never resend automatically; only an explicitly warned action can try again |

The production replay journal contains normalized username, timestamp, MSID, attempt date, and state—never the token. Before transport begins, a same-directory temporary file is synchronized, atomically renamed into Application Support, and its parent directory is synchronized. The shared journal also owns a transient reservation so two scenes cannot issue the same POST concurrently. Confirmed rows are filtered from restored caches before any network refresh; indeterminate rows remain visible.

An unreadable journal fails closed. The app offers a separate destructive reset warning rather than silently discarding replay barriers. Reset never sends the pending deletion.

## Reuse and provenance

- API semantics and eventual-consistency timing: current ListenBrainz docs/server.
- Product behavior: current website and official Android/KMP client.
- Transport: existing MPL-2.0 ListenBrainzKit `deleteListen` request.
- Presentation and safety state: independently written native SwiftUI/app code. No GPL source was copied.

No authenticated production deletion was exercised. Tests use injected local providers and transports.

## Verification

- ListenBrainzKit: 121 tests in 20 suites passed, including the exact deletion request contract.
- Native app: 266 tests passed with no failures; focused coverage includes persistence, relaunch, offline cache repair, cross-model races, corrupt storage, account separation, cancellation boundaries, and explicit retry behavior.
- The universal arm64/x86_64 Release simulator build succeeded.
- Independent correctness and security re-reviews returned ready. Fixture-only simulator checks covered light, dark, a smaller device, long titles, the largest accessibility text size, and the recovery warning.
