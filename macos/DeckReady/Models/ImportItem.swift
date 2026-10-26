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


enum LibrarySort: String, CaseIterable, Identifiable {
    case title = "Title", artist = "Artist", album = "Album", genre = "Genre"
    case year = "Year", duration = "Duration", filename = "Filename"
    var id: String { rawValue }
}

struct LibraryQuery {
    var artist = "", genre = "", year = "", format = "", search = ""
    var sort: LibrarySort = .title
    var ascending = true
    static func tag(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Unknown" : value
    }
    func apply(to tracks: [LibraryTrack]) -> [LibraryTrack] {
        let search = self.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tracks.filter { track in
            (artist.isEmpty || Self.tag(track.metadata.artist) == artist) &&
            (genre.isEmpty || Self.tag(track.metadata.genre) == genre) &&
            (year.isEmpty || Self.tag(track.metadata.year) == year) &&
            (format.isEmpty || track.fileExtension == format) &&
            (search.isEmpty || [track.displayTitle, track.displayArtist, track.metadata.album,
                track.metadata.genre, track.metadata.year, track.fileURL.lastPathComponent]
                .contains { $0.lowercased().contains(search) })
        }.sorted { left, right in
            var order: ComparisonResult
            switch sort {
            case .duration:
                order = left.metadata.duration == right.metadata.duration ? .orderedSame :
                    (left.metadata.duration < right.metadata.duration ? .orderedAscending : .orderedDescending)
            case .year:
                let a = Int(left.metadata.year) ?? 0, b = Int(right.metadata.year) ?? 0
                order = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            default:
                func value(_ track: LibraryTrack) -> String {
                    switch sort {
                    case .title: return track.displayTitle
                    case .artist: return track.displayArtist
                    case .album: return track.metadata.album
                    case .genre: return track.metadata.genre
                    default: return track.fileURL.lastPathComponent
                    }
                }
                order = value(left).localizedStandardCompare(value(right))
            }
            if order == .orderedSame { order = left.fileURL.path.localizedStandardCompare(right.fileURL.path) }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}

enum LibraryCrateScan {
    static func discover(in root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let formats: Set<String> = ["mp3", "m4a", "wav", "wave", "aiff", "aif", "flac", "aac"]
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in
                failure = error
                return false
            }) else { throw CocoaError(.fileReadUnknown) }
        var urls: Set<URL> = []
        for case let url as URL in enumerator {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            // Directory enumeration does not follow symbolic links. Calling skipDescendants
            // for a symlink to a file can skip an unrelated directory that follows it.
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            if formats.contains(url.pathExtension.lowercased()) {
                urls.insert(url.standardizedFileURL)
            }
        }
        if let failure { throw failure }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
