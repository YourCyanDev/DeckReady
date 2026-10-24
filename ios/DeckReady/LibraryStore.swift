import Foundation
import AVFoundation
import CryptoKit
import Combine
import ZIPFoundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var library = Library()
    @Published private(set) var busy = false
    @Published var message: String?
    private let root: URL
    private let fm = FileManager.default
    private var snapshot: URL { root.appendingPathComponent("library.json") }
    var tracks: [Track] { library.tracks }
    var crates: [Crate] { library.crates }

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DeckReady", isDirectory: true)
        do {
            try fm.createDirectory(at: self.root, withIntermediateDirectories: true)
            if fm.fileExists(atPath: snapshot.path) {
                library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: snapshot))
            }
        } catch { message = "Your library could not be loaded. No files were deleted. \(error.localizedDescription)" }
    }

    func fileURL(_ track: Track) -> URL { root.appendingPathComponent(track.filename) }
    private func commit(_ next: Library) throws {
        try JSONEncoder().encode(next).write(to: snapshot, options: .atomic)
        library = next
    }
    func change(_ edit: (inout Library) -> Void) {
        guard !busy else { return }
        var next = library
        edit(&next)
        do { try commit(next) } catch { message = "Could not save: \(error.localizedDescription)" }
    }
    func createCrate(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        change { $0.crates.append(Crate(name: name)) }
    }
    func removeTrack(_ track: Track) {
        guard !busy else { return }
        var next = library
        next.tracks.removeAll { $0.id == track.id }
        for index in next.crates.indices { next.crates[index].trackIDs.removeAll { $0 == track.id } }
        do {
            try commit(next)
            try? fm.removeItem(at: fileURL(track))
        } catch { message = "Could not delete: \(error.localizedDescription)" }
    }
    func toggle(_ track: Track, in crateID: UUID) {
        change { value in
            guard let index = value.crates.firstIndex(where: { $0.id == crateID }) else { return }
            if value.crates[index].trackIDs.contains(track.id) { value.crates[index].trackIDs.removeAll { $0 == track.id } }
            else { value.crates[index].trackIDs.append(track.id) }
        }
    }
    func tracks(in crate: Crate) -> [Track] { crate.trackIDs.compactMap { id in tracks.first { $0.id == id } } }

    func importFiles(_ urls: [URL]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        var added = 0, duplicates = 0, failures: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            do {
                let source: URL
                if url.pathExtension.lowercased() == "zip" {
                    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                    try await Task.detached(priority: .userInitiated) {
                        // ZIPFoundation validates entry paths; symlinks are excluded below.
                        try FileManager.default.unzipItem(at: url, to: staging)
                    }.value
                    source = staging
                } else { source = url }
                var isDirectory: ObjCBool = false
                fm.fileExists(atPath: source.path, isDirectory: &isDirectory)
                let candidates: [URL]
                if isDirectory.boolValue {
                    candidates = (fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])?.allObjects as? [URL] ?? []).sorted { $0.path < $1.path }
                } else { candidates = [source] }
                for candidate in candidates where FileRules.audioExtensions.contains(candidate.pathExtension.lowercased()) {
                    do {
                        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                        let digest = try await Self.hash(candidate)
                        if tracks.contains(where: { $0.digest == digest }) { duplicates += 1; continue }
                        let id = UUID()
                        let filename = id.uuidString + "." + candidate.pathExtension.lowercased()
                        let destination = root.appendingPathComponent(filename)
                        do {
                            try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: candidate, to: destination) }.value
                            let asset = AVURLAsset(url: destination)
                            guard try await asset.load(.isPlayable) else { throw CocoaError(.fileReadCorruptFile) }
                            let metadata = try await asset.load(.commonMetadata)
                            var title = candidate.deletingPathExtension().lastPathComponent, artist = "Unknown artist", album = ""
                            var artwork: Data?
                            for item in metadata {
                                switch item.commonKey {
                                case .commonKeyTitle: if let text = try? await item.load(.stringValue), !text.isEmpty { title = text }
                                case .commonKeyArtist: if let text = try? await item.load(.stringValue), !text.isEmpty { artist = text }
                                case .commonKeyAlbumName: album = (try? await item.load(.stringValue)) ?? ""
                                case .commonKeyArtwork: artwork = try? await item.load(.dataValue)
                                default: break
                                }
                            }
                            let seconds = try await asset.load(.duration).seconds
                            let track = Track(id: id, filename: filename, title: title, artist: artist, album: album, duration: seconds.isFinite ? seconds : 0, digest: digest, artwork: artwork)
                            var next = library; next.tracks.append(track); try commit(next); added += 1
                        } catch { try? fm.removeItem(at: destination); throw error }
                    } catch { failures.append("\(candidate.lastPathComponent): \(error.localizedDescription)") }
                }
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        message = "Imported \(added) tracks. Skipped \(duplicates) exact duplicates." + (failures.isEmpty ? "" : "\n\(failures.count) files failed:\n" + failures.prefix(5).joined(separator: "\n"))
    }
    nonisolated private static func hash(_ url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
