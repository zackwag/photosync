# AGENTS.md

## Project overview

PhotoSync syncs an iCloud Photo Album to a Skylight frame: one-way push with deletion sync. Apple Photos is the source of truth, read through PhotoKit. The Skylight API is reached through a Swift REST client.

It's a Swift CLI (`photosync`) that also runs as a launchd daemon. Releases ship it as `PhotoSync.app`, signed with a Developer ID and notarized, through the `zackwag/tap` Homebrew cask.

`docs/design.md` is the source of truth for behavior: the confirmed API facts, the sync algorithm, and the dismissed alternatives. Read the relevant section before changing behavior, and update it in the same PR.

## Setup

- macOS 26+ on Apple silicon and Xcode command line tools. PhotoKit requires macOS.
- A Mac with Photos access and a Skylight login. Skylight tokens live in the Keychain (service `photosync`), and `photosync login` creates them.
- User data lives in `~/Library/Application Support/PhotoSync/` (`config.json` and `state.db`), and the daemon logs to `~/Library/Logs/PhotoSync/daemon.log`.

## Build / Run

```sh
swift build
swift run PhotoSyncCLI <command>
scripts/build-app.sh                    # ad-hoc signed PhotoSync.app in dist/
scripts/build-app.sh -s "Developer ID Application"  # Developer ID signed
```

The Photos permission (TCC) is checked against the binary's code signature. A plain `swift build` is signed ad hoc, so every new build triggers the Photos prompt again. To avoid this, build with the Developer ID and run from `~/Applications`.

## Test

```sh
swift build
swift test
```

## Repository structure

- `Sources/SkylightClient/`: OAuth + REST client for the Skylight API.
- `Sources/SyncEngine/`: Pure diff logic comparing album assets against state.
- `Sources/State/`: SQLite state store mapping photo asset IDs to Skylight message IDs.
- `Sources/Config/`: JSON config, Keychain credentials, file paths.
- `Sources/PhotoReader/`: PhotoKit reader, UTType mapping, change observer.
- `Sources/Notify/`: macOS UserNotifications.
- `Sources/PhotoSyncCLI/`: CLI entry point and all commands.
- `Tests/`: Unit tests for each module.
- `packaging/`: Info.plist, entitlements.
- `scripts/`: build-app.sh.
- `docs/`: design.md, plan.md.

## Conventions

- Match the surrounding code's style: doc comments on exported identifiers.
- Errors use typed enums conforming to `LocalizedError`.
- Tests use XCTest with table-driven patterns where appropriate.
- Skylight's API is undocumented; check behavior against a live account before relying on it, and record findings in `docs/design.md`.
- Markdown follows markdownlint with MD013 off.

## Commit and PR conventions

- Conventional Commits: `feat:`, `fix:`, `docs:`, `ci:`, `chore:`, `refactor:`, `test:`.
- PRs are squash-merged; the PR title becomes the commit on `main`.
- Releases use release-please. Don't hand-edit `CHANGELOG.md` or `.release-please-manifest.json`.
