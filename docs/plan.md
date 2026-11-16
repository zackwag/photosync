# PhotoSync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Swift CLI/daemon that syncs an iCloud Photo Album to a Skylight frame — one-way push with deletion.

**Architecture:** SPM package with six modules: SkylightClient (OAuth + REST), SyncEngine (pure diff), PhotoReader (PhotoKit), State (SQLite3 C API), Config (JSON + Keychain), and the CLI executable. The daemon runs a CFRunLoop for PhotoKit change notifications with a poll fallback.

**Tech Stack:** Swift 6, SPM, swift-argument-parser, URLSession (async/await), SQLite3 C API, PhotoKit, UserNotifications, launchd

**Spec:** `/tmp/photosync-design/design.md`

## Global Constraints

- macOS 14.0+ deployment target
- Only dependency: `apple/swift-argument-parser` (latest)
- Bundle ID: `dev.zackwag.PhotoSync`
- Launchd label: `dev.zackwag.photosync`
- Keychain service: `photosync`, account: `skylight`
- Config path: `~/Library/Application Support/PhotoSync/config.json`
- State path: `~/Library/Application Support/PhotoSync/state.db`
- Log path: `~/Library/Logs/PhotoSync/daemon.log`
- User-Agent, Skylight-Api-Version, OAuth client_id, redirect URI: match the Go client exactly (see spec facts table)
- No video, no captions, no albums on the Skylight side, no two-way sync

## Review Focus

1. **Presigned URL expiry mid-upload** — if the PUT takes longer than S3's 900s TTL on a large photo over a slow connection, the upload fails silently. The upload should retry with a fresh presigned URL on a 403 from S3.
2. **HEIC content type** — PhotoKit returns UTType `.heic`; the Content-Type header must be `image/heic` and the ext `heic`, not `heif`. Test that UTType-to-extension mapping handles this.
3. **Empty album on first run** — a brand new config with an empty album should sync cleanly (no uploads, no deletes, no mass-delete warning), not error.
4. **Keychain access denied** — `SecItemCopyMatching` returning `errSecAuthFailed` or `errSecInteractionNotAllowed` must surface as a clear "run `photosync login`" message, not a crash.
5. **Concurrent daemon + manual sync** — two processes writing to `state.db` simultaneously. SQLite's WAL mode with `SQLITE_BUSY` retry handles this, but the timeout must be tested.

---

### Task 1: Project scaffold + SkylightClient

**Files:**
- Create: `Package.swift`
- Create: `Sources/SkylightClient/Models.swift`
- Create: `Sources/SkylightClient/OAuth.swift`
- Create: `Sources/SkylightClient/Client.swift`
- Create: `Sources/SkylightClient/Frames.swift`
- Create: `Sources/SkylightClient/Messages.swift`
- Create: `Tests/SkylightClientTests/MockURLProtocol.swift`
- Create: `Tests/SkylightClientTests/OAuthTests.swift`
- Create: `Tests/SkylightClientTests/ClientTests.swift`
- Create: `Tests/SkylightClientTests/MessagesTests.swift`

**Interfaces:**
- Consumes: nothing (first task)
- Produces:
  - `Token(accessToken: String, refreshToken: String)` — Codable struct
  - `Frame(id: String, name: String)` — struct
  - `UploadResult(presignedURL: URL, messageID: String, s3Key: String)` — struct
  - `APIError(method: String, path: String, statusCode: Int, body: String)` — Error
  - `SkylightAuth.PKCE(verifier: String, challenge: String)` — generated with `static func generate() throws -> PKCE`
  - `SkylightAuth.authorizeURL(challenge: String) -> URL`
  - `SkylightAuth.extractCode(from raw: String) throws -> String`
  - `SkylightAuth.exchangeCode(_ code: String, verifier: String, fingerprint: String, session: URLSession) async throws -> Token`
  - `SkylightAuth.refresh(token: String, fingerprint: String, session: URLSession) async throws -> Token`
  - `SkylightClient.init(token: Token, fingerprint: String, session: URLSession, onRefresh: ((Token) -> Void)?)`
  - `SkylightClient.frames() async throws -> [Frame]`
  - `SkylightClient.messageIDs(frameID: String) async throws -> [String]`
  - `SkylightClient.upload(frameID: String, ext: String, imageData: Data) async throws -> UploadResult`
  - `SkylightClient.deleteMessages(frameID: String, ids: [String]) async throws`

