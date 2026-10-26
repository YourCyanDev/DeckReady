import Foundation
import Combine
import AppKit

@MainActor
final class AppSettings: ObservableObject {
    enum SeratoAppPreference: String, CaseIterable, Identifiable {
        case automatic = "Automatic"
        case pro = "Serato DJ Pro"
        case lite = "Serato DJ Lite"
        var id: String { rawValue }
    }

    enum ImportMode: String, CaseIterable, Identifiable {
        case copy = "Copy"
        case move = "Move"
        var id: String { rawValue }
    }

    enum OrganizationMode: String, CaseIterable, Identifiable {
        case flat = "No subfolders"
        case artist = "Artist"
        case genre = "Genre"
        case year = "Year"
        case yearArtist = "Year → Artist (songs inside)"
        case genreArtist = "Genre → Artist (songs inside)"
        var id: String { rawValue }
    }

    @Published var libraryFolder: URL? {
        didSet { persistLibraryFolder() }
    }
    @Published var inboxFolder: URL? {
        didSet { persistInboxFolder() }
    }
    @Published var automaticInboxImport: Bool {
        didSet { defaults.set(automaticInboxImport, forKey: Keys.automaticInboxImport) }
    }
    @Published var removeInboxItemsAfterImport: Bool {
        didSet { defaults.set(removeInboxItemsAfterImport, forKey: Keys.removeInboxItemsAfterImport) }
    }
    @Published var importMode: ImportMode {
        didSet { defaults.set(importMode.rawValue, forKey: Keys.importMode) }
    }
    @Published var organizationMode: OrganizationMode {
        didSet { defaults.set(organizationMode.rawValue, forKey: Keys.organizationMode) }
    }
    @Published var additionalOrganizationModes: [OrganizationMode] {
        didSet { defaults.set(additionalOrganizationModes.map(\.rawValue), forKey: Keys.additionalOrganizationModes) }
    }
    var activeOrganizationModes: [OrganizationMode] {
        var result = [organizationMode]
        for mode in additionalOrganizationModes where !result.contains(mode) { result.append(mode) }
        return result
    }
    var availableAdditionalOrganizationModes: [OrganizationMode] {
        [.yearArtist, .genreArtist].filter { !activeOrganizationModes.contains($0) }
    }
    @Published var automaticSeratoImport: Bool {
        didSet { defaults.set(automaticSeratoImport, forKey: Keys.autoSerato) }
    }
    @Published var launchSeratoWhenNeeded: Bool {
        didSet { defaults.set(launchSeratoWhenNeeded, forKey: Keys.launchSerato) }
    }
    @Published var writeMetadataToFiles: Bool {
        didSet { defaults.set(writeMetadataToFiles, forKey: Keys.writeMetadata) }
    }
    @Published var seratoCrateName: String {
        didSet { defaults.set(seratoCrateName, forKey: Keys.seratoCrateName) }
    }
    @Published var deleteSourceContainerAfterImport: Bool {
        didSet { defaults.set(deleteSourceContainerAfterImport, forKey: Keys.deleteSourceContainerAfterImport) }
    }
    @Published var preferredSeratoApp: SeratoAppPreference {
        didSet { defaults.set(preferredSeratoApp.rawValue, forKey: Keys.preferredSeratoApp) }
    }

    private enum Keys {
        static let libraryFolder = "libraryFolder"
        static let inboxFolder = "inboxFolder"
        static let automaticInboxImport = "automaticInboxImport"
        static let removeInboxItemsAfterImport = "removeInboxItemsAfterImport"
        static let importMode = "importMode"
        static let organizationMode = "organizationMode"
        static let additionalOrganizationModes = "additionalOrganizationModes"
        static let autoSerato = "autoSerato"
        static let launchSerato = "launchSerato"
        static let writeMetadata = "writeMetadata"
        static let seratoCrateName = "seratoCrateName"
        static let deleteSourceContainerAfterImport = "deleteSourceContainerAfterImport"
        static let preferredSeratoApp = "preferredSeratoApp"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Keys.libraryFolder) {
            self.libraryFolder = URL(fileURLWithPath: path)
        } else {
            let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
            self.libraryFolder = music
                .appendingPathComponent("DeckReady", isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
        }

        if let path = defaults.string(forKey: Keys.inboxFolder) {
            self.inboxFolder = URL(fileURLWithPath: path)
        } else {
            let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
            self.inboxFolder = music
                .appendingPathComponent("DeckReady", isDirectory: true)
                .appendingPathComponent("Inbox", isDirectory: true)
        }

        self.automaticInboxImport = defaults.object(forKey: Keys.automaticInboxImport) as? Bool ?? true
        self.removeInboxItemsAfterImport = defaults.object(forKey: Keys.removeInboxItemsAfterImport) as? Bool ?? true
        self.importMode = ImportMode(rawValue: defaults.string(forKey: Keys.importMode) ?? "") ?? .copy
        self.organizationMode = OrganizationMode(rawValue: defaults.string(forKey: Keys.organizationMode) ?? "") ?? .flat
        self.additionalOrganizationModes = (defaults.stringArray(forKey: Keys.additionalOrganizationModes) ?? [])
            .compactMap(OrganizationMode.init(rawValue:))
            .filter { $0 == .yearArtist || $0 == .genreArtist }
        self.automaticSeratoImport = defaults.object(forKey: Keys.autoSerato) as? Bool ?? true
        self.launchSeratoWhenNeeded = defaults.object(forKey: Keys.launchSerato) as? Bool ?? true
        self.writeMetadataToFiles = defaults.object(forKey: Keys.writeMetadata) as? Bool ?? true
        self.seratoCrateName = defaults.string(forKey: Keys.seratoCrateName) ?? "DeckReady Imports"
        self.deleteSourceContainerAfterImport = defaults.object(forKey: Keys.deleteSourceContainerAfterImport) as? Bool ?? false
        self.preferredSeratoApp = SeratoAppPreference(rawValue: defaults.string(forKey: Keys.preferredSeratoApp) ?? "") ?? .automatic

        if let libraryFolder { try? FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true) }
        if let inboxFolder { try? FileManager.default.createDirectory(at: inboxFolder, withIntermediateDirectories: true) }
    }

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose DeckReady Music Library"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            libraryFolder = panel.url
        }
    }

    func chooseInboxFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose DeckReady Inbox"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            inboxFolder = panel.url
        }
    }

    func revealLibraryFolder() {
        guard let libraryFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([libraryFolder])
    }

    func revealInboxFolder() {
        guard let inboxFolder else { return }
        try? FileManager.default.createDirectory(at: inboxFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([inboxFolder])
    }

    var normalizedSeratoCrateName: String {
        let trimmed = seratoCrateName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "DeckReady Imports" : trimmed
    }

    var inboxConfigurationError: String? {
        guard let inbox = inboxFolder?.standardizedFileURL,
              let library = libraryFolder?.standardizedFileURL else { return nil }

        let inboxPath = normalizedDirectoryPath(inbox.path)
        let libraryPath = normalizedDirectoryPath(library.path)
        if inboxPath == libraryPath || inboxPath.hasPrefix(libraryPath) || libraryPath.hasPrefix(inboxPath) {
            return "The DeckReady Inbox and Music Library must be separate folders and cannot be inside one another."
        }
        return nil
    }

    private func normalizedDirectoryPath(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private func persistLibraryFolder() {
        defaults.set(libraryFolder?.path, forKey: Keys.libraryFolder)
    }

    private func persistInboxFolder() {
        defaults.set(inboxFolder?.path, forKey: Keys.inboxFolder)
    }
}
