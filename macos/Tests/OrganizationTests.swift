import Foundation

@main
struct OrganizationTests {
    @MainActor static func main() throws {
        func check(_ value: Bool, _ message: String) {
            if !value { fatalError(message) }
        }
        let root = URL(fileURLWithPath: "/tmp/DeckReadyOrganizationTests", isDirectory: true)
        func track(_ name: String, _ year: String = "2026", _ artist: String = "Yo DJ Hill", _ genre: String = "Hip-Hop") -> (url: URL, metadata: TrackMetadata) {
            (root.appendingPathComponent(name), TrackMetadata(title: name, artist: artist, album: "", genre: genre, year: year, duration: 0))
        }
        let tracks = [track("a.wav"), track("b.wav"), track("c.wav", "2025"), track("missing.wav", "", "", "")]
        let years = CrateOrganization.plan(tracks, modes: [.yearArtist], flatName: "Ignored")
        check(years["2026%%Yo DJ Hill"]?.count == 2, "Year artist grouping")
        check(years["2025%%Yo DJ Hill"]?.count == 1, "Same artist in another year")
        check(years["need tag editing"]?.count == 1, "Missing tags")
        check(!years.keys.contains(where: { $0.contains("Songs") || $0.components(separatedBy: "%%").count > 2 }), "No Songs crate")
        let incomplete = [track("no-year.wav", ""), track("no-artist.wav", "2026", "  "), track("no-genre.wav", "2026", "Yo DJ Hill", "")]
        let combined = CrateOrganization.plan(tracks + incomplete, modes: [.yearArtist, .genreArtist, .yearArtist], flatName: "Ignored")
        check(combined["need tag editing"]?.count == 4, "Review entries must deduplicate across modes")
        check(combined["Hip-Hop%%Yo DJ Hill"]?.contains(root.appendingPathComponent("a.wav")) == true, "Same URL in genre structure")
        check(combined["2026%%Yo DJ Hill"]?.contains(root.appendingPathComponent("a.wav")) == true, "Same URL in year structure")
        for mode in [AppSettings.OrganizationMode.flat, .artist, .genre, .year] {
            check(CrateOrganization.plan(tracks, modes: [mode], flatName: "My Crate").count == 1, "Old modes remain flat Serato crates")
        }
        check(CrateOrganization.destination(root: root, metadata: tracks[0].metadata, mode: .yearArtist).path == root.path + "/2026/Yo DJ Hill", "Year folders")
        check(CrateOrganization.destination(root: root, metadata: tracks[0].metadata, mode: .genreArtist).path == root.path + "/Hip-Hop/Yo DJ Hill", "Genre folders")
        check(CrateOrganization.destination(root: root, metadata: .empty, mode: .yearArtist).path == root.path + "/Unknown Year/Unknown Artist", "Unknown folder fallback")
        let unsafe = CrateOrganization.plan([track("unsafe.wav", "2026", "../artist%%name")], modes: [.yearArtist], flatName: "Ignored")
        check(unsafe.keys.allSatisfy { !$0.contains("/") && $0.components(separatedBy: "%%").count <= 2 }, "Unsafe metadata cannot inject hierarchy")

        let suite = "DeckReadyTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defaults.set(temp.appendingPathComponent("Library").path, forKey: "libraryFolder")
        defaults.set(temp.appendingPathComponent("Inbox").path, forKey: "inboxFolder")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }
        let settings = AppSettings(defaults: defaults)
        check(settings.organizationMode == .flat && settings.additionalOrganizationModes.isEmpty, "Old settings migration")
        settings.organizationMode = .yearArtist
        settings.additionalOrganizationModes = [.genreArtist]
        let loaded = AppSettings(defaults: defaults)
        check(loaded.activeOrganizationModes == [.yearArtist, .genreArtist], "Multiple options persist")
        check(loaded.availableAdditionalOrganizationModes.isEmpty, "No duplicate Add more options")
        loaded.additionalOrganizationModes = [.yearArtist, .genreArtist, .genreArtist]
        check(loaded.activeOrganizationModes.count == 2, "Duplicate modes ignored by routing")
        loaded.additionalOrganizationModes = []
        check(loaded.availableAdditionalOrganizationModes == [.genreArtist], "Remove restores Add more option")
        let libraryRoot = temp.appendingPathComponent("ExistingLibrary")
        try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        let unmanaged = libraryRoot.appendingPathComponent("never-imported.MP3")
        let nested = libraryRoot.appendingPathComponent("Nested/song.wav")
        let bytes = Data([7, 8, 9, 10])
        try bytes.write(to: unmanaged)
        try bytes.write(to: nested)
        try bytes.write(to: libraryRoot.appendingPathComponent("notes.txt"))
        try bytes.write(to: libraryRoot.appendingPathComponent(".hidden.mp3"))
        try FileManager.default.createSymbolicLink(at: libraryRoot.appendingPathComponent("linked.mp3"), withDestinationURL: unmanaged)
        let discovered = try LibraryCrateScan.discover(in: libraryRoot)
        check(discovered.count == 2, "Scan must recurse and skip hidden files/symlinks")
        check(discovered.contains { $0.resolvingSymlinksInPath().path == unmanaged.resolvingSymlinksInPath().path }, "Scanner must include unmanaged audio despite macOS temporary path aliases")
        let rows = [
            LibraryTrack(fileURL: unmanaged, metadata: TrackMetadata(title: "Zulu", artist: "Artist B", album: "Two", genre: "Pop", year: "2026", duration: 100)),
            LibraryTrack(fileURL: nested, metadata: TrackMetadata(title: "Alpha", artist: "Artist A", album: "One", genre: "Hip-Hop", year: "2025", duration: 20)),
            LibraryTrack(fileURL: libraryRoot.appendingPathComponent("blank.wav"), metadata: .empty)
        ]
        var query = LibraryQuery(artist: "Artist A", genre: "Hip-Hop", year: "2025", format: "WAV")
        check(query.apply(to: rows).map(\.fileURL) == [nested], "Filters must combine with AND")
        query.genre = "Pop"
        check(query.apply(to: rows).isEmpty, "Combined filters exclude nonmatches")
        check(LibraryQuery(artist: "Unknown").apply(to: rows).count == 1, "Unknown tag filter")
        check(LibraryQuery(search: "2026").apply(to: rows).count == 1, "Search includes year")
        check(LibraryQuery(sort: .duration, ascending: false).apply(to: rows).first?.fileURL == unmanaged, "Duration sort is numeric and descending")
        check(LibraryQuery(sort: .year, ascending: false).apply(to: rows).first?.fileURL == unmanaged, "Year sort is numeric")
        for sort in LibrarySort.allCases {
            let up = LibraryQuery(sort: sort).apply(to: rows).map(\.fileURL)
            let down = LibraryQuery(sort: sort, ascending: false).apply(to: rows).map(\.fileURL)
            check(up == Array(down.reversed()), "Ascending/descending order with stable tie breaker")
        }
        _ = CrateOrganization.plan(discovered.map { ($0, TrackMetadata.empty) }, modes: [.yearArtist, .genreArtist], flatName: "Ignored")
        let unmanagedAfter = try Data(contentsOf: unmanaged)
        check(unmanagedAfter == bytes, "Organize scan/plan must leave unmanaged audio untouched")
        let nestedAfter = try Data(contentsOf: nested)
        check(nestedAfter == bytes, "Organize scan/plan must leave nested audio untouched")
        print("All macOS organization, missing-tag, folder, safety and settings regression checks passed.")
    }
}