- [ ] **Step 1: Create `Package.swift`**

Define all six targets (SkylightClient, SyncEngine, State, Config, PhotoReader, PhotoSyncCLI) and test targets for SkylightClient, SyncEngine, State. Only dependency: `apple/swift-argument-parser`. Set `platforms: [.macOS(.v14)]`. State links SQLite3 (available on macOS). SyncEngine depends on State (for the `PhotoRecord` type — moved there in Task 3 Step 5).

- [ ] **Step 2: Write `Models.swift`**

```swift
// Token, Frame, UploadResult, APIError as described in Interfaces.
// Token is Codable. APIError conforms to Error and LocalizedError.
```

- [ ] **Step 3: Write `OAuth.swift`**

Implement `SkylightAuth` enum with static methods. Constants: `baseURL = "https://app.ourskylight.com"`, `clientID = "skylight-mobile"`, `scope = "everything"`, `redirectURI = "https://ourskylight.com/welcome"`. PKCE uses `CryptoKit.SHA256` for S256 challenge. `extractCode` accepts a bare code, a full redirect URL, or `code=...` prefix — same logic as Go client's `ExtractCode`. Token exchange sends `source: "js-mobile"`, refresh sends `source: "web"`. Both send device params matching the Go client's `addDeviceParams`.

- [ ] **Step 4: Write failing `OAuthTests.swift`**

```swift
func testPKCEGeneratesValidChallenge() {
    let pkce = try SkylightAuth.PKCE.generate()
    XCTAssertEqual(pkce.verifier.count, 86) // 64 bytes base64url
    // challenge is SHA256 of verifier, base64url-encoded
}
func testAuthorizeURLContainsRequiredParams() {
    let url = SkylightAuth.authorizeURL(challenge: "test_challenge")
    XCTAssertTrue(url.absoluteString.contains("client_id=skylight-mobile"))
    XCTAssertTrue(url.absoluteString.contains("code_challenge=test_challenge"))
    XCTAssertTrue(url.absoluteString.contains("code_challenge_method=S256"))
}
func testExtractCodeFromRedirectURL() {
    let code = try SkylightAuth.extractCode(from: "https://ourskylight.com/welcome?code=abc123")
    XCTAssertEqual(code, "abc123")
}
func testExtractCodeFromBareCode() {
    let code = try SkylightAuth.extractCode(from: "abc123")
    XCTAssertEqual(code, "abc123")
}
```

- [ ] **Step 5: Run tests — expect fail**

Run: `swift test --filter OAuthTests`
Expected: compilation error (SkylightAuth not yet implemented)

- [ ] **Step 6: Implement `OAuth.swift` to pass tests**

- [ ] **Step 7: Run tests — expect pass**

Run: `swift test --filter OAuthTests`

- [ ] **Step 8: Write `MockURLProtocol.swift`**

A `URLProtocol` subclass that captures requests and returns canned responses. Static `var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?`. Used by all SkylightClient tests.

- [ ] **Step 9: Write `Client.swift`**

Constants: `apiVersion = "2026-05-01"`, `userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"`. Internal `request(method:path:query:body:)` sets Accept, Authorization, User-Agent, Skylight-Api-Version headers. On 401 from first attempt, calls `SkylightAuth.refresh`, updates stored token, calls `onRefresh`, retries once. On 4xx/5xx throws `APIError`.

- [ ] **Step 10: Write failing `ClientTests.swift`**

```swift
func testAutoRefreshOn401() async throws {
    // First request returns 401, second returns 200 with frame data.
    // Assert onRefresh was called with new token.
    // Assert the retried request has the new access token.
}
func testThrowsAPIErrorOn4xx() async throws {
    // Return 422. Assert APIError with correct statusCode and body.
}
```

- [ ] **Step 11: Write `Frames.swift` and `Messages.swift`**

