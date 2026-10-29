## Organize Library and browsing (a1.10.0)

Open Music Library and click **Organize Library** to scan the entire configured music folder, including songs that were not imported through DeckReady. It adds references to the organization structures selected in Settings. Review the song/crate counts, then confirm. Audio files are not copied, moved, renamed or retagged; existing crate contents are retained. Serato must be closed during updates. Active filters do not restrict this operation.

Use Artist, Genre, Year and Format filters together; Clear Filters resets them. Sort by Title, Artist, Album, Genre, Year, Duration or Filename, in either direction. Unknown tags can be filtered explicitly.

## Persistent DMG background fix

The local builder and CI use the same DMG packager. It embeds the branded PNG and writes Finder's .DS_Store directly, with a background alias targeting the image's own volume. The final compressed DMG is mounted read-only twice at different paths to verify the background and saved icon positions survive reopening. No Finder automation is needed. Packaging requires Python 3.9+; dependencies are installed in a private build-cache environment on first use.

# DeckReady macOS a1.09.2

In Settings → Music Library → Organize by, select **Year → Artist (songs inside)** or **Genre → Artist (songs inside)**. Use **Add more** to enable both. The first option controls file storage; every selected crate structure references the same stored audio file. Missing required tags go to **need tag editing**. Existing files are not relocated, and existing crate tracks are retained.

Build on macOS Ventura 13+ with Xcode 15.2 or newer. Run `Build DeckReady macOS Installers.command` to build the app, DMG and PKG. The source also lives under `macos/` in the repository. Serato must be closed while crates are updated. Live Serato import/export testing remains required.

# DeckReady macOS Alpha a1.09.2

DeckReady macOS **a1.09.2** source and release builders for Xcode 15.2 / macOS Ventura 13+.

### a1.09.2 behavior fix

DeckReady no longer launches Serato after syncing when Serato was already closed. Serato is only eligible to be reopened when it was running and DeckReady had to close it to safely apply crate changes.

## New in a1.09.2

- Added a **Previous Track** button to DeckReady's persistent Now Playing bar.
- Added native macOS **Previous Track** media-control support.
- Added a compact **playback time bar** showing elapsed time and total duration.
- The playback bar is **scrubbable**, so you can jump to another point in the preview.
- Added a small **album artwork thumbnail** beside the Now Playing track details.
- If embedded artwork is unavailable, DeckReady shows a clean music-note placeholder.
- Improved Now Playing duration synchronization using the active `AVPlayerItem` duration when available.
- Previous / Next availability follows the active DeckReady playback queue.

## Included from a1.08.1

- Skip / Next Track support in DeckReady and macOS system media controls.
- Native macOS Now Playing / Control Center integration using MediaPlayer.
- Publishes title, artist, album, duration, playback position, playback state, queue position, and embedded artwork when available.
- Native Play, Pause, Play/Pause, Next Track, and playback-position controls.
- Automatic next-track playback when the current preview finishes.

## Included from a1.08.0

- Dedicated **Tag Editor** page in the sidebar.
- Edit Title, Artist, Album, Genre, and Year.
- Play/Pause, Reveal, Reload Tags, and Save Tags controls.
- MP3 and WAV/WAVE embedded tag writing with DeckReady's safety-backup verification.
- Persistent in-app Now Playing bar.
- DeckReady GitHub, Discord, and Report an Issue links in the Help menu.
- Branded Finder DMG layout and standard macOS PKG installer builder.

## Release builders

- `Build DeckReady DMG Fast.command` — incremental unsigned app build + branded DMG.
- `Package Cached App DMG.command` — repackage an existing cached app without recompiling.
- `Build DeckReady PKG.command` — incremental unsigned app build + standard PKG installer.
- `Build DeckReady macOS Installers.command` — creates **both DMG and PKG** in one run.

Outputs:

- `DeckReady-a1.09.2.dmg`
- `DeckReady-a1.09.2.pkg`

The PKG installs `DeckReady.app` into `/Applications`.

> These Alpha installers are currently unsigned. macOS may require Control-click → Open or approval in System Settings → Privacy & Security.

## Official links

- GitHub: https://github.com/YourCyanDev/DeckReady
- Discord: https://discord.gg/BuVnCQ5fG9
- Issues: https://github.com/YourCyanDev/DeckReady/issues
