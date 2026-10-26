# DeckReady Windows a1.09.0

- Raised Windows app and MSI versions to **a1.09.0 / 1.9.0**, so this build upgrades older 1.8.x installations. Updated local build scripts and CI output names to match.

- Added **Add more** / **Remove** organization controls. Year/artist and genre/artist crates can be enabled together; the first option controls file storage, and all selected structures reference the same audio files. Selections persist between sessions.

- Added **Year → Artist (songs inside)** and **Genre → Artist (songs inside)** under Settings → Import Behavior → Organize by.
- New imports use `Library/Year/Artist/song.ext`. With automatic Serato sync, tracks are added to a year crate and an artist subcrate (`2026 → Yo DJ Hill → songs`), while Serato is closed.
- Genre/artist mode uses genre crates with artist subcrates and matching genre/artist folders. Missing genre or artist tags go only to **need tag editing**.
- Year/artist mode uses year names as top-level crates instead of the single crate-name setting. Existing crate tracks are retained. No existing library files are moved.
- Tracks missing either year or artist go only to the **need tag editing** crate; their storage folders use **Unknown Year** / **Unknown Artist**. Edited queue metadata is used even with file-tag writing disabled.
- Windows source implementation; macOS source is not present in this repository. iOS has a separate draft implementation.

# DeckReady Windows a1.08.0

## Added
- New **Tag Editor** page in the left sidebar.
- Two-pane tag editing layout: track browser on the left, metadata editor on the right.
- Edit Title, Artist, Album, Genre, and Year directly from the DeckReady library.
- Save Tags writes to the actual audio file using the existing safety-backup + verification flow.
- Play/Pause, Reveal, Reload Tags, and Save Tags controls are available directly in the Tag Editor.

## Included
- Now Playing visibility fix from a1.07.1.
- Windows setup wizard with install-location and optional desktop-shortcut screens.
- Public version: **a1.08.0**. Internal MSI version: **1.8.0**.

---

# DeckReady Windows a1.07.0 - MSI Builder Revision 11

- Added a real **Custom Setup** screen to the MSI wizard.
- The screen includes an optional **Desktop shortcut** feature.
- Desktop shortcut is selected by default, but users can disable it before installation.
- DeckReady itself remains required and cannot be deselected.
- Internal MSI version raised to **1.7.11** so it upgrades earlier a1.07.0 installer test builds.
- Public DeckReady version remains **a1.07.0**.

---

# DeckReady Windows a1.07.0 — MSI Builder Revision 10

- Added a real Windows setup wizard using WiX Toolset UI.
- Added Welcome, License Agreement, Destination Folder, Ready to Install, Progress, and Finish pages.
- Added DeckReady-branded welcome and banner artwork.
- Added a DeckReady alpha license/notice screen.
- Internal MSI ProductVersion is now 1.7.10 so it cleanly upgrades earlier a1.07.0 test installers.
- Kept the public DeckReady version at **a1.07.0**.
- Validated on a Windows GitHub Actions runner: WiX build, wizard dialog tables, upgrade over an older MSI, payload replacement, and uninstall all passed.

## MSI Builder Revision 9 (public release remains a1.07.0)

- Changed the internal MSI ProductVersion from 1.7.0 to 1.7.9 while keeping the app/public version at a1.07.0.
- Forces Windows Installer to perform a true major upgrade from earlier a1.07.0 test MSIs instead of entering same-version maintenance/configuration.
- Added `Build and Install DeckReady MSI.bat`, which builds the verified MSI, launches it, and always writes a verbose Windows Installer log.
- Embedded-cabinet verification remains enabled.

# DeckReady Windows a1.07.0 — MSI Builder Revision 8

- Fixed Windows Installer hanging at “Gathering required information…” when an older a1.07.0 MSI was already installed.
- Added WiX `MajorUpgrade` with `AllowSameVersionUpgrades="yes"` so corrected 1.7.0 MSI builds can replace earlier 1.7.0 alpha test builds.
- Kept the embedded-cabinet verification from Revision 7.
- Validated the upgrade path on Windows: old 1.7.0 install → new 1.7.0 install → payload replacement verification → uninstall.
- Public DeckReady version remains **a1.07.0**.

## MSI Builder Revision 7

- Added `installer/Verify-Msi.ps1` to inspect the final MSI database directly.

- Fixed the Revision 6 cabinet verification false positive.
- WiX may create an intermediate `#cab1.cab` under `installer\obj` even when the cabinet is embedded in the MSI.
- The builder now verifies the final MSI `Media` table directly through Windows Installer.
- The build only passes when every cabinet reference begins with `#`, which denotes an embedded cabinet stream.
- DeckReady release version remains **a1.07.0**.

# DeckReady Windows Changelog
- Fixed the Windows MSI builder to let WiX use its native output directory and copy the verified MSI into `release\msi`, avoiding unreliable OutputPath overrides.

## Alpha a1.07.0

### Added
- Help → DeckReady on GitHub.
- Help → DeckReady Discord.
- Help → Report an Issue.
- WiX Toolset 6 MSI installer project.
- `Build Windows MSI.bat` for creating a self-contained EXE and MSI.
- Start Menu shortcut in MSI installs.

### Changed
- Updated Windows release version to Alpha a1.07.0.
- Updated file/assembly version to 1.7.0.
- Installer packaging hotfix: the human-readable `a1.07.0` label is no longer passed to MSBuild/NuGet as the project version.
- MSI builder now stops on any failed publish/WiX step and verifies the final `.msi` exists before reporting success.
- MSI validation hotfix: separated the per-machine executable from the per-user Start Menu shortcut and added an HKCU registry KeyPath, resolving WiX ICE43/ICE57 validation errors.

## Alpha a1.06
- Reworked the WPF menu chrome to remove the default light/white menu borders.


### Packaging hotfix (a1.07.0)
- MSI output discovery hotfix: the builder now checks WiX 6's `installer\bin\x64\Release` output directly and falls back to a recursive search before copying the installer to `release\msi`.
- Release version remains **a1.07.0**.

### Packaging hotfix (same a1.07.0 version)
- Windows MSI now builds directly into `release\msi` instead of being copied there after the WiX build.
- Added an exact output-file verification so a successful WiX build cannot leave an empty release folder unnoticed.

### Installer builder hotfix (same a1.07.0 release)
- Reworked the MSI build pipeline so MSBuild copies WiX `$(TargetPath)` directly into `release\msi`.
- Removed fragile MSI path-discovery/copy logic from the batch script.
- Added explicit installer builder revision output and stricter MSI verification.

## Windows a1.07.0 - MSI Builder Revision 6

- Fixed Windows Installer asking for a missing `cab1.cab`.
- WiX now embeds the application cabinet directly inside the MSI (`MediaTemplate EmbedCab="yes"`).
- Added a release-build sanity check that rejects any external `.cab` output.
- Public DeckReady version remains `a1.07.0`.
