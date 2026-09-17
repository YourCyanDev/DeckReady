# DeckReady
Finally a better way to import and organize music! 

**Prepare your music. Import it. Get behind the decks.**

DeckReady is a desktop utility designed to make preparing and importing music into **Serato DJ** faster and easier.

Instead of manually organizing downloaded tracks, moving files around, and managing Serato imports one by one, DeckReady provides a streamlined workflow for getting music ready for your library.

> **Current platform:** macOS
> **Windows support:** Planned

---

## About DeckReady

DeckReady was created to simplify the process of preparing music before using it in Serato.

The goal is simple:

**Download → Organize → Import → DJ**

DeckReady handles the repetitive parts of that process while keeping the user in control of their music library.

---

## Features

### Serato Integration

Import prepared music into your Serato library without manually locating and moving every track.

DeckReady is designed to work alongside Serato's existing library structure rather than replace it.

### Music Organization

Keep imported tracks organized and ready to use before opening Serato.

### Automatic File Handling

DeckReady can manage the source files after an import is completed.

An optional setting can automatically delete the original source file after DeckReady has successfully processed it.

> Automatic deletion should only occur after the import has completed successfully.

### Serato Detection

DeckReady can detect when Serato is currently running.

Because changes made directly to Serato's library files may not immediately appear inside an already-running Serato session, DeckReady can warn the user when Serato needs to be restarted.

Users can choose to:

* **Quit & Reopen Serato**
* **Restart Later**

This helps prevent confusion when newly imported tracks have been saved but are not yet visible inside Serato.

### Import Safety

DeckReady is being designed to avoid modifying Serato data unnecessarily and to reduce the chance of library corruption or incomplete imports.

### Simple Desktop Interface

DeckReady provides a dedicated graphical interface instead of requiring terminal commands or manual file editing.

---

## Planned Features

DeckReady is still under active development.

Planned features include:

* Windows support
* `.pkg` installer for macOS
* Windows installer / `.exe` release
* Import history
* Activity and diagnostic logs
* Improved Serato library detection
* Improved metadata handling
* Additional file-management options
* Better error recovery
* Automatic update support
* Expanded settings
* More import customization

---

## Installation

### macOS

Prebuilt releases will eventually be available through the repository's **Releases** section.

For development builds, installation may currently require manually launching the application.

Because DeckReady may not currently be signed with an Apple Developer certificate, macOS may display a security warning when opening the application.

If macOS blocks the application, you may need to allow it from:

**System Settings → Privacy & Security**

Only download DeckReady from the official repository.

---

## Using DeckReady

A typical DeckReady workflow looks like this:

1. Download or locate the music you want to import.
2. Open DeckReady.
3. Select your tracks.
4. Choose your import options.
5. Import the music.
6. DeckReady prepares the files for Serato.
7. Restart Serato if DeckReady indicates that it is required.
8. Open Serato and access your newly imported music.

---

## Serato Must Sometimes Be Restarted

Serato loads portions of its music library when the application starts.

If DeckReady modifies library information while Serato is already running, Serato may continue displaying the older version of the library until it reloads.

DeckReady may therefore display a warning similar to:

> **Your changes were saved successfully, but Serato must restart before they will appear.**

You can then choose to restart Serato immediately or restart it later.

---

## Development Status

DeckReady is currently under development and should be considered **pre-release software** until a stable version is published.

Features, file formats, settings, and internal behavior may change between development versions.

Back up important music and Serato library data before testing development builds.

---

## Roadmap

### macOS

* [x] Initial DeckReady application
* [x] Music import workflow
* [x] Serato integration development
* [x] Serato running detection
* [x] Restart warning workflow
* [ ] Stable macOS release
* [ ] Packaged `.pkg` installer
* [x] Import history
* [ ] Built-in logging system
* [ ] Automatic update system

### Windows

* [ ] Windows port
* [ ] Windows Serato library integration
* [ ] Windows testing
* [ ] `.exe` / installer release

### Distribution

* [ ] Stable GitHub release
* [x] Release notes
* [x] Downloadable builds
* [x] Versioned releases

---

## Building From Source

Build instructions will be expanded as DeckReady approaches its first stable public release.

Developers who clone the repository should use the dependencies and development environment specified by the project files included in the repository.

```bash
git clone <DECKREADY_REPOSITORY_URL>
cd DeckReady
```

Additional setup instructions will be added as the build process is finalized.

---

## Reporting Bugs

If you discover a problem with DeckReady, please open a GitHub Issue.

When reporting a bug, include:

* DeckReady version
* macOS or Windows version
* Serato version
* What you were trying to do
* What happened
* What you expected to happen
* Any relevant DeckReady logs
* Screenshots of the error, if applicable

Please avoid including private information or copyrighted music files in public bug reports.

---

## Contributing

DeckReady is currently being actively developed.

Contribution guidelines will be expanded as the project becomes more stable.

Bug reports, testing feedback, and reproducible issue reports are especially useful during development.

---

## Disclaimer

DeckReady is an independent project and is **not affiliated with, endorsed by, sponsored by, or officially associated with Serato Limited**.

**Serato** and **Serato DJ** are trademarks of their respective owners.

DeckReady interacts with files used by DJ software. Although the project is designed with data safety in mind, you should maintain backups of important music libraries and Serato data, especially when using development or pre-release versions.

Use DeckReady at your own risk.

---

## License

The license for DeckReady will be specified in the repository's `LICENSE` file.

---

## DeckReady

**Less file management. More time behind the decks.**

**Join the community, https://discord.gg/BuVnCQ5fG9**