`frames()`: GET `/api/frames`, parse JSON:API `data` array, map to `[Frame]`. `name` prefers `household_name`, falls back to `name` (same as Go client).

`messageIDs(frameID:)`: GET `/api/frames/{id}/messages/all_ids`, parse `{"data":[{"id":"...","type":"id"},...]}`, return `[String]`.

`upload(frameID:ext:imageData:)`: POST `/api/upload_urls?request_source=android_share` with `{"ext":ext,"frame_ids":[frameID]}`. Parse first `data[0].url`. Extract message ID from `x-amz-meta-recipient_message_ids=` query param in the presigned URL. PUT `imageData` to presigned URL with `Content-Type: image/{ext}` using a plain URLSession (no auth headers). Return `UploadResult`.

`deleteMessages(frameID:ids:)`: DELETE `/api/frames/{id}/messages/destroy_multiple` with `{"message_ids":ids}`.

- [ ] **Step 12: Write failing `MessagesTests.swift`**

```swift
func testMessageIDsParsesJSONAPI() async throws {
    // Mock returns {"data":[{"id":"111","type":"id"},{"id":"222","type":"id"}]}
    let ids = try await client.messageIDs(frameID: "1")
    XCTAssertEqual(ids, ["111", "222"])
}
func testUploadParsesMessageIDFromPresignedURL() async throws {
    // Mock upload_urls returns presigned URL containing recipient_message_ids=999
    // Mock PUT returns 200
    let result = try await client.upload(frameID: "1", ext: "jpg", imageData: Data([0xFF]))
    XCTAssertEqual(result.messageID, "999")
}
func testDeleteSendsCorrectBody() async throws {
    // Capture the DELETE request body, assert it equals {"message_ids":["111","222"]}
}
func testUploadRetriesWithFreshURLOnS3_403() async throws {
    // First PUT returns 403 (expired presigned URL).
    // upload() should call upload_urls again for a fresh URL and retry PUT.
}
```

- [ ] **Step 13: Run all tests — expect fail**

Run: `swift test --filter SkylightClientTests`

- [ ] **Step 14: Implement to pass**

- [ ] **Step 15: Run all tests — expect pass**

Run: `swift test --filter SkylightClientTests`

- [ ] **Step 16: Commit**

```bash
git add -A
git commit -m "feat: project scaffold and SkylightClient with OAuth, frames, messages"
```

### Task 2: SyncEngine

**Files:**
- Create: `Sources/SyncEngine/Models.swift`
- Create: `Sources/SyncEngine/SyncEngine.swift`
- Create: `Tests/SyncEngineTests/SyncEngineTests.swift`

**Interfaces:**
- Consumes: nothing (pure logic, no imports from other modules)
- Produces:
  - `PhotoRecord(assetID: String, messageID: String, pending: Bool)`
  - `SyncPlan(uploads: [String], deletes: [(assetID: String, messageID: String)])`
  - `SyncEngine.plan(albumAssetIDs: Set<String>, stateRecords: [PhotoRecord], force: Bool) -> SyncPlan`
  - `SyncEngine.massDeleteExceeded(deleteCount: Int, totalLinked: Int) -> Bool`

- [ ] **Step 1: Write `Models.swift`**

`PhotoRecord` struct with `assetID`, `messageID`, `pending` fields.

- [ ] **Step 2: Write failing `SyncEngineTests.swift`**

