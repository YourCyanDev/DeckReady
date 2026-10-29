import Foundation
import Combine
import AppKit
import CryptoKit

@MainActor
final class SeratoService: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var isRunning = false
    @Published private(set) var applicationURL: URL?
    @Published private(set) var versionText: String?
    @Published private(set) var statusText = "Checking for Serato…"
    @Published private(set) var proInstalled = false
    @Published private(set) var liteInstalled = false

    private let proPaths = [
        "/Applications/Serato DJ Pro.app",
        "/Applications/Serato DJ.app"
    ]
    private let litePaths = [
        "/Applications/Serato DJ Lite.app"
    ]

    private let defaultColumns: [(String, String)] = [
        ("song", "250"),
        ("artist", "250"),
        ("bpm", "30"),
        ("key", "30"),
        ("album", "250"),
        ("length", "250"),
        ("comment", "250")
    ]

    enum SyncError: LocalizedError {
        case seratoRunning
        case noTracks
        case invalidPath(URL)

        var errorDescription: String? {
            switch self {
            case .seratoRunning:
                return "Serato is open. Quit Serato, then click Retry Serato so DeckReady can safely update its import crate."
            case .noTracks:
                return "There are no tracks to sync to Serato."
            case .invalidPath(let url):
                return "DeckReady couldn't convert this track to a Serato path: \(url.path)"
            }
        }
    }

    func refreshStatus() {
        let proURL = firstExistingURL(in: proPaths)
        let liteURL = firstExistingURL(in: litePaths)
        proInstalled = proURL != nil
        liteInstalled = liteURL != nil
        isInstalled = proInstalled || liteInstalled
        applicationURL = proURL ?? liteURL
        isRunning = !runningSeratoApplications().isEmpty

        if let applicationURL, let bundle = Bundle(url: applicationURL) {
            versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        } else {
            versionText = nil
        }

        if proInstalled && liteInstalled {
            statusText = isRunning ? "Serato DJ Pro / Lite installed • Serato is running" : "Serato DJ Pro and Lite installed"
        } else if proInstalled {
            statusText = isRunning ? "Serato DJ Pro is running" : "Serato DJ Pro installed"
        } else if liteInstalled {
            statusText = isRunning ? "Serato DJ Lite is running" : "Serato DJ Lite installed"
        } else {
            statusText = "Serato DJ Pro / Lite not found in /Applications"
        }
    }

    func launch(preferred: AppSettings.SeratoAppPreference = .automatic) async -> Bool {
        refreshStatus()
        guard let target = applicationURL(for: preferred) else { return false }

        return await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, error in
                Task { @MainActor in
                    self.refreshStatus()
                    continuation.resume(returning: error == nil)
                }
            }
        }
    }

    func effectivePreference(_ requested: AppSettings.SeratoAppPreference) -> AppSettings.SeratoAppPreference {
        if proInstalled && liteInstalled {
            return requested == .automatic ? .pro : requested
        }
        if proInstalled { return .pro }
        if liteInstalled { return .lite }
        return .automatic
    }

    func preferenceSelectorEnabled(openWhenComplete: Bool) -> Bool {
        openWhenComplete && proInstalled && liteInstalled
    }

    func quitAndWait(timeout: TimeInterval = 10) async -> Bool {
        refreshStatus()
        let apps = runningSeratoApplications()
        guard !apps.isEmpty else { return true }

        var accepted = true
        for app in apps {
            accepted = app.terminate() && accepted
        }
        guard accepted else {
            refreshStatus()
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
            refreshStatus()
            if !isRunning { return true }
        }
        refreshStatus()
        return !isRunning
    }

    private func runningSeratoApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let name = app.localizedName else { return false }
            return name.localizedCaseInsensitiveContains("Serato DJ")
        }
    }

    private func firstExistingURL(in paths: [String]) -> URL? {
        paths.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func applicationURL(for preference: AppSettings.SeratoAppPreference) -> URL? {
        let proURL = firstExistingURL(in: proPaths)
        let liteURL = firstExistingURL(in: litePaths)
        switch preference {
        case .pro: return proURL ?? liteURL
        case .lite: return liteURL ?? proURL
        case .automatic: return proURL ?? liteURL
        }
    }

    func syncOrganizedCrates(_ tracks: [(url: URL, metadata: TrackMetadata)],
                             modes: [AppSettings.OrganizationMode], flatName: String) throws -> Int {
        let plan = CrateOrganization.plan(tracks, modes: modes, flatName: flatName)
        for name in plan.keys.sorted() {
            _ = try syncDeckReadyCrate(plan[name] ?? [], crateName: name)
        }
        return plan.count
    }

    func syncDeckReadyCrate(_ urls: [URL], crateName: String) throws -> Int {
        refreshStatus()
        guard !isRunning else { throw SyncError.seratoRunning }
        guard !urls.isEmpty else { throw SyncError.noTracks }

        let grouped = Dictionary(grouping: urls.map(\.standardizedFileURL)) { volumeRoot(for: $0).path }
        var totalTrackCount = 0

        for (_, volumeTracks) in grouped {
            guard let firstTrack = volumeTracks.first else { continue }
            let root = volumeRoot(for: firstTrack)
            let seratoRoot = seratoRoot(forVolumeRoot: root)
            let subcrates = seratoRoot.appendingPathComponent("Subcrates", isDirectory: true)
            let safeCrateName = sanitizeCrateName(crateName)
            let crateURL = subcrates.appendingPathComponent("\(safeCrateName).crate")
            try FileManager.default.createDirectory(at: subcrates, withIntermediateDirectories: true)

            var paths = try existingPaths(in: crateURL)
            for trackURL in volumeTracks {
                guard let relative = seratoRelativePath(for: trackURL, volumeRoot: root) else {
                    throw SyncError.invalidPath(trackURL)
                }
                paths.insert(relative)
            }

            try backupExistingCrate(crateURL, crateName: safeCrateName)
            let data = buildCrateData(trackPaths: paths.sorted())
            try data.write(to: crateURL, options: .atomic)
            totalTrackCount += paths.count
        }
        return totalTrackCount
    }

    func scanExactDuplicates() async -> [SeratoDuplicateTrack] {
        let references = collectCrateTrackReferences()
        guard !references.isEmpty else { return [] }

        var digestGroups: [String: [(url: URL, crates: Set<String>)]] = [:]
        for (path, crates) in references {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path),
                  let digest = try? sha256Hex(url) else { continue }
            digestGroups[digest, default: []].append((url, crates))
        }

        let metadataService = MetadataService()
        var output: [SeratoDuplicateTrack] = []
        var groupNumber = 1
        for (digest, entries) in digestGroups.sorted(by: { $0.key < $1.key }) {
            let uniqueByPath = Dictionary(grouping: entries, by: { $0.url.standardizedFileURL.path })
            guard uniqueByPath.count > 1 else { continue }
            let groupID = "Duplicate Group \(groupNumber)"
            groupNumber += 1

            for (_, samePathEntries) in uniqueByPath.sorted(by: { $0.key < $1.key }) {
                guard let first = samePathEntries.first else { continue }
                let allCrates = Set(samePathEntries.flatMap { $0.crates })
                let metadata = await metadataService.metadata(for: first.url)
                output.append(SeratoDuplicateTrack(
                    groupID: groupID,
                    fileURL: first.url,
                    metadata: metadata,
                    crateNames: allCrates.sorted(),
                    copyCount: uniqueByPath.count,
                    sha256: digest
                ))
            }
        }
        return output
    }

    private func collectCrateTrackReferences() -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for location in seratoLibraryLocations() {
            let subcrates = location.seratoRoot.appendingPathComponent("Subcrates", isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: subcrates,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let crateURL as URL in enumerator where crateURL.pathExtension.lowercased() == "crate" {
                guard let data = try? Data(contentsOf: crateURL) else { continue }
                let crateName = crateURL.deletingPathExtension().lastPathComponent
                for relative in crateTrackPaths(in: data) {
                    guard let fileURL = resolveSeratoPath(relative, volumeRoot: location.volumeRoot) else { continue }
                    result[fileURL.standardizedFileURL.path, default: []].insert(crateName)
                }
            }
        }
        return result
    }

    private func seratoLibraryLocations() -> [(seratoRoot: URL, volumeRoot: URL)] {
        var locations: [(URL, URL)] = []
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music", isDirectory: true)
            .appendingPathComponent("_Serato_", isDirectory: true)
        if FileManager.default.fileExists(atPath: local.path) {
            locations.append((local, URL(fileURLWithPath: "/", isDirectory: true)))
        }

        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let mounted = (try? FileManager.default.contentsOfDirectory(at: volumes, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for volume in mounted {
            let root = volume.appendingPathComponent("_Serato_", isDirectory: true)
            if FileManager.default.fileExists(atPath: root.path) {
                locations.append((root, volume))
            }
        }
        return locations
    }

    private func crateTrackPaths(in data: Data) -> [String] {
        var paths: [String] = []
        for record in records(in: data) where record.tag == "otrk" {
            for nested in records(in: record.payload) where nested.tag == "ptrk" {
                if let path = String(data: nested.payload, encoding: .utf16BigEndian), !path.isEmpty {
                    paths.append(path)
                }
            }
        }
        return paths
    }

    private func resolveSeratoPath(_ relative: String, volumeRoot: URL) -> URL? {
        let clean = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.isEmpty else { return nil }
        if volumeRoot.path == "/" { return URL(fileURLWithPath: "/" + clean) }
        return volumeRoot.appendingPathComponent(clean)
    }

    private func sha256Hex(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func volumeRoot(for url: URL) -> URL {
        let components = url.standardizedFileURL.pathComponents
        if components.count >= 3, components[1] == "Volumes" {
            return URL(fileURLWithPath: "/Volumes/\(components[2])", isDirectory: true)
        }
        return URL(fileURLWithPath: "/", isDirectory: true)
    }

    private func seratoRoot(forVolumeRoot volumeRoot: URL) -> URL {
        if volumeRoot.path == "/" {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music", isDirectory: true)
                .appendingPathComponent("_Serato_", isDirectory: true)
        }
        return volumeRoot.appendingPathComponent("_Serato_", isDirectory: true)
    }

    private func seratoRelativePath(for trackURL: URL, volumeRoot: URL) -> String? {
        let trackPath = trackURL.standardizedFileURL.path
        let rootPath = volumeRoot.standardizedFileURL.path
        if rootPath == "/" { return String(trackPath.drop(while: { $0 == "/" })) }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard trackPath.hasPrefix(prefix) else { return nil }
        return String(trackPath.dropFirst(prefix.count))
    }

    private func sanitizeCrateName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "DeckReady Imports" : trimmed
        let illegal = CharacterSet(charactersIn: "/:\\")
        let cleaned = base.components(separatedBy: illegal).joined(separator: "-")
        return cleaned.isEmpty ? "DeckReady Imports" : cleaned
    }

    private func backupExistingCrate(_ crateURL: URL, crateName: String) throws {
        guard FileManager.default.fileExists(atPath: crateURL.path) else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeckReady", isDirectory: true)
            .appendingPathComponent("Serato Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(crateName)-\(formatter.string(from: Date()))-\(UUID().uuidString).crate"
        try FileManager.default.copyItem(at: crateURL, to: support.appendingPathComponent(name))
    }

    private func buildCrateData(trackPaths: [String]) -> Data {
        var result = Data()
        result.append(tlvText(tag: "vrsn", text: "1.0/Serato ScratchLive Crate"))
        for (name, width) in defaultColumns {
            var column = Data()
            column.append(tlvText(tag: "tvcn", text: name))
            column.append(tlvText(tag: "tvcw", text: width))
            result.append(tlv(tag: "ovct", payload: column))
        }
        for path in trackPaths {
            result.append(tlv(tag: "otrk", payload: tlvText(tag: "ptrk", text: path)))
        }
        return result
    }

    private func existingPaths(in crateURL: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: crateURL.path) else { return [] }
        return Set(crateTrackPaths(in: try Data(contentsOf: crateURL)))
    }

    private func tlvText(tag: String, text: String) -> Data {
        tlv(tag: tag, payload: text.data(using: .utf16BigEndian) ?? Data())
    }

    private func tlv(tag: String, payload: Data) -> Data {
        var data = Data(tag.utf8.prefix(4))
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    private func records(in data: Data) -> [(tag: String, payload: Data)] {
        var output: [(String, Data)] = []
        var offset = 0
        while offset + 8 <= data.count {
            let tagData = data.subdata(in: offset..<(offset + 4))
            guard let tag = String(data: tagData, encoding: .ascii) else { break }
            let lengthBytes = data[(offset + 4)..<(offset + 8)]
            let length = lengthBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            offset += 8
            let payloadLength = Int(length)
            guard offset + payloadLength <= data.count else { break }
            output.append((tag, data.subdata(in: offset..<(offset + payloadLength))))
            offset += payloadLength
        }
        return output
    }
}
