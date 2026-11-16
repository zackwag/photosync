# PhotoSync design

How PhotoSync keeps an iCloud Photo Album and a Skylight frame's photos in sync — one-way, album to frame.

## Goals

- Watch one iCloud Photo Album and push its photos to one Skylight frame. A photo added to the album appears on the frame. A photo removed from the album is deleted from the frame.
- The album is the single source of truth. The same album can also feed an Apple HomeView natively, so the user manages one collection for multiple displays.
- Run as a launchd daemon, like remindersync, with the same signing, notarization and Homebrew cask distribution.

## Non-goals

- Two-way sync. Photos added directly on the Skylight (via the Skylight app or email) are not pulled back into the album.
- Syncing multiple albums to multiple frames in one config. One album, one frame. A second pair is a second config entry and a future enhancement.
- Video sync. The Skylight API accepts video, but the upload and display behavior is unverified. Photos only for now.
- Captions, albums on the Skylight side, slideshow settings, or likes. Just the photos.

## Facts this is built on

From the Skylight Android APK (v2.32.0, decompiled with jadx), confirmed against a live account (spike, 2026-11-16):

| Fact | Consequence |
| --- | --- |
| Skylight calls photos "messages". `GET /api/frames/{id}/messages/all_ids` returns JSON:API `{"data": [{"id": "...", "type": "id"}, ...]}` — just IDs, no per-message metadata. | We can diff what's on the frame against what we've uploaded. State must store the mapping; `all_ids` alone can't correlate back to an asset. |
| `GET /api/frames/{id}/messages/{msgId}` returns `type: "message_detail"` with `asset_bucket`, `asset_key`, `asset_url` (CloudFront signed), `asset_type`, `caption`, `sender_name`, `from_email`, `created_at`, `download_token`. | Useful for debugging but not needed in the sync loop. |
| `POST /api/upload_urls?request_source=android_share` with `{"ext":"jpg","frame_ids":["id"]}` returns `{"data":[{"url":"<presigned S3 URL>","key":"<s3key>","get_url":"<presigned read URL>"}]}`. The presigned URL embeds the pre-allocated message ID in `x-amz-meta-recipient_message_ids=<id>`. | Upload is two HTTP calls. The message ID is known before the PUT, so state can be written optimistically. |
| `PUT <presigned URL>` with raw image bytes (Content-Type `image/jpeg`) uploads to `po-box-production` S3. The backend asynchronously moves it to `darkroom-production` with a CloudFront URL. The message appears in `all_ids` within ~5 seconds. | No registration call needed — the S3 PUT alone triggers backend processing. |
| Images must be large enough for backend processing. A 78-byte or 223-byte PNG never appears; a 15 KB 640x480 JPEG appears within 5 seconds. | Upload original photo bytes, not thumbnails. Minimum viable size is unclear but real photos (hundreds of KB to several MB) will be fine. |
| `DELETE /api/frames/{id}/messages/destroy_multiple` with JSON body `{"message_ids":["id1","id2"]}` returns the deleted IDs as a JSON array `["id1","id2"]`. | Deletion sync works. Batch deletes are supported. |
| The native Android upload path does no image resizing or compression. Files go up as-is. | We upload the original asset bytes. The frame or Skylight's backend handles display sizing. |
| Max per upload batch: 50 images. | Uploads are sequential (one presigned URL per call). The 50-image limit is on the Android share sheet, not the API. |
| Skylight OAuth is PKCE authorization code flow against `app.ourskylight.com/oauth/authorize` with `client_id=skylight-mobile`, `scope=everything`, redirect to `https://ourskylight.com/welcome`. The user copies the `?code=` from the browser. Refresh via `POST /oauth/token`. | Reimplemented in Swift with URLSession. Same flow as the Go client. |
| Skylight rejects requests without a browser-like User-Agent and requires `Skylight-Api-Version: 2026-05-01` and `Authorization: Bearer` headers. | The Swift client mirrors the Go client's headers. |
| PhotoKit's `PHPhotoLibrary.shared().register(_:)` delivers change notifications when the album's contents change (adds, removes, edits). | The daemon reacts to changes instead of polling. A poll interval is the fallback. |
| Photos access (TCC) is checked against the binary's code signature, same as Reminders access in remindersync. A Developer ID signature makes the grant stable across builds. | Same app bundle, signing, and install pattern as remindersync. |
| `PHAsset.localIdentifier` is stable across app launches and iCloud sync. | Used as the key in state to track which assets have been uploaded. |
| `PHImageManager.requestImageDataAndOrientation` returns the full-resolution image data and UTType. | Used to get the bytes for upload. HEIC assets are uploaded as-is (the Skylight app maps heif→heic, so the frame accepts it). |

## Architecture

```text
iCloud Photo Album ──PhotoKit──▶ PhotoSync daemon ──Skylight API──▶ Skylight frame
                                       │
                                   state.db
                              (asset ID → message ID)
```

