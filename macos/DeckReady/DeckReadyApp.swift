import SwiftUI
import AppKit

extension Notification.Name {
    static let deckReadyImportMusic = Notification.Name("DeckReady.ImportMusic")
    static let deckReadyImportFolder = Notification.Name("DeckReady.ImportFolder")
    static let deckReadyOpenInbox = Notification.Name("DeckReady.OpenInbox")
    static let deckReadyScanInbox = Notification.Name("DeckReady.ScanInbox")
    static let deckReadyOpenMusicLibrary = Notification.Name("DeckReady.OpenMusicLibrary")
}

@main
struct DeckReadyApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var importer = ImportService()
    @StateObject private var serato = SeratoService()
    @StateObject private var inboxWatcher = InboxWatcher()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(importer)
                .environmentObject(serato)
                .environmentObject(inboxWatcher)
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    importer.configure(settings: settings, serato: serato)
                    inboxWatcher.configure(settings: settings, importer: importer)
                    serato.refreshStatus()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import Music…") {
                    NotificationCenter.default.post(name: .deckReadyImportMusic, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Import Folder…") {
                    NotificationCenter.default.post(name: .deckReadyImportFolder, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()
                Button("Open DeckReady Inbox") {
                    NotificationCenter.default.post(name: .deckReadyOpenInbox, object: nil)
                }
                Button("Scan Inbox Now") {
                    NotificationCenter.default.post(name: .deckReadyScanInbox, object: nil)
                }
                Button("Open Music Library") {
                    NotificationCenter.default.post(name: .deckReadyOpenMusicLibrary, object: nil)
                }
            }

            CommandGroup(replacing: .help) {
                Button("DeckReady on GitHub") {
                    openExternalURL("https://github.com/YourCyanDev/DeckReady")
                }

                Button("DeckReady Discord") {
                    openExternalURL("https://discord.gg/BuVnCQ5fG9")
                }

                Button("Report an Issue") {
                    openExternalURL("https://github.com/YourCyanDev/DeckReady/issues")
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(serato)
                .environmentObject(inboxWatcher)
                .frame(width: 660, height: 650)
        }
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
