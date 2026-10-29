# macOS a1.10.0

- Added Needs Tag Editing in the sidebar, with a count, missing field labels, and the existing tag editor. Checks embedded title, artist, album, genre and year, including blank/Unknown values and zero years. Refresh scans all music in the configured library. Tracks leave the view when their tags are completed. No audio is moved or automatically retagged. This view is independent of the additive Serato review crate.

# macOS a1.10.0

- Added Organize Library: scan all audio in the configured music folder, including songs DeckReady never imported, and add references to the selected crates. Audio files remain in place; no copying, moving, renaming or tag writes occur.
- Added Artist, Genre, Year and Format filters, search, seven Sort by categories, and ascending/descending order. Filters do not limit Organize Library.
- Preview track/crate counts before updating; close Serato safely before writes and preserve existing crate contents.

# DMG packaging fix for a1.09.2

- Embed the branded background and saved Finder layout in local and CI builds.
- Keep DeckReady on the left and Applications on the right at the intended background positions.
- Verify the final DMG background alias and unchanged layout after two read-only mounts at different locations.
- App version remains a1.09.2; this changes packaging only.

# macOS a1.09.2

- Added Year → Artist and Genre → Artist with songs inside artist subcrates.
- Add more / Remove enables both structures referencing the same stored audio; the first option controls folders.
- Missing year/genre or artist tags route tracks to need tag editing, deduplicated across modes.
- Extra selections persist. Existing files and crate contents remain in place. Retry follows the same routing.
- Numeric version 1.9.2, build 11. Based on macOS a1.09.1, with Xcode 15.2 compatibility.

# DeckReady macOS a1.09.1

## Alpha a1.09.1

- Fixed Serato reopen behavior: DeckReady no longer launches Serato after a normal sync when Serato was already closed.
- If Serato was running, DeckReady can still quit it to apply crate changes and optionally reopen it afterward.
- Updated the Serato setting text to clarify that reopening only applies after DeckReady closes a running Serato session.

## Alpha a1.09.1

### Added / Improved
- Added Previous Track to the in-app Now Playing controls.
- Added native macOS Previous Track support through `MPRemoteCommandCenter`.
- Added a scrubbable playback progress bar with elapsed and total time.
- Added a compact embedded album-art thumbnail to the Now Playing bar with a fallback placeholder.
- Improved playback-duration synchronization from the active AVPlayer item.
- Previous and Next button availability now follows the active DeckReady playback queue.
- Bundle marketing version updated to **1.9.1** and build number to **9**.

## Alpha a1.08.1

### Fixed / Improved
- Fixed Xcode 15.2/macOS build failures caused by using `MPNowPlayingSession` APIs that are unavailable on macOS. DeckReady now uses the shared `MPRemoteCommandCenter` and default `MPNowPlayingInfoCenter`.
- Fixed Swift concurrency errors in the AVPlayer time/end observers while preserving main-thread playback state updates.
- Added Skip / Next Track to DeckReady's Now Playing bar.
- Added native macOS Control Center / Now Playing publishing via MediaPlayer.
- Native media controls can Play, Pause, toggle playback, seek, and skip to the next DeckReady track.
- Publishes title, artist, album, duration, position, queue position, and embedded artwork when available.
- Preview playback automatically advances to the next track when possible.
- Bundle marketing version updated to **1.8.1** and build number to **8**.

# DeckReady macOS Changelog

## Alpha a1.08.0

### Added
- New **Tag Editor** button in the left sidebar.
- Dedicated two-pane tag editor inspired by desktop music-tagging tools.
- Browse library tracks on the left and edit Title, Artist, Album, Genre, and Year on the right.
- Play/Pause, Reveal, Reload Tags, and Save Tags controls in the editor.
- Tag-writing status and format support messaging.

### Included
- Now Playing bar from a1.07.1.
- Help links for GitHub, Discord, and Report an Issue.
- DMG + PKG packaging scripts.

### Notes
- MP3 and WAV/WAVE embedded tag writing remains supported on the Ventura/Xcode 15.2 build. Other imported formats remain read-only in the Tag Editor until their writer is implemented safely.
- Bundle marketing version: **1.8.0**.

## Alpha a1.07.1
- Fixed audio previews playing without appearing in Now Playing.
- Added a persistent Now Playing bar for preview audio with title, artist, pause/resume, and stop.

## Alpha a1.07.0
- Added Help → DeckReady on GitHub, DeckReady Discord, and Report an Issue.
- Added PKG builder and combined DMG + PKG builder.
- Improved branded DMG packaging.

## Alpha a1.06.1
- Fixed the ImportService optional-chaining compiler failure.