```swift
func testEmptyBothSidesProducesNoPlan() {
    let plan = SyncEngine.plan(albumAssetIDs: [], stateRecords: [], force: false)
    XCTAssertTrue(plan.uploads.isEmpty)
    XCTAssertTrue(plan.deletes.isEmpty)
}
func testNewAssetsAreUploads() {
    let plan = SyncEngine.plan(albumAssetIDs: ["a", "b"], stateRecords: [], force: false)
    XCTAssertEqual(Set(plan.uploads), ["a", "b"])
}
func testRemovedAssetsAreDeletes() {
    let records = [PhotoRecord(assetID: "a", messageID: "m1", pending: false)]
    let plan = SyncEngine.plan(albumAssetIDs: [], stateRecords: records, force: false)
    XCTAssertEqual(plan.deletes.count, 1)
    XCTAssertEqual(plan.deletes[0].messageID, "m1")
}
func testPresentInBothIsNoAction() {
    let records = [PhotoRecord(assetID: "a", messageID: "m1", pending: false)]
    let plan = SyncEngine.plan(albumAssetIDs: ["a"], stateRecords: records, force: false)
    XCTAssertTrue(plan.uploads.isEmpty)
    XCTAssertTrue(plan.deletes.isEmpty)
}
func testPendingRecordsAreReUploads() {
    let records = [PhotoRecord(assetID: "a", messageID: "m1", pending: true)]
    let plan = SyncEngine.plan(albumAssetIDs: ["a"], stateRecords: records, force: false)
    XCTAssertEqual(plan.uploads, ["a"])
    XCTAssertTrue(plan.deletes.isEmpty) // pending record is re-uploaded, not deleted
}
func testMassDeleteThreshold() {
    // max(5, 25% of 100) = 25. Deleting 26 should exceed.
    XCTAssertTrue(SyncEngine.massDeleteExceeded(deleteCount: 26, totalLinked: 100))
    XCTAssertFalse(SyncEngine.massDeleteExceeded(deleteCount: 25, totalLinked: 100))
    // Small set: max(5, 25% of 8) = 5. Deleting 6 exceeds.
    XCTAssertTrue(SyncEngine.massDeleteExceeded(deleteCount: 6, totalLinked: 8))
    XCTAssertFalse(SyncEngine.massDeleteExceeded(deleteCount: 5, totalLinked: 8))
}
```

- [ ] **Step 3: Run tests — expect fail**

Run: `swift test --filter SyncEngineTests`

- [ ] **Step 4: Implement `SyncEngine.swift`**

Static `plan` method: build a `Set` of non-pending state asset IDs. Assets in album but not in state set → uploads. Assets in album with pending records → also uploads (re-upload). State records whose asset ID is not in album → deletes. `massDeleteExceeded`: `deleteCount > max(5, totalLinked / 4)`.

- [ ] **Step 5: Run tests — expect pass**

Run: `swift test --filter SyncEngineTests`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: SyncEngine with diff logic and mass-delete limit"
```

### Task 3: State store

**Files:**
- Create: `Sources/State/StateStore.swift`
- Create: `Tests/StateTests/StateStoreTests.swift`

**Interfaces:**
- Consumes: `PhotoRecord` from SyncEngine (or re-exports it; if circular, define it in State and SyncEngine imports State)
- Produces:
  - `StateStore.init(path: String) throws` — opens DB, creates table, sets WAL mode + 5s busy timeout
  - `StateStore.insert(assetID: String, messageID: String, pending: Bool) throws`
  - `StateStore.clearPending(assetID: String) throws`
  - `StateStore.delete(assetID: String) throws`
  - `StateStore.deleteAll(assetIDs: [String]) throws`
  - `StateStore.listAll() throws -> [PhotoRecord]`
  - `StateStore.close()`

Note: `PhotoRecord` should live in State (not SyncEngine) to avoid a circular dependency. SyncEngine imports State for the type.

- [ ] **Step 1: Write failing `StateStoreTests.swift`**

```swift
func testInsertAndListAllRoundTrips() throws {
    let store = try StateStore(path: ":memory:")
    try store.insert(assetID: "a1", messageID: "m1", pending: false)
    let records = try store.listAll()
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].assetID, "a1")
    XCTAssertEqual(records[0].messageID, "m1")
    XCTAssertFalse(records[0].pending)
}
func testClearPendingUpdatesPendingFlag() throws {
    let store = try StateStore(path: ":memory:")
    try store.insert(assetID: "a1", messageID: "m1", pending: true)
    try store.clearPending(assetID: "a1")
    let records = try store.listAll()
    XCTAssertFalse(records[0].pending)
}
func testDeleteRemovesRow() throws {
    let store = try StateStore(path: ":memory:")
    try store.insert(assetID: "a1", messageID: "m1", pending: false)
    try store.delete(assetID: "a1")
    XCTAssertTrue(try store.listAll().isEmpty)
}
func testDeleteAllBatch() throws {
    let store = try StateStore(path: ":memory:")
    try store.insert(assetID: "a1", messageID: "m1", pending: false)
    try store.insert(assetID: "a2", messageID: "m2", pending: false)
    try store.insert(assetID: "a3", messageID: "m3", pending: false)
    try store.deleteAll(assetIDs: ["a1", "a3"])
    let remaining = try store.listAll()
    XCTAssertEqual(remaining.count, 1)
    XCTAssertEqual(remaining[0].assetID, "a2")
}
func testWALModeIsSet() throws {
    let store = try StateStore(path: ":memory:")
    // Query pragma and assert WAL
}
```

- [ ] **Step 2: Run tests — expect fail**

Run: `swift test --filter StateTests`

- [ ] **Step 3: Implement `StateStore.swift`**

`import SQLite3`. Init: `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE`, `sqlite3_exec("PRAGMA journal_mode=WAL")`, `sqlite3_exec("PRAGMA busy_timeout=5000")`, `sqlite3_exec(CREATE TABLE IF NOT EXISTS photo ...)`. Each method prepares a statement, binds, steps, finalizes. `deleteAll` uses a loop or builds `DELETE FROM photo WHERE asset_id IN (?,?,?)` with bound params. `close` calls `sqlite3_close`.

- [ ] **Step 4: Run tests — expect pass**

Run: `swift test --filter StateTests`

- [ ] **Step 5: Move `PhotoRecord` to State, update SyncEngine to import State**

Update `Package.swift`: SyncEngine depends on State. Move `PhotoRecord` from `Sources/SyncEngine/Models.swift` to `Sources/State/StateStore.swift` (or a `Sources/State/Models.swift`). Update SyncEngine imports. Run all tests.

- [ ] **Step 6: Run all tests**

Run: `swift test`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: SQLite state store with WAL mode and busy timeout"
```