One-way push. The daemon reads the album, diffs against its state, uploads new photos, deletes removed ones, and updates state. PhotoKit change notifications trigger a sync; a configurable poll interval is the fallback.

### Packages (Swift)

- **PhotoSyncCLI**: the executable target (Swift Package Manager, `Package.swift`). One file per command group (`sync`, `login`, `config`, `install`, `status`), plus the entry point. Uses `swift-argument-parser` for the CLI.
- **SkylightClient**: the Skylight API client. OAuth PKCE login, token refresh, upload (presigned URL flow), list messages, delete messages, list frames. Mirrors the Go `skylight/` package's auth and request patterns. Pure `URLSession`, no dependencies.
- **PhotoReader**: reads a Photo Album's assets via PhotoKit. Lists assets, fetches image data, observes changes.
- **SyncEngine**: the diff logic. Given the album's asset IDs and the state's mappings, produces a plan: uploads and deletes. No PhotoKit or Skylight dependency — takes arrays and returns actions, testable in isolation.
- **State**: SQLite state store via the raw SQLite3 C API (ships with macOS, no dependency). Maps `(asset_local_identifier)` → `(skylight_message_id, uploaded_at)`. One table, simple keyed lookups — GRDB would be overkill.
- **Config**: reads and writes `config.json` via `Codable`/`JSONDecoder` (built-in, no TOML dependency).

### State

SQLite in `~/Library/Application Support/PhotoSync/state.db`:

```sql
CREATE TABLE photo (
    asset_id    TEXT PRIMARY KEY,  -- PHAsset.localIdentifier
    message_id  TEXT NOT NULL,     -- Skylight message ID (from presigned URL metadata)
    pending     INTEGER NOT NULL DEFAULT 0,  -- 1 = upload_urls called, PUT not confirmed
    uploaded_at TEXT NOT NULL      -- ISO 8601
);
```

One row per synced photo. `pending` is set to 1 between getting the presigned URL and confirming the PUT, so a crash mid-upload can be detected and retried without duplicates. No pair concept needed (one album, one frame). If multi-pair is added later, a `pair_id` column extends it.

### Configuration

`~/Library/Application Support/PhotoSync/config.json`:

```json
{
  "album_id": "AF2E8C3B-1234-5678-9ABC-DEF012345678/L0/040",
  "album_title": "Skylight",
  "frame_id": "5760005",
  "frame_name": "Living Room",
  "poll_interval": 300
}
```

JSON rather than TOML: Swift has built-in `Codable`/`JSONDecoder`, so no third-party parser dependency. `album_title` and `frame_name` are display-only (for error messages and `status` output).

`photosync config` walks through:

1. List Photo Albums via PhotoKit, let the user pick one.
2. If not logged in to Skylight, run the OAuth login inline (open browser, paste code).
3. List frames via `GET /api/frames`, let the user pick one.
4. Save.

Credentials (Skylight access + refresh token, device fingerprint) go in the Keychain under service `photosync`.

## Sync algorithm

For each run:

1. **Read the album.** Fetch all `PHAsset` objects in the configured album. If the album doesn't exist (deleted or ID changed), stop with an error.
2. **Read state.** Load all `(asset_id, message_id)` pairs from SQLite.
3. **Diff.**
   - **New**: asset in album, not in state → upload.
   - **Removed**: asset in state, not in album → delete from Skylight.
   - **Present in both**: no action.
4. **Upload new photos.** For each new asset:
   - Fetch image data via `PHImageManager.requestImageDataAndOrientation`.
   - Determine extension from the UTType (jpg, heic, png).
   - `POST /api/upload_urls` with `{"ext":"<ext>","frame_ids":["<frameId>"]}`.
   - Parse the message ID from the presigned URL's `x-amz-meta-recipient_message_ids` query parameter.
   - `PUT` the raw bytes to the presigned URL with `Content-Type: image/<ext>`.
   - Insert `(asset_id, message_id)` into state. The message ID is known before the PUT, so state can be written between the two calls for crash safety (see below).
5. **Delete removed photos.** Collect all `message_id` values for removed assets. `DELETE /api/frames/{id}/messages/destroy_multiple` with `{"message_ids":["id1","id2",...]}`. Delete the state rows.
6. **Wait** for the next PhotoKit change notification or poll interval.

### Crash recovery

The message ID is embedded in the presigned URL (from `upload_urls`), so it's known before the PUT. The upload sequence for each photo:

1. `POST upload_urls` → parse message ID from presigned URL.
2. Insert `(asset_id, message_id)` into state with a `pending` flag.
3. `PUT` bytes to presigned URL.
4. Clear the `pending` flag.

If the process dies:

- After step 2, before step 3: the state row exists with `pending`. On restart, the message doesn't exist on Skylight (the PUT never happened). The next sync sees the pending row, retries the upload with a new presigned URL (the old one expired), and updates the message ID. Or: delete the pending row and let the normal flow re-upload it. Either way, no duplicate.
- After step 3, before step 4: the photo is on Skylight and the state row has the right message ID. The next sync clears `pending` and moves on. No duplicate.
- Deletes that didn't commit will be retried. Deleting an already-deleted message returns the empty array `[]`, which is fine.

