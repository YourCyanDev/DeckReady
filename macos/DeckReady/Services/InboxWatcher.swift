import Foundation
import Combine
import Darwin

@MainActor
final class InboxWatcher: ObservableObject {
    @Published private(set) var isWatching = false
    @Published private(set) var statusText = "Not configured"

    private weak var settings: AppSettings?
    private weak var importer: ImportService?
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    func configure(settings: AppSettings, importer: ImportService) {
        self.settings = settings
        self.importer = importer

        cancellables.removeAll()
        settings.$inboxFolder
            .combineLatest(settings.$automaticInboxImport, settings.$libraryFolder)
            .sink { [weak self] _, _, _ in
                Task { @MainActor [weak self] in
                    self?.restart()
                }
            }
            .store(in: &cancellables)

        restart()
    }

    func restart() {
        stop()
        guard let settings else { return }

        guard settings.automaticInboxImport else {
            statusText = "Automatic import is off"
            return
        }
        guard settings.libraryFolder != nil else {
            statusText = "Choose Library first"
            return
        }
        guard settings.inboxConfigurationError == nil else {
            statusText = "Inbox conflicts with Library"
            return
        }
        guard let folder = settings.inboxFolder else {
            statusText = "No Inbox selected"
            return
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            statusText = "Could not create Inbox"
            return
        }

        fileDescriptor = open(folder.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            statusText = "Could not watch Inbox"
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        newSource.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleScan(delayNanoseconds: 1_500_000_000)
            }
        }
        source = newSource
        newSource.resume()
        isWatching = true
        statusText = "Watching"

        // Anything placed in the Inbox while DeckReady was closed is processed on launch.
        scheduleScan(delayNanoseconds: 600_000_000)
    }

    func scanNow() {
        scheduleScan(delayNanoseconds: 0)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        isWatching = false
    }

    private func scheduleScan(delayNanoseconds: UInt64) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.runScan()
        }
    }

    private func runScan() async {
        guard let settings, let importer, settings.automaticInboxImport,
              settings.inboxConfigurationError == nil,
              let folder = settings.inboxFolder else { return }

        statusText = "Scanning…"
        await importer.processInbox(folder: folder, removeAfterImport: settings.removeInboxItemsAfterImport)
        statusText = isWatching ? "Watching" : "Not watching"
    }

}
