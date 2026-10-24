import Foundation

struct Track: Codable, Identifiable, Equatable {
    var id: UUID
    var filename: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var digest: String
    var artwork: Data?
}

struct Crate: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var trackIDs: [UUID] = []
}

struct Library: Codable {
    var tracks: [Track] = []
    var crates: [Crate] = []
}

enum FileRules {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aif", "aiff", "flac", "aac", "mp4"]
    static func safeName(_ input: String) -> String {
        let cleaned = input.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\0")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "Crate" : String(cleaned.prefix(100))
    }
    static func exportName(index: Int, track: Track) -> String {
        String(format: "%03d", index + 1) + " - " + safeName(track.title) + "." + URL(fileURLWithPath: track.filename).pathExtension
    }
}