### Safety limits

- **Dry run.** `photosync sync --dry-run` prints the plan and writes nothing.
- **Mass delete limit.** If a sync would delete more than `max(5, 25%)` of the synced photos, skip and report. `sync --force` overrides. Protects against an album that got wiped or an iCloud sync hiccup that temporarily empties it.
- **All-or-nothing reads.** A PhotoKit error aborts the sync. An empty album that previously had photos is suspicious and logged as a warning (but allowed, since someone might intentionally clear it).

## Running it

`photosync daemon` syncs at start, then on:

- **PhotoKit change notifications**, debounced by 2 seconds (same as remindersync's EventKit debounce).
- **Poll fallback**, every 5 minutes by default. PhotoKit notifications should catch everything, but iCloud sync delays or edge cases might miss a change.

The daemon is a launchd user agent, same pattern as remindersync:

- `~/Library/LaunchAgents/dev.zackwag.photosync.plist`
- `KeepAlive` for restart on crash, no restart on clean exit
- Aqua session only (TCC prompt needs a GUI session)
- Logs to `~/Library/Logs/PhotoSync/daemon.log`, same rotation (5 MB, one backup)
- `photosync install` loads the agent, waits for the Photos permission prompt
- `photosync uninstall` removes it

The main thread runs a `CFRunLoop` (needed for PhotoKit change notifications, same reason remindersync needs it for EventKit).

### Alerts

Same strategy as remindersync: native macOS notifications via UserNotifications framework from the app bundle.

- After 10 minutes of consecutive failures.
- Immediately on auth failure (expired Skylight login) or Photos access denied.
- Once per failure streak.
- When it recovers after alerting.

### Distribution

Same pipeline as remindersync:

- `PhotoSync.app` bundle, Developer ID signed, notarized.
- Homebrew cask in `zackwag/homebrew-tap`.
- release-please for versioning and changelog.
- GitHub Actions: build arm64 binary, sign, notarize, upload to release, update cask.

## Build order

The API spike is done (2026-11-16). All three endpoints are confirmed working.

1. **SkylightClient.** OAuth PKCE login, token refresh, upload (presigned URL flow), list message IDs, delete messages, list frames. Unit-testable with a mock HTTP server.
2. **SyncEngine.** Pure diff logic, tested against in-memory data. No framework dependencies.
3. **PhotoReader.** PhotoKit wrapper: list albums, list assets in an album, fetch image data, observe changes.
4. **State.** SQLite store.
5. **Config + CLI.** Interactive config wizard, `sync`, `status`, `login` commands.
6. **Daemon + install.** launchd agent, log rotation, alerts.
7. **Distribution.** Build script, signing, notarization, cask, CI.

## Dismissed alternatives

| Alternative | Why not |
| --- | --- |
| Go with cgo PhotoKit bindings | No existing Go library for PhotoKit. Writing cgo wrappers for PHAsset, PHFetchResult, PHImageManager, PHPhotoLibraryChangeObserver is hundreds of lines of boilerplate for something Swift gives natively. |
| Python with pyicloud | Uses iCloud web APIs, which risk the `-20209` account lock (same reason remindersync dismissed it). PhotoKit is the supported path. |
| Shared Go skylight/ package | Different language (Swift), different repo. The Skylight API surface for photos is small (3 endpoints). Reimplementing in Swift is less work than maintaining a cross-language bridge. |
| Two-way sync | The album is the single source of truth, also feeding an Apple HomeView. Pulling Skylight photos into the album would pollute it with photos from other family members using the Skylight app directly. |
| Image resizing before upload | The native Skylight Android app uploads originals. The frame or backend handles display sizing. Adding resizing is complexity for no clear benefit, and risks quality loss. |
| Core Data for state | SQLite is simpler for this shape (one table, keyed lookups, per-row transactions). Core Data's object graph and migration tooling are overkill. |
| JSON file for state | Same reasoning as remindersync: SQLite gives per-item transactions and safe concurrent reads for `status`. |
| Polling only (no PhotoKit change observation) | Wastes battery/CPU checking every N seconds when nothing changed. PhotoKit notifications are push-based and free. Poll is the fallback, not the primary. |
| Putting this in the remindersync repo | Different language, different Apple framework dependency (Photos vs EventKit), different distribution concern. A monorepo would complicate CI (Swift + Go builds) and blur the scope. |
| GRDB or SQLite.swift for the state store | One table with two interesting columns. The raw SQLite3 C API ships with macOS and needs no dependency. GRDB is nice but adds a dependency for something this simple. |
| TOML for config | Swift has no built-in TOML parser. JSON with `Codable` is zero-dependency and built into Foundation. |
| Xcode project instead of SPM | SPM with `Package.swift` is lighter for a CLI. The build script handles the app bundle, signing and notarization outside of Xcode, same as remindersync. |
