import XCTest
@testable import DeckReady

final class DeckReadyTests: XCTestCase {
    func testExportNameCannotEscapeFolderAndPreservesExtension() {
        let track = Track(id: UUID(), filename: "id.mp3", title: "../../set:one", artist: "DJ", album: "", duration: 1, digest: "abc")
        let name = FileRules.exportName(index: 0, track: track)
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasPrefix("001 - "))
        XCTAssertTrue(name.hasSuffix(".mp3"))
        XCTAssertEqual(FileRules.safeName(".."), "Crate")
    }
    func testDifferentIDsAvoidCollisionsForSameTitle() {
        let track = Track(id: UUID(), filename: "id.wav", title: "Same title", artist: "DJ", album: "", duration: 1, digest: "abc")
        XCTAssertNotEqual(FileRules.exportName(index: 0, track: track), FileRules.exportName(index: 1, track: track))
    }
    @MainActor func testCratesPersistAndTrackDeletionRemovesMembership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let track = Track(id: UUID(), filename: "test.wav", title: "Test", artist: "DJ", album: "", duration: 1, digest: "abc")
        store.change { $0.tracks.append(track) }
        store.createCrate("Friday")
        store.toggle(track, in: store.crates[0].id)
        XCTAssertEqual(LibraryStore(root: root).crates[0].trackIDs, [track.id])
        store.removeTrack(track)
        let reloaded = LibraryStore(root: root)
        XCTAssertTrue(reloaded.tracks.isEmpty)
        XCTAssertTrue(reloaded.crates[0].trackIDs.isEmpty)
    }
}