### Task 4: Config + Credentials

**Files:**
- Create: `Sources/Config/Config.swift`
- Create: `Sources/Config/Credentials.swift`
- Create: `Sources/Config/Paths.swift`
- Create: `Tests/ConfigTests/ConfigTests.swift`
- Modify: `Package.swift` (add Config target + test target)

**Interfaces:**
- Consumes: `Token` from SkylightClient
- Produces: `SyncConfig` (Codable: albumID, albumTitle, frameID, frameName, pollInterval default 300), `SkylightCredentials` (token: Token, fingerprint: String), `Paths` (static configURL, stateURL, logURL, logDir)

- [ ] **Step 1: Write Config tests**

```swift
func testRoundTrip() throws {
    let config = SyncConfig(albumID: "A", albumTitle: "B", frameID: "1", frameName: "F", pollInterval: 120)
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(SyncConfig.self, from: data)
    XCTAssertEqual(decoded.albumID, "A")
    XCTAssertEqual(decoded.pollInterval, 120)
}
func testDefaultPollInterval() throws {
    let json = #"{"album_id":"A","album_title":"B","frame_id":"1","frame_name":"F"}"#
    let config = try JSONDecoder().decode(SyncConfig.self, from: Data(json.utf8))
    XCTAssertEqual(config.pollInterval, 300)
}
func testPathsUnderApplicationSupport() {
    XCTAssert(Paths.configURL.path.contains("PhotoSync/config.json"))
    XCTAssert(Paths.stateURL.path.contains("PhotoSync/state.db"))
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `swift test --filter ConfigTests`

- [ ] **Step 3: Implement Config.swift, Credentials.swift, Paths.swift**

`SyncConfig`: Codable struct with snake_case CodingKeys, `pollInterval` defaults to 300 via `decodeIfPresent`. `load(from:)` reads URL, `save(_:to:)` writes with `.prettyPrinted`, creates parent dir.

`SkylightCredentials`: wraps `Token` + `fingerprint`. `loadCredentials()` / `saveCredentials(_:)` / `deleteCredentials()` via Security framework SecItemCopyMatching/SecItemAdd/SecItemUpdate/SecItemDelete, service "photosync", account "skylight", JSON-encoded password data.

`Paths`: static computed properties using `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` + "PhotoSync".

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter ConfigTests`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: config, credentials, and path management"
```

### Task 5: PhotoReader + CLI commands (login, sync, status)

**Files:**
- Create: `Sources/PhotoReader/PhotoReader.swift` (protocol)
- Create: `Sources/PhotoReader/PhotoKitReader.swift` (macOS implementation, `#if canImport(Photos)`)
- Create: `Sources/PhotoReader/UTTypeMapping.swift`
- Create: `Sources/PhotoSyncCLI/PhotoSync.swift` (`@main`, top-level command)
- Create: `Sources/PhotoSyncCLI/LoginCommand.swift`
- Create: `Sources/PhotoSyncCLI/SyncCommand.swift`
- Create: `Sources/PhotoSyncCLI/StatusCommand.swift`
- Create: `Tests/PhotoReaderTests/UTTypeMappingTests.swift`
- Modify: `Package.swift` (add PhotoReader target, PhotoSyncCLI executable)

