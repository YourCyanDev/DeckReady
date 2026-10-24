import SwiftUI
import UniformTypeIdentifiers

struct CrateDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    let folder: FileWrapper
    @MainActor init(tracks: [Track], store: LibraryStore) throws {
        var children: [String: FileWrapper] = [:]
        for (index, track) in tracks.enumerated() {
            children[FileRules.exportName(index: index, track: track)] = try FileWrapper(url: store.fileURL(track), options: .immediate)
        }
        folder = FileWrapper(directoryWithFileWrappers: children)
    }
    init(configuration: ReadConfiguration) throws { folder = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { folder }
}
