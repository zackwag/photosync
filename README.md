# PhotoSync

Syncs an iCloud Photo Album to a Skylight frame. One album as the single source of truth for multiple displays: add a photo to the album, it shows up on Skylight (and HomeView, and anything else that reads from the album). Remove it from the album, it's removed from Skylight.

One-way push with deletion sync. No Skylight-to-album sync.

## Install

```sh
brew install zackwag/tap/photosync
```

Or download `PhotoSync.zip` from [Releases](https://github.com/zackwag/photosync/releases), unzip, and move `PhotoSync.app` to `~/Applications`.

## Setup

```sh
photosync login    # authenticate with Skylight
photosync config   # pick an album and a frame
photosync sync --dry-run   # preview
photosync sync     # run it
photosync install  # start the background daemon
```

## Commands

| Command | Description |
|---------|-------------|
| `login` | Authenticate with Skylight via OAuth |
| `config` | Interactive setup: choose album and frame |
| `sync` | One-shot sync (supports `--dry-run`, `--force`) |
| `status` | Show sync status |
| `install` | Install the launchd daemon |
| `uninstall` | Remove the launchd daemon |
| `daemon` | Run the sync loop (managed by launchd) |

## How it works

The daemon polls the photo album and compares it against a local SQLite state database that maps album asset IDs to Skylight message IDs.

- New photos in the album are uploaded to Skylight via presigned S3 URLs.
- Photos removed from the album are deleted from Skylight.
- A safety limit blocks mass deletes (>25% of linked photos) unless `--force` is passed.
- Crash recovery: uploads are tracked as "pending" in the database. If a crash happens mid-upload, the pending record is retried on the next sync.

## Data locations

| File | Path |
|------|------|
| Config | `~/Library/Application Support/PhotoSync/config.json` |
| State DB | `~/Library/Application Support/PhotoSync/state.db` |
| Daemon log | `~/Library/Logs/PhotoSync/daemon.log` |
| Credentials | macOS Keychain (service: `photosync`) |
| LaunchAgent | `~/Library/LaunchAgents/dev.zackwag.photosync.plist` |

## Building from source

Requires macOS 14+ and Xcode command line tools.

```sh
swift build
swift test
scripts/build-app.sh   # ad-hoc signed PhotoSync.app in dist/
```