**Interfaces:**
- Consumes: `SkylightClient.Client`, `SyncEngine.plan()`, `StateStore`, `SyncConfig`, `SkylightCredentials`, `Paths`
- Produces: `PhotoReading` protocol: `albumAssetIDs(albumID:) throws -> Set<String>`, `imageData(assetID:) throws -> (data: Data, ext: String)`, `albums() throws -> [(id: String, title: String)]`

- [ ] **Step 1: Write UTType mapping test**

```swift
func testJPEG() { XCTAssertEqual(extensionForUTType("public.jpeg"), "jpg") }
func testHEIC() { XCTAssertEqual(extensionForUTType("public.heic"), "heic") }
func testPNG() { XCTAssertEqual(extensionForUTType("public.png"), "png") }
func testHEIF() { XCTAssertEqual(extensionForUTType("public.heif"), "heic") }
func testUnknown() { XCTAssertEqual(extensionForUTType("public.tiff"), "jpg") }
```

- [ ] **Step 2: Run — expect FAIL**

Run: `swift test --filter UTTypeMapping`

- [ ] **Step 3: Implement PhotoReader protocol + UTType mapping + PhotoKitReader**

`PhotoReading` protocol in `PhotoReader.swift`. `extensionForUTType(_:) -> String` maps UTI strings to file extensions (heif→heic, fallback jpg). `PhotoKitReader` behind `#if canImport(Photos)` uses `PHAsset.fetchAssets(in:options:)` and `PHImageManager.default().requestImageDataAndOrientation`.

- [ ] **Step 4: Implement CLI entry point + LoginCommand**

`PhotoSync.swift`: `@main struct PhotoSync: AsyncParsableCommand` with subcommands. `LoginCommand`: generates PKCE + fingerprint, prints authorize URL, reads code from stdin via `readLine()`, calls `OAuth.exchangeCode()`, saves via `saveCredentials()`.

- [ ] **Step 5: Implement SyncCommand**

Options: `--dry-run`, `--force`. Loads config + credentials, builds `Client`, opens `StateStore`, reads album via `PhotoReading`, calls `SyncEngine.plan()`, checks mass delete limit (skip unless `--force`), prints plan in dry-run, otherwise executes: for each upload — `POST upload_urls`, insert pending row, `PUT` bytes, clear pending; for deletes — `DELETE destroy_multiple`, delete state rows.

- [ ] **Step 6: Implement StatusCommand**

Loads config, opens state, prints album title, frame name, linked count, pending count.

- [ ] **Step 7: Run all tests**

Run: `swift test`

- [ ] **Step 8: Build and verify CLI help**

Run: `swift build && .build/debug/photosync --help`

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: photo reader, login, sync, and status commands"
```

### Task 6: Config wizard

**Files:**
- Create: `Sources/PhotoSyncCLI/ConfigCommand.swift`

**Interfaces:**
- Consumes: `PhotoReading.albums()`, `SkylightClient.Client.frames()`, `Config.save()`, `Credentials.loadCredentials()`, `LoginCommand` (for inline login)

- [ ] **Step 1: Implement ConfigCommand**

`struct ConfigCommand: AsyncParsableCommand`. Interactive flow: call `PhotoReading.albums()`, print numbered list, read selection via `readLine()`, check for credentials (prompt to login if missing), call `client.frames()`, print numbered list, read selection, build `SyncConfig`, save. Print confirmation.

- [ ] **Step 2: Build and manually test**

Run: `swift build && .build/debug/photosync config`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: interactive config wizard"
```

