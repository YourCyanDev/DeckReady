# ✨ Features

## 🎵 Music Importing

DeckReady supports multiple ways to bring music into your workflow.

You can import:

* Individual tracks
* Multiple tracks
* Entire folders
* ZIP archives containing music
* Files through drag and drop
* Files through the application menu
* Music placed into DeckReady's watched import folder

---

## 🔄 Automatic Import Folder

DeckReady includes a dedicated watched folder for new music.

On macOS this may appear as:

```text
DeckReady Imports
```

On Windows the workflow uses the DeckReady import / Inbox folder.

Save or move supported music into this folder and DeckReady can automatically detect and process it.

This makes it useful with:

* Browser downloads
* Music download tools
* Finder
* File Explorer
* Drag and drop
* Other applications that can save files into a selected folder

The goal is simple:

### Download → DeckReady → Serato

---

## 📁 Automatic Organization

DeckReady can organize imported music into its library using track information such as:

* Artist
* Genre
* Year

This helps reduce the amount of manual sorting required after downloading music.

---

## 📋 Copy or Move

Choose how DeckReady handles your original files.

### Copy

Keeps the original file and creates an organized copy inside the DeckReady library.

### Move

Moves the original file into the DeckReady library.

This allows DeckReady to work with both temporary download folders and existing music collections.

---

## 🏷️ Metadata

DeckReady can read track metadata and provides metadata editing tools for supported audio formats.

Metadata may include:

* Title
* Artist
* Album
* Genre
* Year

Metadata support will continue to improve throughout Alpha development.

---

## 🔍 Duplicate Detection

DeckReady can detect tracks that have already been imported.

Duplicate detection helps prevent the same music from being added multiple times, even when files have been renamed or imported through different workflows.

Detected duplicates can be separated from successful imports for review.

---

## 🕘 Recent Imports

DeckReady keeps track of recently processed music so you can quickly review what has been added.

Import history can persist between sessions.

---

## 🔎 Library Search

Search your DeckReady music collection directly from inside the application instead of manually browsing through folders.

---

## 📦 ZIP Imports

DeckReady can process music contained inside ZIP archives.

The import workflow can:

1. Extract supported music
2. Read track information
3. Check for duplicates
4. Organize successful imports
5. Prepare tracks for the DeckReady library

---

# 🎚️ Serato Integration

DeckReady is built around a **Serato-ready workflow**.

Current development includes support for:

* Detecting Serato
* Preparing music for Serato
* Serato crate workflows
* Handling library synchronization
* Detecting when Serato must restart
* Opening Serato after supported workflows
* Backup-focused behavior before supported library changes

---

## 🔄 Waiting for Serato

If Serato is already running when DeckReady needs to update library information, DeckReady can mark tracks as:

### Waiting for Serato

You may then be given options such as:

* **Quit & Reopen Serato**
* **Restart Later**

This helps avoid modifying library information while Serato is actively using it.

---

# 🧹 Source Cleanup

DeckReady can optionally clean up source files after a successful import.

Cleanup is designed to happen only after DeckReady confirms that the music was successfully processed or identified as a duplicate.

Additional safeguards are used to reduce the risk of accidentally deleting important library files.

---

# 💾 Persistent Settings

DeckReady remembers application settings between sessions.

Settings may include:

* Library locations
* Import behavior
* Copy / Move preference
* Organization settings
* Source cleanup
* Serato options
* Application preferences

---

# 📜 Logging

DeckReady includes logging and diagnostic tools to help troubleshoot issues during Alpha development.

Logging can help identify problems involving:

* Imports
* Duplicate detection
* Metadata
* File movement
* Automatic folder syncing
* Serato synchronization
* Application errors

---

# ❓ Help Menu

Starting with **a1.07.0**, DeckReady includes quick-access links from inside the app.

The Help menu includes:

* **DeckReady on GitHub**
* **DeckReady Discord**
* **Report an Issue**

---

# 🍎 macOS

DeckReady is actively developed for macOS.

Current distribution:

* `.dmg`

Planned distribution:

* `.pkg`

The macOS version includes the same overall DeckReady workflow while using a native macOS interface and packaging system.

---

# 🪟 Windows

DeckReady is actively developed for Windows using:

* C#
* .NET 8
* WPF

Planned Windows distribution includes:

* `.exe`
* `.msi`

A full MSI installer is planned as DeckReady moves closer to leaving Alpha.

---

# 📥 Downloads

DeckReady builds are available from the GitHub Releases page:

[https://github.com/YourCyanDev/DeckReady/releases](https://github.com/YourCyanDev/DeckReady/releases)

Because DeckReady is still in Alpha, releases should currently be treated as testing builds.

---

# 🔜 Planned Improvements

DeckReady development is ongoing.

Future releases are expected to include improvements such as:

* Expanded metadata editing
* Improved Serato integration
* Better Serato DJ Pro / Lite detection
* More import customization
* Improved duplicate handling
* Better import progress information
* Improved error messages
* Expanded diagnostics and logging
* UI improvements
* Performance improvements
* Reliability improvements
* Automatic update support
* macOS `.pkg` distribution
* Windows `.exe` distribution
* Windows `.msi` installer

---

# 🐛 Bug Reports

Found something broken?

Report it here:

[https://github.com/YourCyanDev/DeckReady/issues](https://github.com/YourCyanDev/DeckReady/issues)

A useful bug report should include:

* DeckReady version
* Operating system version
* Serato version
* What you were trying to do
* Steps to reproduce the issue
* What you expected to happen
* What actually happened
* Screenshots when relevant
* Logs when relevant

Please do not upload copyrighted music files to public GitHub issues.

---

# 💡 Feature Requests

Feature suggestions are welcome while DeckReady is in Alpha.

When submitting an idea, explain:

* What you want DeckReady to do
* How you currently handle the task
* How the feature would improve your workflow

---

# 🔗 Links

### GitHub

[https://github.com/YourCyanDev/DeckReady](https://github.com/YourCyanDev/DeckReady)

### Discord

[https://discord.gg/BuVnCQ5fG9](https://discord.gg/BuVnCQ5fG9)

### Report an Issue

[https://github.com/YourCyanDev/DeckReady/issues](https://github.com/YourCyanDev/DeckReady/issues)

---

# ⚠️ Alpha Notice

DeckReady is early-development software.

You may encounter:

* Bugs
* Incomplete features
* Metadata edge cases
* Import failures
* Serato synchronization issues
* UI inconsistencies
* Features that change between builds

Maintain backups of important music and Serato library data while using Alpha builds.

---

# Disclaimer

DeckReady is an independent project and is **not affiliated with, endorsed by, sponsored by, or officially associated with Serato Limited**.

Serato and Serato DJ are trademarks of their respective owners.

DeckReady interacts with music files and DJ library information. Although safeguards and backup features are being developed, Alpha software can contain bugs.

Use development builds with appropriate backups.

---

# 🎶 DeckReady

## Organize › Prepare › Play

### Your music. Serato ready.

## iPhone and iPad alpha

The SwiftUI iOS app lives in [`ios/`](ios/README.md). Open `ios/DeckReady.xcodeproj` on a Mac to develop and test local imports, previews, crates and Files export for Serato DJ for iOS. This is an early source alpha and requires simulator and physical-device validation before release.
