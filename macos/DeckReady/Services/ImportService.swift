import Foundation
import Combine
import CryptoKit
import AppKit

@MainActor
final class ImportService: ObservableObject {
    @Published var items: [ImportItem] = []
    @Published var recentImports: [ImportHistoryRecord] = []
    @Published var duplicateHistory: [ImportHistoryRecord] = []
    @Published var isBusy = false
    @Published var libraryOrganizationStatus = ""
    @Published var activityLog: [String] = []
    @Published var lastError: String?
    @Published var showSeratoRestartPrompt = false
    @Published var showSeratoSyncSuccessPrompt = false
    @Published var seratoSyncSuccessMessage = ""

    private let metadataService = MetadataService()
    private let zipService = ZipService()
    private weak var settings: AppSettings?
    private weak var serato: SeratoService?
    private var temporaryFolders: [URL] = []
    private var cleanupBlockedSourcePaths: Set<String> = []
    private var processedInboxSignatures: [String: String] = [:]

    private let supportedAudioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "wave", "aiff", "aif", "flac", "aac"
    ]

    private struct DiscoveredTrack {
        let url: URL
        let cameFromArchive: Bool
        let sourceContainerURL: URL?
        let sourceContainerKind: SourceContainerKind?
    }

    init() {
        loadHistory()
        loadInboxState()
    }

    func configure(settings: AppSettings, serato: SeratoService) {
        self.settings = settings
        self.serato = serato
    }

    func organizeLibrary() async {
        guard !isBusy, let settings, let serato, let root = settings.libraryFolder else { return }
        isBusy = true
        libraryOrganizationStatus = "Finding library audio files…"
        defer { isBusy = false; libraryOrganizationStatus = "" }
        let modes = settings.activeOrganizationModes
        let flatName = settings.normalizedSeratoCrateName
        do {
            let urls = try await Task.detached { try LibraryCrateScan.discover(in: root) }.value
            guard !urls.isEmpty else { lastError = "No supported audio files were found in the Music Library folder."; return }
            var tracks: [(url: URL, metadata: TrackMetadata)] = []
            for (index, url) in urls.enumerated() {
                if index % 25 == 0 { libraryOrganizationStatus = "Reading tags: \(index + 1) of \(urls.count)…" }
                // Read actual files, regardless of DeckReady import history or active view filters.
                tracks.append((url, await metadataService.metadata(for: url)))
            }
            let plan = CrateOrganization.plan(tracks, modes: modes, flatName: flatName)
            let reviewCount = plan["need tag editing"]?.count ?? 0
            let preview = NSAlert()
            preview.messageText = "Organize Library"
            preview.informativeText = "\(urls.count) songs in \(root.path) will be added to \(plan.count) crates.\n\nOrganize by: \(modes.map(\.rawValue).joined(separator: " + "))\nNeed tag editing: \(reviewCount)\n\nAudio files will stay in place. Existing crate tracks are retained. This processes the full folder, including songs DeckReady did not import."
            preview.addButton(withTitle: "Update Crates")
            preview.addButton(withTitle: "Cancel")
            guard preview.runModal() == .alertFirstButtonReturn else { return }
            serato.refreshStatus()
            let wasRunning = serato.isRunning
            if wasRunning {
                let close = NSAlert()
                close.messageText = "Close Serato to update crates"
                close.informativeText = "DeckReady needs Serato closed while it updates the library crates."
                close.addButton(withTitle: "Quit Serato & Organize")
                close.addButton(withTitle: "Cancel")
                guard close.runModal() == .alertFirstButtonReturn else { return }
                guard await serato.quitAndWait() else { lastError = "Serato is still open. Close it and try Organize Library again."; return }
            }
            libraryOrganizationStatus = "Updating library crates…"
            let count = try serato.syncOrganizedCrates(tracks, modes: modes, flatName: flatName)
            markHistorySynced(urls)
            log("Organized \(urls.count) existing library songs into \(count) crates without changing audio files.")
            if wasRunning && settings.launchSeratoWhenNeeded { _ = await serato.launch(preferred: settings.preferredSeratoApp) }
            seratoSyncSuccessMessage = "Organized \(urls.count) existing songs into \(count) crates. Audio files were left in place."
            showSeratoSyncSuccessPrompt = true
        } catch { lastError = "Could not organize the library: \(error.localizedDescription)" }
    }

    func add(urls: [URL]) {
        Task { _ = await scan(urls: urls) }
    }

    func processInbox(folder: URL, removeAfterImport: Bool) async {
        if isBusy {
            log("Inbox scan deferred because DeckReady is busy.")
            return
        }
        guard settings?.inboxConfigurationError == nil else {
            lastError = settings?.inboxConfigurationError
            return
        }

        let candidates = inboxCandidates(in: folder)
        guard !candidates.isEmpty else { return }

        let firstSignatures: [(url: URL, signature: String)] = candidates.compactMap { url in
            guard let signature = try? sourceSignature(url) else { return nil }
            return (url, signature)
        }
        // Wait once for the whole batch so large drops do not add ~1 second per item.
        try? await Task.sleep(nanoseconds: 900_000_000)

        var stableCandidates: [(url: URL, signature: String)] = []
        for first in firstSignatures {
            let url = first.url
            guard FileManager.default.fileExists(atPath: url.path),
                  let second = try? sourceSignature(url),
                  first.signature == second else {
                log("Inbox item is still being copied; waiting for the next scan: \(url.lastPathComponent)")
                continue
            }
            if processedInboxSignatures[url.standardizedFileURL.path] == second { continue }
            stableCandidates.append((url, second))
        }
        guard !stableCandidates.isEmpty else { return }

        log("Inbox detected \(stableCandidates.count) new item\(stableCandidates.count == 1 ? "" : "s").")
        let newIDs = await scan(urls: stableCandidates.map { $0.url })
        guard !newIDs.isEmpty else { return }
        await performImport(only: Set(newIDs))

        let successStates: Set<ImportState> = [.imported, .duplicate, .waitingForSerato]
        for candidate in stableCandidates {
            let path = candidate.url.standardizedFileURL.path
            let related = items.filter { item in
                item.sourceURL.standardizedFileURL.path == path ||
                item.sourceContainerURL?.standardizedFileURL.path == path
            }
            guard !related.isEmpty, related.allSatisfy({ successStates.contains($0.state) }) else { continue }

            if removeAfterImport {
                if FileManager.default.fileExists(atPath: candidate.url.path) {
                    do {
                        try FileManager.default.removeItem(at: candidate.url)
                        log("Removed imported Inbox item: \(candidate.url.lastPathComponent)")
                    } catch {
                        log("Could not remove Inbox item \(candidate.url.lastPathComponent): \(error.localizedDescription)")
                        processedInboxSignatures[path] = candidate.signature
                    }
                }
            } else {
                processedInboxSignatures[path] = candidate.signature
            }
        }
        persistInboxState()
    }

    func clearCompleted() {
        let removed = items.filter { [.imported, .duplicate, .failed].contains($0.state) }
        blockAutomaticCleanup(for: removed)
        items.removeAll { [.imported, .duplicate, .failed].contains($0.state) }
        cleanupUnusedTemporaryFolders()
    }

    func removeItem(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            blockAutomaticCleanup(for: [item])
        }
        items.removeAll { $0.id == id }
        cleanupUnusedTemporaryFolders()
    }

    func clearRecentHistory() {
        recentImports.removeAll()
        persistHistory()
    }

    func clearDuplicateHistory() {
        duplicateHistory.removeAll()
        persistHistory()
    }

    func importReadyItems() {
        Task { await performImport() }
    }

    func updateMetadata(for id: UUID, metadata: TrackMetadata) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        if settings?.writeMetadataToFiles == true {
            let targetURL = items[index].destinationURL ?? items[index].sourceURL
            do {
                try metadataService.write(metadata: metadata, to: targetURL)
                items[index].metadata = metadata
                items[index].statusMessage = items[index].destinationURL != nil
                    ? "Stored • tags saved"
                    : "Ready • tags saved"
                log("Tags saved safely: \(targetURL.lastPathComponent)")
            } catch {
                lastError = error.localizedDescription
                items[index].statusMessage = items[index].destinationURL != nil
                    ? "Stored • tag update failed"
                    : "Ready • tag update failed"
                log("Tag update failed: \(targetURL.lastPathComponent) — \(error.localizedDescription)")
            }
            return
        }

        items[index].metadata = metadata
        items[index].statusMessage = items[index].destinationURL != nil
            ? "Stored • DeckReady metadata edited"
            : "Ready • DeckReady metadata edited"
    }

    func updateHistoryMetadata(for id: UUID, duplicate: Bool, metadata: TrackMetadata) {
        let record: ImportHistoryRecord?
        if duplicate {
            record = duplicateHistory.first(where: { $0.id == id })
        } else {
            record = recentImports.first(where: { $0.id == id })
        }
        guard let record else { return }

        if settings?.writeMetadataToFiles == true {
            do {
                try metadataService.write(metadata: metadata, to: record.fileURL)
            } catch {
                lastError = error.localizedDescription
                log("Tag update failed: \(record.fileURL.lastPathComponent) — \(error.localizedDescription)")
                return
            }
        }

        if duplicate, let index = duplicateHistory.firstIndex(where: { $0.id == id }) {
            duplicateHistory[index].metadata = metadata
        } else if !duplicate, let index = recentImports.firstIndex(where: { $0.id == id }) {
            recentImports[index].metadata = metadata
        }
        persistHistory()
        log("Updated metadata: \(record.fileURL.lastPathComponent)")
    }

    func retrySerato() {
        Task {
            let waiting = waitingSeratoURLs()
            guard !waiting.isEmpty else { return }
            await syncToSerato(waiting)
        }
    }

    func deferSeratoRestart() {
        showSeratoRestartPrompt = false
        log("Serato restart deferred. Pending tracks remain queued for Serato sync.")
    }

    func quitSeratoAndSync(reopenAfterSync: Bool) {
        showSeratoRestartPrompt = false
        Task { await quitSeratoAndSyncNow(reopenAfterSync: reopenAfterSync) }
    }

    private func waitingSeratoURLs() -> [URL] {
        items.compactMap { item -> URL? in
            item.state == .waitingForSerato ? item.destinationURL : nil
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func scan(urls: [URL]) async -> [UUID] {
        guard !isBusy else { return [] }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        log("Scanning \(urls.count) dropped item\(urls.count == 1 ? "" : "s")…")

        var discovered: [DiscoveredTrack] = []
        for url in urls {
            do {
                discovered.append(contentsOf: try expand(url: url))
            } catch {
                lastError = error.localizedDescription
                log("Error: \(error.localizedDescription)")
            }
        }

        if discovered.isEmpty {
            log("No supported audio files found.")
            return []
        }

        let existingPaths = Set(items.map { $0.sourceURL.standardizedFileURL.path })
        let uniqueDiscovered = discovered.filter { !existingPaths.contains($0.url.standardizedFileURL.path) }
        var addedIDs: [UUID] = []

        for discoveredTrack in uniqueDiscovered {
            let url = discoveredTrack.url
            let archived = discoveredTrack.cameFromArchive
            var item = ImportItem(
                sourceURL: url,
                cameFromArchive: archived,
                sourceContainerURL: discoveredTrack.sourceContainerURL,
                sourceContainerKind: discoveredTrack.sourceContainerKind
            )
            item.state = .scanning
            item.statusMessage = "Reading metadata"
            items.append(item)
            let id = item.id
            addedIDs.append(id)

            let metadata = await metadataService.metadata(for: url)
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].metadata = metadata
            items[index].state = .ready
            items[index].statusMessage = archived ? "Ready • extracted from ZIP" : "Ready"
        }

        if uniqueDiscovered.count != discovered.count {
            log("Skipped \(discovered.count - uniqueDiscovered.count) track\(discovered.count - uniqueDiscovered.count == 1 ? "" : "s") already in the queue.")
        }
        log("Found \(uniqueDiscovered.count) new supported track\(uniqueDiscovered.count == 1 ? "" : "s").")
        return addedIDs
    }

    private func expand(url: URL) throws -> [DiscoveredTrack] {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

        if values.isDirectory == true {
            return try scanDirectory(
                url,
                cameFromArchive: false,
                sourceContainerURL: url,
                sourceContainerKind: .folder
            )
        }

        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            let extracted = try zipService.extract(url)
            temporaryFolders.append(extracted)
            log("Extracted \(url.lastPathComponent)")
            return try scanDirectory(
                extracted,
                cameFromArchive: true,
                sourceContainerURL: url,
                sourceContainerKind: .zip
            )
        }

        guard supportedAudioExtensions.contains(ext) else { return [] }
        return [DiscoveredTrack(
            url: url,
            cameFromArchive: false,
            sourceContainerURL: nil,
            sourceContainerKind: nil
        )]
    }

    private func scanDirectory(
        _ directory: URL,
        cameFromArchive: Bool,
        sourceContainerURL: URL?,
        sourceContainerKind: SourceContainerKind?
    ) throws -> [DiscoveredTrack] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [DiscoveredTrack] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains("__MACOSX") { continue }
            let ext = fileURL.pathExtension.lowercased()
            if supportedAudioExtensions.contains(ext) {
                result.append(DiscoveredTrack(
                    url: fileURL,
                    cameFromArchive: cameFromArchive,
                    sourceContainerURL: sourceContainerURL,
                    sourceContainerKind: sourceContainerKind
                ))
            }
        }
        return result.sorted {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    private func performImport(only itemIDs: Set<UUID>? = nil) async {
        guard !isBusy else { return }
        guard let settings, let libraryFolder = settings.libraryFolder else {
            lastError = "Choose a Music Storage Location in Settings before importing."
            return
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        } catch {
            lastError = "Couldn't create the library folder: \(error.localizedDescription)"
            return
        }

        let readyIDs = items.filter { item in
            item.state == .ready && (itemIDs.map { $0.contains(item.id) } ?? true)
        }.map(\.id)
        if readyIDs.isEmpty { return }

        log("Importing \(readyIDs.count) track\(readyIDs.count == 1 ? "" : "s")…")
        var importedURLs: [URL] = []

        for id in readyIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].state = .importing
            items[index].statusMessage = "Checking for duplicates"

            do {
                // Detect exact duplicates anywhere inside the configured library,
                // not only files that happen to share the same filename.
                if let duplicateURL = try findExactDuplicate(of: items[index].sourceURL, inside: libraryFolder) {
                    items[index].destinationURL = duplicateURL

                    if settings.writeMetadataToFiles {
                        items[index].statusMessage = "Writing metadata"
                        try metadataService.write(metadata: items[index].metadata, to: duplicateURL)
                    }

                    items[index].state = .duplicate
                    items[index].statusMessage = settings.writeMetadataToFiles
                        ? "Already stored • tags saved • ready for Serato"
                        : "Already stored • ready for Serato"
                    importedURLs.append(duplicateURL)
                    recordHistory(for: items[index], duplicate: true)
                    log("Exact duplicate skipped: \(items[index].sourceURL.lastPathComponent)")
                    continue
                }

                let destinationFolder = destinationFolder(for: items[index], root: libraryFolder, mode: settings.organizationMode)
                try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

                let proposed = destinationFolder.appendingPathComponent(items[index].sourceURL.lastPathComponent)
                let finalDestination = uniqueDestination(for: proposed)
                items[index].statusMessage = settings.importMode == .copy ? "Copying" : "Moving"

                if settings.importMode == .move && !items[index].cameFromArchive {
                    try FileManager.default.moveItem(at: items[index].sourceURL, to: finalDestination)
                } else {
                    try FileManager.default.copyItem(at: items[index].sourceURL, to: finalDestination)
                }

                items[index].destinationURL = finalDestination

                if settings.writeMetadataToFiles {
                    items[index].statusMessage = "Writing metadata"
                    try metadataService.write(metadata: items[index].metadata, to: finalDestination)
                    log("Metadata saved into file: \(finalDestination.lastPathComponent)")
                }

                items[index].state = .imported
                items[index].statusMessage = settings.writeMetadataToFiles
                    ? "Stored • tags saved"
                    : "Stored in DeckReady library"
                importedURLs.append(finalDestination)
                recordHistory(for: items[index], duplicate: false)
                log("Imported: \(finalDestination.lastPathComponent)")
            } catch {
                items[index].state = .failed
                items[index].statusMessage = error.localizedDescription
                log("Failed: \(items[index].sourceURL.lastPathComponent) — \(error.localizedDescription)")
            }
        }

        guard !importedURLs.isEmpty else { return }

        if settings.automaticSeratoImport {
            await syncToSerato(importedURLs)
        }
        cleanupSuccessfulSourceContainers()
        cleanupUnusedTemporaryFolders()
    }

    private func blockAutomaticCleanup(for removedItems: [ImportItem]) {
        for item in removedItems {
            if let sourcePath = item.sourceContainerURL?.standardizedFileURL.path {
                cleanupBlockedSourcePaths.insert(sourcePath)
            }
        }
    }

    private func cleanupSuccessfulSourceContainers() {
        guard settings?.deleteSourceContainerAfterImport == true else { return }
        guard let libraryFolder = settings?.libraryFolder?.standardizedFileURL else { return }

        let candidates = Dictionary(grouping: items.compactMap { item -> ImportItem? in
            item.sourceContainerURL == nil ? nil : item
        }) { item in
            item.sourceContainerURL!.standardizedFileURL.path
        }

        for (_, sourceItems) in candidates {
            guard let containerURL = sourceItems.first?.sourceContainerURL?.standardizedFileURL,
                  let kind = sourceItems.first?.sourceContainerKind else { continue }

            let successStates: Set<ImportState> = [.imported, .duplicate, .waitingForSerato]
            guard sourceItems.allSatisfy({ successStates.contains($0.state) }) else { continue }

            // Never allow cleanup to remove the configured library itself or a parent folder containing it.
            let containerPath = containerURL.path.hasSuffix("/") ? containerURL.path : containerURL.path + "/"
            let libraryPath = libraryFolder.path.hasSuffix("/") ? libraryFolder.path : libraryFolder.path + "/"
            if containerURL.path == libraryFolder.path || libraryPath.hasPrefix(containerPath) {
                log("Source cleanup skipped for safety: \(containerURL.path)")
                continue
            }

            if cleanupBlockedSourcePaths.contains(containerURL.path) {
                log("Source cleanup skipped because an item from that source was removed from the queue: \(containerURL.lastPathComponent)")
                continue
            }

            if let inbox = settings?.inboxFolder?.standardizedFileURL {
                let inboxPath = inbox.path.hasSuffix("/") ? inbox.path : inbox.path + "/"
                if containerURL.path.hasPrefix(inboxPath) {
                    // Inbox cleanup has its own setting and runs after the automatic batch finishes.
                    continue
                }
            }

            guard FileManager.default.fileExists(atPath: containerURL.path) else { continue }
            do {
                try FileManager.default.removeItem(at: containerURL)
                log("Deleted original \(kind.rawValue.lowercased()): \(containerURL.lastPathComponent)")
            } catch {
                log("Could not delete original \(kind.rawValue.lowercased()) \(containerURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func syncToSerato(_ urls: [URL]) async {
        guard let serato else { return }
        serato.refreshStatus()

        guard serato.isInstalled else {
            markWaiting(urls, message: "Stored • Serato is not installed or was not detected")
            return
        }

        if serato.isRunning {
            markWaiting(urls, message: "Stored • Serato restart required to apply crate changes")
            showSeratoRestartPrompt = true
            log("Tracks are saved, but Serato must restart before DeckReady can safely apply the crate changes.")
            return
        }

        // Serato was already closed when this sync began, so do not launch it.
        // DeckReady only reopens Serato when it was running and DeckReady had to quit it first.
        await writeSeratoCrate(urls, launchAfterSync: false)
    }

    private func quitSeratoAndSyncNow(reopenAfterSync: Bool) async {
        guard let serato else { return }
        let waiting = waitingSeratoURLs()
        guard !waiting.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }

        log("Requesting Serato to quit so pending crate changes can be applied…")
        let didQuit = await serato.quitAndWait()
        guard didQuit else {
            lastError = "Serato didn't finish quitting. If Serato is showing a save or confirmation window, finish that first, then click Retry Serato."
            log("Serato did not finish quitting; pending tracks were left untouched.")
            return
        }

        await writeSeratoCrate(waiting, launchAfterSync: reopenAfterSync)
    }

    private func writeSeratoCrate(_ urls: [URL], launchAfterSync: Bool) async {
        guard let settings, let serato else { return }

        do {
            let modes = settings.activeOrganizationModes
            let nested = modes.contains(.yearArtist) || modes.contains(.genreArtist)
            var tracks: [(url: URL, metadata: TrackMetadata)] = []
            for url in urls {
                let key = url.standardizedFileURL
                let metadata: TrackMetadata
                if let queued = items.last(where: { $0.activeURL.standardizedFileURL == key }) {
                    metadata = queued.metadata
                } else if let recent = recentImports.first(where: { $0.fileURL.standardizedFileURL == key }) {
                    metadata = recent.metadata
                } else {
                    metadata = await metadataService.metadata(for: url)
                }
                tracks.append((url, metadata))
            }
            let crateName = nested ? "selected crates (including need tag editing when needed)" : settings.normalizedSeratoCrateName
            let crateCount = try serato.syncOrganizedCrates(tracks, modes: modes, flatName: settings.normalizedSeratoCrateName)
            for index in items.indices where items[index].destinationURL.map(urls.contains) == true {
                items[index].state = items[index].state == .duplicate ? .duplicate : .imported
                items[index].statusMessage = "Stored • synced to \(crateName)"
            }
            markHistorySynced(urls)
            log("Synced \(urls.count) tracks across \(crateCount) Serato crates.")

            let syncedTrackCount = Set(urls.map { $0.standardizedFileURL.path }).count
            var reopenedSerato = false
            if launchAfterSync {
                log("Reopening Serato…")
                reopenedSerato = await serato.launch(preferred: settings.preferredSeratoApp)
            }

            let noun = syncedTrackCount == 1 ? "track" : "tracks"
            seratoSyncSuccessMessage = "\(syncedTrackCount) \(noun) successfully imported into the Serato crate ‘\(crateName)’."
            if launchAfterSync {
                seratoSyncSuccessMessage += reopenedSerato
                    ? " Serato has been reopened."
                    : " The crate was updated, but DeckReady could not reopen Serato automatically."
            }
            showSeratoSyncSuccessPrompt = true

            // Make sure the confirmation is visible even if Serato was just relaunched.
            NSApplication.shared.activate(ignoringOtherApps: true)
        } catch {
            markWaiting(urls, message: "Stored • \(error.localizedDescription)")
        }
    }

    private func markWaiting(_ urls: [URL], message: String) {
        for index in items.indices where items[index].destinationURL.map(urls.contains) == true {
            items[index].state = .waitingForSerato
            items[index].statusMessage = message
        }
        log(message)
    }

    private func destinationFolder(for item: ImportItem, root: URL, mode: AppSettings.OrganizationMode) -> URL {
        CrateOrganization.destination(root: root, metadata: item.metadata, mode: mode)
    }

    private func sanitize(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:")
        return value.components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueDestination(for proposed: URL) -> URL {
        guard FileManager.default.fileExists(atPath: proposed.path) else { return proposed }
        let folder = proposed.deletingLastPathComponent()
        let stem = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private func findExactDuplicate(of source: URL, inside root: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let sourcePath = source.standardizedFileURL.path
        let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let sourceSize else { return nil }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var sourceDigest: SHA256.Digest?
        for case let candidate as URL in enumerator {
            if candidate.standardizedFileURL.path == sourcePath { return candidate }
            guard supportedAudioExtensions.contains(candidate.pathExtension.lowercased()) else { continue }
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, values.fileSize == sourceSize else { continue }
            if sourceDigest == nil { sourceDigest = try sha256(source) }
            if let sourceDigest, try sha256(candidate) == sourceDigest { return candidate }
        }
        return nil
    }

    private func sha256(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize()
    }

    private func inboxCandidates(in folder: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true { return true }
            let ext = url.pathExtension.lowercased()
            return ext == "zip" || supportedAudioExtensions.contains(ext)
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func sourceSignature(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        var components: [String] = []
        if values.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return "folder:empty" }
            for case let file as URL in enumerator {
                let fileValues = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard fileValues.isRegularFile == true else { continue }
                let relative = file.path.replacingOccurrences(of: url.path + "/", with: "")
                let size = fileValues.fileSize ?? 0
                let modified = fileValues.contentModificationDate?.timeIntervalSince1970 ?? 0
                components.append("\(relative)|\(size)|\(modified)")
            }
            components.sort()
        } else {
            components = ["\(url.lastPathComponent)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"]
        }
        let data = Data(components.joined(separator: "\n").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private var inboxStateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeckReady", isDirectory: true)
        return base.appendingPathComponent("inbox-state.json")
    }

    private func loadInboxState() {
        guard let data = try? Data(contentsOf: inboxStateURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        processedInboxSignatures = decoded
    }

    private func persistInboxState() {
        do {
            try FileManager.default.createDirectory(at: inboxStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(processedInboxSignatures)
            try data.write(to: inboxStateURL, options: .atomic)
        } catch {
            log("Could not save Inbox state: \(error.localizedDescription)")
        }
    }

    private func recordHistory(for item: ImportItem, duplicate: Bool) {
        guard let destination = item.destinationURL else { return }
        let record = ImportHistoryRecord(
            metadata: item.metadata,
            fileURL: destination,
            wasDuplicate: duplicate,
            seratoSynced: false
        )
        if duplicate {
            duplicateHistory.insert(record, at: 0)
            if duplicateHistory.count > 300 { duplicateHistory.removeLast(duplicateHistory.count - 300) }
        } else {
            recentImports.insert(record, at: 0)
            if recentImports.count > 500 { recentImports.removeLast(recentImports.count - 500) }
        }
        persistHistory()
    }

    private func markHistorySynced(_ urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        for index in recentImports.indices where paths.contains(recentImports[index].fileURL.standardizedFileURL.path) {
            recentImports[index].seratoSynced = true
        }
        for index in duplicateHistory.indices where paths.contains(duplicateHistory[index].fileURL.standardizedFileURL.path) {
            duplicateHistory[index].seratoSynced = true
        }
        persistHistory()
    }

    private struct HistoryStore: Codable {
        var recent: [ImportHistoryRecord]
        var duplicates: [ImportHistoryRecord]
    }

    private var historyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeckReady", isDirectory: true)
        return base.appendingPathComponent("import-history.json")
    }

    private func loadHistory() {
        do {
            let data = try Data(contentsOf: historyURL)
            let store = try JSONDecoder().decode(HistoryStore.self, from: data)
            recentImports = store.recent
            duplicateHistory = store.duplicates
        } catch {
            recentImports = []
            duplicateHistory = []
        }
    }

    private func persistHistory() {
        do {
            let url = historyURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(HistoryStore(recent: recentImports, duplicates: duplicateHistory))
            try data.write(to: url, options: .atomic)
        } catch {
            log("Could not save import history: \(error.localizedDescription)")
        }
    }

    private func cleanupUnusedTemporaryFolders() {
        let activeSourcePaths = items.map { $0.sourceURL.standardizedFileURL.path }
        temporaryFolders.removeAll { folder in
            let folderPath = folder.standardizedFileURL.path + "/"
            let stillNeeded = activeSourcePaths.contains { $0.hasPrefix(folderPath) }
            if !stillNeeded {
                try? FileManager.default.removeItem(at: folder)
                return true
            }
            return false
        }
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        activityLog.append("[\(formatter.string(from: Date()))] \(message)")
        if activityLog.count > 300 { activityLog.removeFirst(activityLog.count - 300) }
    }
}