### Task 7: Daemon + install + alerts

**Files:**
- Create: `Sources/PhotoSyncCLI/DaemonCommand.swift`
- Create: `Sources/PhotoSyncCLI/InstallCommand.swift`
- Create: `Sources/PhotoSyncCLI/UninstallCommand.swift`
- Create: `Sources/PhotoReader/ChangeObserver.swift`
- Create: `Sources/Notify/Notify.swift`
- Create: `Sources/PhotoSyncCLI/AlertTracker.swift`
- Create: `Sources/PhotoSyncCLI/Launchd.swift`
- Create: `Sources/PhotoSyncCLI/LogRotation.swift`
- Create: `Tests/PhotoSyncCLITests/AlertTrackerTests.swift`
- Modify: `Package.swift` (add Notify target)

**Interfaces:**
- Consumes: everything from tasks 1-6
- Produces: `AlertTracker` (recordFailure(at:isAuthError:) -> AlertAction, recordSuccess() -> AlertAction), `Notifier.send(title:body:)`, `Launchd.plist(agent:) -> Data`

- [ ] **Step 1: Write AlertTracker tests**

```swift
func testNoAlertBeforeTenMinutes() {
    var tracker = AlertTracker()
    let action = tracker.recordFailure(at: Date(), isAuthError: false)
    XCTAssertEqual(action, .none)
}
func testAlertAfterTenMinutes() {
    var tracker = AlertTracker()
    _ = tracker.recordFailure(at: Date(timeIntervalSinceNow: -601), isAuthError: false)
    let action = tracker.recordFailure(at: Date(), isAuthError: false)
    XCTAssertEqual(action, .alert)
}
func testImmediateOnAuthError() {
    var tracker = AlertTracker()
    let action = tracker.recordFailure(at: Date(), isAuthError: true)
    XCTAssertEqual(action, .alert)
}
func testOncePerStreak() {
    var tracker = AlertTracker()
    _ = tracker.recordFailure(at: Date(timeIntervalSinceNow: -601), isAuthError: false)
    _ = tracker.recordFailure(at: Date(), isAuthError: false) // alerts
    let action = tracker.recordFailure(at: Date(), isAuthError: false)
    XCTAssertEqual(action, .none)
}
func testRecoveryClearsStreak() {
    var tracker = AlertTracker()
    _ = tracker.recordFailure(at: Date(timeIntervalSinceNow: -601), isAuthError: false)
    _ = tracker.recordFailure(at: Date(), isAuthError: false)
    let action = tracker.recordSuccess()
    XCTAssertEqual(action, .recoveryAlert)
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `swift test --filter AlertTracker`

- [ ] **Step 3: Implement AlertTracker**

Struct with `streakStart: Date?`, `alerted: Bool`. `recordFailure(at:isAuthError:)` returns `.alert` on auth error or when streak exceeds 10 min and not yet alerted. `recordSuccess()` returns `.recoveryAlert` if was alerted, `.none` otherwise. Resets state.

- [ ] **Step 4: Run — expect PASS**

Run: `swift test --filter AlertTracker`

- [ ] **Step 5: Implement ChangeObserver**

`ChangeObserver: NSObject, PHPhotoLibraryChangeObserver`. Debounces `photoLibraryDidChange` by 2s via `DispatchWorkItem`. Calls a closure on change.

- [ ] **Step 6: Implement Notify.swift**

`requestPermission()` via `UNUserNotificationCenter.current().requestAuthorization`. `send(title:body:)` posts `UNMutableNotificationContent`. Guarded by `#if canImport(UserNotifications)`.

- [ ] **Step 7: Implement Launchd.swift + LogRotation.swift**

