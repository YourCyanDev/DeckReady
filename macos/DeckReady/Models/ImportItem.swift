import Foundation

struct TrackMetadata: Hashable, Codable {
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: String
    var duration: TimeInterval

    static let empty = TrackMetadata(title: "", artist: "", album: "", genre: "", year: "", duration: 0)
}

enum SourceContainerKind: String, Hashable {
    case zip = "ZIP"
    case folder = "Folder"
}

enum ImportState: String, Hashable {
    case queued = "Queued"
    case scanning = "Scanning"
    case ready = "Ready"
    case importing = "Importing"
    case imported = "Imported"
    case duplicate = "Duplicate"
    case failed = "Failed"
    case waitingForSerato = "Waiting for Serato"
}

struct ImportItem: Identifiable, Hashable {
    let id: UUID
    let sourceURL: URL
    var metadata: TrackMetadata
    var state: ImportState
    var statusMessage: String
    var destinationURL: URL?
    var cameFromArchive: Bool
    var sourceContainerURL: URL?
    var sourceContainerKind: SourceContainerKind?

    init(
        sourceURL: URL,
        cameFromArchive: Bool = false,
        sourceContainerURL: URL? = nil,
        sourceContainerKind: SourceContainerKind? = nil
    ) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.metadata = .empty
        self.state = .queued
        self.statusMessage = "Waiting to scan"
        self.destinationURL = nil
        self.cameFromArchive = cameFromArchive
        self.sourceContainerURL = sourceContainerURL
        self.sourceContainerKind = sourceContainerKind
    }

    var displayTitle: String {
        if !metadata.title.isEmpty { return metadata.title }
        return sourceURL.deletingPathExtension().lastPathComponent
    }

    var displayArtist: String {
        metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist
    }

    var activeURL: URL {
        destinationURL ?? sourceURL
    }

    var fileExtension: String {
        activeURL.pathExtension.uppercased()
    }
}

struct ImportHistoryRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var metadata: TrackMetadata
    var filePath: String
    var importedAt: Date
    var wasDuplicate: Bool
    var seratoSynced: Bool

    init(metadata: TrackMetadata, fileURL: URL, importedAt: Date = Date(), wasDuplicate: Bool, seratoSynced: Bool = false) {
        self.id = UUID()
        self.metadata = metadata
        self.filePath = fileURL.path
        self.importedAt = importedAt
        self.wasDuplicate = wasDuplicate
        self.seratoSynced = seratoSynced
    }

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var displayTitle: String {
        metadata.title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : metadata.title
    }
    var displayArtist: String {
        metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist
    }
}


struct LibraryTrack: Identifiable, Hashable {
    let fileURL: URL
    var metadata: TrackMetadata

    var id: String { fileURL.standardizedFileURL.path }
    var displayTitle: String {
        metadata.title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : metadata.title
    }
    var displayArtist: String { metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist }
    var fileExtension: String { fileURL.pathExtension.uppercased() }
}

struct SeratoDuplicateTrack: Identifiable, Hashable {
    let id: UUID
    let groupID: String
    let fileURL: URL
    let metadata: TrackMetadata
    let crateNames: [String]
    let copyCount: Int
    let sha256: String

    init(groupID: String, fileURL: URL, metadata: TrackMetadata, crateNames: [String], copyCount: Int, sha256: String) {
        self.id = UUID()
        self.groupID = groupID
        self.fileURL = fileURL
        self.metadata = metadata
        self.crateNames = crateNames
        self.copyCount = copyCount
        self.sha256 = sha256
    }

    var displayTitle: String {
        metadata.title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : metadata.title
    }
    var displayArtist: String { metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist }
}


/// Shared folder/crate routing. Songs are references inside artist crates, never a third level.
enum CrateOrganization {
    static func plan(_ tracks: [(url: URL, metadata: TrackMetadata)],
                     modes: [AppSettings.OrganizationMode], flatName: String) -> [String: [URL]] {
        var crates: [String: [URL]] = [:]
        var selected: [AppSettings.OrganizationMode] = []
        for mode in modes where !selected.contains(mode) { selected.append(mode) }
        func add(_ name: String, _ url: URL) {
            let normalized = url.standardizedFileURL
            if !(crates[name] ?? []).contains(normalized) { crates[name, default: []].append(normalized) }
        }
        for track in tracks {
            for mode in selected {
                if mode == .yearArtist || mode == .genreArtist {
                    let category = mode == .yearArtist ? track.metadata.year : track.metadata.genre
                    if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        track.metadata.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        add("need tag editing", track.url)
                        continue
                    }
                    let parent = component(category, fallback: mode == .yearArtist ? "Unknown Year" : "Unknown Genre", crate: true)
                    let artist = component(track.metadata.artist, fallback: "Unknown Artist", crate: true)
                    add(parent, track.url)
                    add(parent + "%%" + artist, track.url)
                } else {
                    add(component(flatName, fallback: "DeckReady Imports", crate: false), track.url)
                }
            }
        }
        return crates
    }

    static func destination(root: URL, metadata: TrackMetadata, mode: AppSettings.OrganizationMode) -> URL {
        let components: [(String, String)]
        switch mode {
        case .flat: components = []
        case .artist: components = [(metadata.artist, "Unknown Artist")]
        case .genre: components = [(metadata.genre, "Unknown Genre")]
        case .year: components = [(metadata.year, "Unknown Year")]
        case .yearArtist: components = [(metadata.year, "Unknown Year"), (metadata.artist, "Unknown Artist")]
        case .genreArtist: components = [(metadata.genre, "Unknown Genre"), (metadata.artist, "Unknown Artist")]
        }
        return components.reduce(root) { result, part in
            result.appendingPathComponent(component(part.0, fallback: part.1, crate: false), isDirectory: true)
        }
    }

    private static func component(_ value: String, fallback: String, crate: Bool) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        var result = value.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if crate { result = result.replacingOccurrences(of: "%", with: "-") }
        if result.isEmpty || result == "." || result == ".." { return fallback }
        return result
    }
}
