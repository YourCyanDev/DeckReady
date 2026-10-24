# DeckReady for iPhone and iPad

First iOS alpha: **a1.01**, bundle version 0.1.0 (1). Separate from the desktop version numbers. Requires iOS 17 or later; Serato's own minimum requirements also apply when importing into Serato.

## Open and run

1. On a Mac with Xcode 16 or newer, open `ios/DeckReady.xcodeproj`.
2. Allow Xcode to resolve ZIPFoundation 0.9.20 from Swift Package Manager.
3. Choose the DeckReady scheme and an iPhone simulator, then Run.
4. For a physical phone, choose your team under Signing & Capabilities, change the bundle identifier if needed, connect your iPhone, and enable Developer Mode when asked. No developer credentials are included.

Windows can edit the source but cannot build or sign an iPhone app with Xcode. This is source code, not an installable IPA or a TestFlight release.

## Included

- Files picker for multiple songs, folders and ZIP imports; originals remain untouched.
- Private local library, SHA-256 duplicate detection and readable per-file import errors.
- Embedded title, artist, album, artwork and duration when the audio provides them.
- Search and sorting by title or artist.
- Persistent previews across tabs with play/pause and volume.
- Saved crates with add/remove songs and drag ordering through Edit.
- Crate folder export using Files, with numbered filenames to preserve an ordering hint.
- Track deletion confirmation; deleting a crate keeps the songs in the library.

## Serato workflow

Export a crate to a folder using its menu → Export to Files. Save to On My iPhone or iCloud Drive. In Serato DJ for iOS choose **Transfer & Files → Import Folder**, select the exported folder and complete Serato's import. This requires user action in Serato. A live device test must confirm the Files folder exporter and exact supported audio formats before release. Serato may sort a crate independently of the numeric filenames.

The export contains original audio files, not a Serato database. This alpha does not claim automatic Serato injection, cue or beatgrid editing, desktop sync, file-tag writing, cloud sync, background folder watching, or background playback. DRM-protected streaming downloads are not supported. The on-screen metadata is read from audio; it is not editable yet.

## Validation

XCTest covers filename safety/collisions and persistence with crate cleanup after deleting a track. The GitHub iOS workflow builds and runs these on a macOS runner with an iPhone simulator. Development in the initial Linux environment cannot run Xcode, so a successful simulator/device build remains a release gate.

Manual device checks before shipping:

- Import local and iCloud songs, a nested folder, ZIP, corrupt audio, duplicates, same-title different recordings and a large batch.
- Restart the app and confirm tracks, artwork, crate membership and order persist.
- Preview, pause, change volume, switch tabs and interrupt playback with a call or headphones removal.
- Export a nonempty crate to local Files and iCloud, then import it in Serato and verify titles, number of songs and playback.
- Test export cancellation, full storage, missing music, ZIP path traversal and ZIPs with symlinks or very large expanded content.

## Architecture

SwiftUI UI, Codable atomic library snapshots, AVFoundation metadata and preview, CryptoKit content hashes, ZIPFoundation extraction, FileDocument folder export. Audio is copied to `Documents/DeckReady`; library references use relative filenames. Large archives are currently not size-capped; only import archives you trust during this alpha. Exports are assembled in memory and need device stress testing for large crates. The app uses the desktop charcoal/mint palette.

The project and scheme are checked in; `python3 tools/generate_project.py` regenerates them deterministically if targets or sources change.