`Launchd.plist(binary:logPath:bundleID:)` renders the XML plist string. Label `dev.zackwag.photosync`, RunAtLoad, LimitLoadToSessionType Aqua, KeepAlive SuccessfulExit=false, ThrottleInterval 30, AssociatedBundleIdentifiers.

`LogRotation.rotateIfNeeded()`: if stdout points to daemon.log and file > 5MB, rename to .1, open new, `dup2`.

- [ ] **Step 8: Implement DaemonCommand**

CFRunLoop on main thread via `DispatchQueue.main.async { RunLoop.main.run() }`. Background queue runs sync loop. Registers ChangeObserver + poll timer. Takes `sync.lock` (flock) per sync, `daemon.lock` for lifetime. Writes daemon state (waiting/running/denied/stopped) + PID to `daemon` table in state.db. SIGTERM handler: set flag, finish current sync, exit 0. After each sync: stat binary, exit with error if changed.

- [ ] **Step 9: Implement InstallCommand + UninstallCommand**

Install: check config + credentials, pick binary path (app bundle or copy to `~/Library/Application Support/PhotoSync/bin/photosync`), write plist to `~/Library/LaunchAgents/`, `launchctl bootstrap`, wait up to 2min for daemon running state.

Uninstall: `launchctl bootout`, remove plist + copied binary, keep config/state/logs.

- [ ] **Step 10: Run all tests**

Run: `swift test`

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: daemon, launchd install, alerts, and change observer"
```

### Task 8: Distribution

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/make-icon.sh`
- Create: `packaging/Info.plist`
- Create: `packaging/photosync.entitlements`
- Create: `packaging/make-icon.swift`
- Create: `.github/workflows/test.yml`
- Create: `.github/workflows/release.yml`
- Create: `.gitignore`
- Create: `README.md`
- Create: `CLAUDE.md`
- Create: `.release-please-manifest.json`
- Create: `release-please-config.json`

**Interfaces:**
- Consumes: the built `photosync` binary
- Produces: `PhotoSync.app` (signed, notarized), Homebrew cask update

- [ ] **Step 1: Create packaging files**

`Info.plist`: CFBundleIdentifier `dev.zackwag.PhotoSync`, CFBundleName `PhotoSync`, LSUIElement true, NSPhotoLibraryUsageDescription "PhotoSync reads your Photo Library to sync albums to your Skylight frame."

`photosync.entitlements`: `com.apple.security.personal-information.photos-library` = true.

`make-icon.swift`: programmatic icon drawing (mirror remindersync pattern, different color/design).

- [ ] **Step 2: Create build-app.sh**

Mirror remindersync's `scripts/build-app.sh`. Build for arm64 + x86_64 with `swift build -c release --arch <arch>`, `lipo -create` into universal binary, create `PhotoSync.app/Contents/MacOS/photosync` + `Contents/Info.plist` + `Contents/Resources/AppIcon.icns`, `codesign --deep --force --options runtime --timestamp --entitlements packaging/photosync.entitlements --sign "$identity"`. Flags: `-v` version, `-s` signing identity (default `-` for ad-hoc), `-o` output dir.

- [ ] **Step 3: Create CI workflows**

`test.yml`: on push/PR, macOS runner: `swift build`, `swift test`. Linux job: `swift build` only (PhotoKit unavailable).

`release.yml`: on tag `v*`. macOS runner: import Developer ID cert from secrets, run `build-app.sh -v $VERSION -s "Developer ID Application"`, `xcrun notarytool submit`, `xcrun stapler staple`, upload `PhotoSync.zip` to release, update `zackwag/homebrew-tap` cask.

- [ ] **Step 4: Create repo scaffolding**

`.gitignore` for Swift (`.build/`, `.swiftpm/`, `dist/`). `README.md` with project description, install instructions, usage. `CLAUDE.md` with project conventions (mirrors remindersync's AGENTS.md style). `.release-please-manifest.json` + `release-please-config.json`.

- [ ] **Step 5: Test ad-hoc build**

Run: `scripts/build-app.sh -o /tmp/photosync-dist && ls -la /tmp/photosync-dist/PhotoSync.app/Contents/MacOS/`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: build scripts, packaging, CI, and repo scaffolding"
```
