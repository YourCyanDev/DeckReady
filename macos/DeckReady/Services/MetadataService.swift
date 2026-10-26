import Foundation
import AVFoundation

struct MetadataService {
    func metadata(for url: URL) async -> TrackMetadata {
        var metadata = TrackMetadata.empty

        // Read tags we can also safely write ourselves first. This keeps the
        // Ventura build independent of third-party packages.
        switch url.pathExtension.lowercased() {
        case "wav", "wave":
            if let tags = try? readWaveTags(from: url) {
                apply(tags: tags, to: &metadata)
            }
        case "mp3":
            if let tags = try? readID3Tags(from: url) {
                apply(tags: tags, to: &metadata)
            }
        default:
            break
        }

        await fillMissingMetadataUsingAVFoundation(url: url, metadata: &metadata)
        applyFilenameFallback(url: url, metadata: &metadata)

        metadata.title = clean(metadata.title)
        metadata.artist = clean(metadata.artist)
        metadata.album = clean(metadata.album)
        metadata.genre = clean(metadata.genre)
        metadata.year = clean(metadata.year)
        return metadata
    }

    /// Writes DeckReady's edited fields directly into the audio file without
    /// re-encoding the audio. A temporary backup is made first and restored if
    /// writing or verification fails.
    ///
    /// The Xcode 15.2 / Ventura build currently has native writers for WAV and
    /// MP3. Other formats can still be imported and read, but tag writing is
    /// intentionally blocked instead of risking damage to the audio file.
    func write(metadata: TrackMetadata, to url: URL) throws {
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            throw MetadataWriteError.notWritable(url.lastPathComponent)
        }

        let fileManager = FileManager.default
        let backupDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("DeckReadyMetadataSafety", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let backupURL = backupDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try fileManager.copyItem(at: url, to: backupURL)

        do {
            switch url.pathExtension.lowercased() {
            case "wav", "wave":
                try writeWave(metadata: metadata, to: url)
                try verifyWave(metadata: metadata, at: url)
            case "mp3":
                try writeMP3(metadata: metadata, to: url)
                try verifyMP3(metadata: metadata, at: url)
            default:
                throw MetadataWriteError.unsupportedWritableFormat(url.pathExtension.uppercased())
            }
            try? fileManager.removeItem(at: backupURL)
        } catch {
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                try fileManager.copyItem(at: backupURL, to: url)
                try? fileManager.removeItem(at: backupURL)
            } catch let restoreError {
                throw MetadataWriteError.restoreFailed(
                    name: url.lastPathComponent,
                    backupPath: backupURL.path,
                    underlying: restoreError.localizedDescription
                )
            }
            throw error
        }
    }

    // MARK: - WAV / RIFF INFO

    private func writeWave(metadata: TrackMetadata, to url: URL) throws {
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        guard original.count >= 12,
              asciiString(original, range: 0..<4) == "RIFF",
              asciiString(original, range: 8..<12) == "WAVE" else {
            throw MetadataWriteError.unsupportedFile(url.lastPathComponent)
        }

        var output = Data(original.prefix(12))
        var offset = 12

        while offset + 8 <= original.count {
            let id = asciiString(original, range: offset..<(offset + 4))
            let size = Int(readUInt32LE(original, at: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= original.count else {
                throw MetadataWriteError.malformedFile(url.lastPathComponent)
            }
            let paddedEnd = min(payloadEnd + (size % 2), original.count)

            var isInfoList = false
            if id == "LIST", size >= 4 {
                isInfoList = asciiString(original, range: payloadStart..<(payloadStart + 4)) == "INFO"
            }

            if !isInfoList {
                output.append(original.subdata(in: offset..<paddedEnd))
            }
            offset = paddedEnd
        }

        if offset < original.count {
            output.append(original.subdata(in: offset..<original.count))
        }

        let info = makeWaveInfoChunk(metadata)
        if !info.isEmpty { output.append(info) }

        guard output.count >= 8, output.count - 8 <= Int(UInt32.max) else {
            throw MetadataWriteError.malformedFile(url.lastPathComponent)
        }
        replaceUInt32LE(in: &output, at: 4, value: UInt32(output.count - 8))
        try output.write(to: url, options: .atomic)
    }

    private func makeWaveInfoChunk(_ metadata: TrackMetadata) -> Data {
        let fields: [(String, String)] = [
            ("INAM", metadata.title),
            ("IART", metadata.artist),
            ("IPRD", metadata.album),
            ("IGNR", metadata.genre),
            ("ICRD", normalizedYear(from: metadata.year))
        ]

        var payload = Data("INFO".utf8)
        var addedAny = false

        for (key, rawValue) in fields {
            let value = clean(rawValue)
            guard !value.isEmpty else { continue }
            addedAny = true

            var text = Data(value.utf8)
            text.append(0)
            payload.append(Data(key.utf8))
            appendUInt32LE(UInt32(text.count), to: &payload)
            payload.append(text)
            if text.count % 2 != 0 { payload.append(0) }
        }

        guard addedAny else { return Data() }

        var chunk = Data("LIST".utf8)
        appendUInt32LE(UInt32(payload.count), to: &chunk)
        chunk.append(payload)
        if payload.count % 2 != 0 { chunk.append(0) }
        return chunk
    }

    private func readWaveTags(from url: URL) throws -> TrackMetadata {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 12,
              asciiString(data, range: 0..<4) == "RIFF",
              asciiString(data, range: 8..<12) == "WAVE" else {
            throw MetadataWriteError.unsupportedFile(url.lastPathComponent)
        }

        var result = TrackMetadata.empty
        var offset = 12

        while offset + 8 <= data.count {
            let id = asciiString(data, range: offset..<(offset + 4))
            let size = Int(readUInt32LE(data, at: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= data.count else { break }

            if id == "LIST", size >= 4,
               asciiString(data, range: payloadStart..<(payloadStart + 4)) == "INFO" {
                var infoOffset = payloadStart + 4
                while infoOffset + 8 <= payloadEnd {
                    let infoID = asciiString(data, range: infoOffset..<(infoOffset + 4))
                    let infoSize = Int(readUInt32LE(data, at: infoOffset + 4))
                    let textStart = infoOffset + 8
                    let textEnd = textStart + infoSize
                    guard textEnd <= payloadEnd else { break }
                    let value = decodeRIFFText(data.subdata(in: textStart..<textEnd))
                    switch infoID {
                    case "INAM": result.title = value
                    case "IART": result.artist = value
                    case "IPRD": result.album = value
                    case "IGNR": result.genre = value
                    case "ICRD": result.year = normalizedYear(from: value)
                    default: break
                    }
                    infoOffset = textEnd + (infoSize % 2)
                }
            }
            offset = payloadEnd + (size % 2)
        }
        return result
    }

    // MARK: - MP3 / ID3v2

    private func writeMP3(metadata: TrackMetadata, to url: URL) throws {
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        var audioStart = 0
        var version: UInt8 = 3
        var preservedFrames: [Data] = []

        if original.count >= 10, asciiString(original, range: 0..<3) == "ID3" {
            version = original[3]
            guard version == 3 || version == 4 else {
                throw MetadataWriteError.unsupportedID3Version(Int(version))
            }

            let flags = original[5]
            if flags & 0x80 != 0 || flags & 0x40 != 0 {
                throw MetadataWriteError.complexID3(url.lastPathComponent)
            }

            let tagSize = Int(readSynchsafe32(original, at: 6))
            let tagEnd = 10 + tagSize
            guard tagEnd <= original.count else {
                throw MetadataWriteError.malformedFile(url.lastPathComponent)
            }
            let hasFooter = version == 4 && (flags & 0x10 != 0)
            audioStart = min(tagEnd + (hasFooter ? 10 : 0), original.count)

            var frameOffset = 10
            while frameOffset + 10 <= tagEnd {
                let frameID = asciiString(original, range: frameOffset..<(frameOffset + 4))
                if frameID.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).isEmpty { break }
                guard isValidID3FrameID(frameID) else { break }

                let frameSize = version == 4
                    ? Int(readSynchsafe32(original, at: frameOffset + 4))
                    : Int(readUInt32BE(original, at: frameOffset + 4))
                let frameEnd = frameOffset + 10 + frameSize
                guard frameSize >= 0, frameEnd <= tagEnd else { break }

                let replacedIDs: Set<String> = ["TIT2", "TPE1", "TALB", "TCON", "TYER", "TDRC"]
                if !replacedIDs.contains(frameID) {
                    preservedFrames.append(original.subdata(in: frameOffset..<frameEnd))
                }
                frameOffset = frameEnd
            }
        }

        var frames = Data()
        appendID3TextFrame(id: "TIT2", value: metadata.title, version: version, to: &frames)
        appendID3TextFrame(id: "TPE1", value: metadata.artist, version: version, to: &frames)
        appendID3TextFrame(id: "TALB", value: metadata.album, version: version, to: &frames)
        appendID3TextFrame(id: "TCON", value: metadata.genre, version: version, to: &frames)
        appendID3TextFrame(id: version == 4 ? "TDRC" : "TYER", value: normalizedYear(from: metadata.year), version: version, to: &frames)
        for frame in preservedFrames { frames.append(frame) }

        // Leave some padding so later edits don't constantly shift the MP3 data.
        frames.append(Data(repeating: 0, count: 1024))

        var header = Data("ID3".utf8)
        header.append(version)
        header.append(0)
        header.append(0)
        header.append(contentsOf: synchsafeBytes(UInt32(frames.count)))

        var output = Data()
        output.append(header)
        output.append(frames)
        if audioStart < original.count {
            output.append(original.subdata(in: audioStart..<original.count))
        }
        try output.write(to: url, options: .atomic)
    }

    private func appendID3TextFrame(id: String, value rawValue: String, version: UInt8, to data: inout Data) {
        let value = clean(rawValue)
        guard !value.isEmpty else { return }

        var payload = Data()
        if version == 4 {
            payload.append(3) // UTF-8
            payload.append(Data(value.utf8))
        } else {
            payload.append(1) // UTF-16 with BOM
            payload.append(contentsOf: [0xFE, 0xFF])
            payload.append(value.data(using: .utf16BigEndian) ?? Data())
        }

        data.append(Data(id.utf8))
        if version == 4 {
            data.append(contentsOf: synchsafeBytes(UInt32(payload.count)))
        } else {
            appendUInt32BE(UInt32(payload.count), to: &data)
        }
        data.append(contentsOf: [0, 0])
        data.append(payload)
    }

    private func readID3Tags(from url: URL) throws -> TrackMetadata {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 10, asciiString(data, range: 0..<3) == "ID3" else {
            return .empty
        }

        let version = data[3]
        guard version == 3 || version == 4 else { return .empty }
        let flags = data[5]
        guard flags & 0x80 == 0, flags & 0x40 == 0 else { return .empty }

        let tagSize = Int(readSynchsafe32(data, at: 6))
        let tagEnd = min(10 + tagSize, data.count)
        var offset = 10
        var result = TrackMetadata.empty

        while offset + 10 <= tagEnd {
            let id = asciiString(data, range: offset..<(offset + 4))
            if id.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).isEmpty { break }
            guard isValidID3FrameID(id) else { break }

            let size = version == 4
                ? Int(readSynchsafe32(data, at: offset + 4))
                : Int(readUInt32BE(data, at: offset + 4))
            let payloadStart = offset + 10
            let payloadEnd = payloadStart + size
            guard size >= 0, payloadEnd <= tagEnd else { break }

            if ["TIT2", "TPE1", "TALB", "TCON", "TYER", "TDRC"].contains(id) {
                let value = decodeID3Text(data.subdata(in: payloadStart..<payloadEnd))
                switch id {
                case "TIT2": result.title = value
                case "TPE1": result.artist = value
                case "TALB": result.album = value
                case "TCON": result.genre = value
                case "TYER", "TDRC": result.year = normalizedYear(from: value)
                default: break
                }
            }
            offset = payloadEnd
        }
        return result
    }

    private func decodeID3Text(_ payload: Data) -> String {
        guard let encodingByte = payload.first, payload.count > 1 else { return "" }
        let textData = payload.dropFirst()
        let string: String?
        switch encodingByte {
        case 0:
            string = String(data: Data(textData), encoding: .isoLatin1)
        case 1:
            string = String(data: Data(textData), encoding: .utf16)
        case 2:
            string = String(data: Data(textData), encoding: .utf16BigEndian)
        case 3:
            string = String(data: Data(textData), encoding: .utf8)
        default:
            string = nil
        }
        return clean(string ?? "")
    }

    private func verifyWave(metadata expected: TrackMetadata, at url: URL) throws {
        let actual = try readWaveTags(from: url)
        try verify(expected: expected, actual: actual, name: url.lastPathComponent)
    }

    private func verifyMP3(metadata expected: TrackMetadata, at url: URL) throws {
        let actual = try readID3Tags(from: url)
        try verify(expected: expected, actual: actual, name: url.lastPathComponent)
    }

    private func verify(expected: TrackMetadata, actual: TrackMetadata, name: String) throws {
        guard clean(expected.title) == clean(actual.title),
              clean(expected.artist) == clean(actual.artist),
              clean(expected.album) == clean(actual.album),
              clean(expected.genre) == clean(actual.genre),
              normalizedYear(from: expected.year) == normalizedYear(from: actual.year) else {
            throw MetadataWriteError.verificationFailed(name)
        }
    }

    // MARK: - AVFoundation fallback reader

    private func fillMissingMetadataUsingAVFoundation(url: URL, metadata: inout TrackMetadata) async {
        let asset = AVURLAsset(url: url)

        if metadata.duration <= 0 {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                metadata.duration = seconds.isFinite ? seconds : 0
            } catch {
                metadata.duration = 0
            }
        }

        var allItems: [AVMetadataItem] = []
        do {
            allItems.append(contentsOf: try await asset.load(.commonMetadata))
        } catch { }

        do {
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                do {
                    allItems.append(contentsOf: try await asset.loadMetadata(for: format))
                } catch { }
            }
        } catch { }

        if metadata.title.isEmpty {
            metadata.title = await bestString(in: allItems, matching: ["common/title", "title", "tit2", "inam", "©nam"]) ?? ""
        }
        if metadata.artist.isEmpty {
            metadata.artist = await bestString(in: allItems, matching: ["common/artist", "artist", "tpe1", "iart", "©art", "aart"]) ?? ""
        }
        if metadata.album.isEmpty {
            metadata.album = await bestString(in: allItems, matching: ["common/albumname", "albumname", "album", "talb", "iprd", "©alb"]) ?? ""
        }
        if metadata.genre.isEmpty {
            metadata.genre = await bestString(in: allItems, matching: ["common/type", "common/genre", "genre", "tcon", "ignr", "©gen", "gnre"]) ?? ""
        }
        if metadata.year.isEmpty,
           let rawYear = await bestString(in: allItems, matching: ["common/creationdate", "creationdate", "year", "tyer", "tdrc", "icrd", "©day"]) {
            metadata.year = normalizedYear(from: rawYear)
        }
    }

    private func bestString(in items: [AVMetadataItem], matching aliases: [String]) async -> String? {
        let normalizedAliases = aliases.map { normalizeKey($0) }
        for alias in normalizedAliases {
            for item in items {
                let candidates = metadataKeys(for: item)
                guard candidates.contains(where: { keyMatches($0, alias: alias) }) else { continue }
                if let value = await stringValue(for: item), !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func metadataKeys(for item: AVMetadataItem) -> [String] {
        var keys: [String] = []
        if let identifier = item.identifier?.rawValue { keys.append(normalizeKey(identifier)) }
        if let commonKey = item.commonKey?.rawValue { keys.append(normalizeKey(commonKey)) }
        if let key = item.key as? String { keys.append(normalizeKey(key)) }
        else if let key = item.key as? NSString { keys.append(normalizeKey(key as String)) }
        return keys
    }

    private func keyMatches(_ key: String, alias: String) -> Bool {
        key == alias || key.hasSuffix("/" + alias) || key.hasSuffix(alias)
    }

    private func normalizeKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func stringValue(for item: AVMetadataItem) async -> String? {
        if let string = try? await item.load(.stringValue) {
            let cleaned = clean(string)
            if !cleaned.isEmpty { return cleaned }
        }

        if let number = try? await item.load(.numberValue) {
            return number.stringValue
        }

        return nil
    }

    // MARK: - Helpers

    private func apply(tags: TrackMetadata, to metadata: inout TrackMetadata) {
        if metadata.title.isEmpty { metadata.title = tags.title }
        if metadata.artist.isEmpty { metadata.artist = tags.artist }
        if metadata.album.isEmpty { metadata.album = tags.album }
        if metadata.genre.isEmpty { metadata.genre = tags.genre }
        if metadata.year.isEmpty { metadata.year = tags.year }
    }

    private func applyFilenameFallback(url: URL, metadata: inout TrackMetadata) {
        let base = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        if metadata.title.isEmpty {
            if let split = base.range(of: " - ") {
                if metadata.artist.isEmpty { metadata.artist = String(base[..<split.lowerBound]) }
                metadata.title = String(base[split.upperBound...])
            } else {
                metadata.title = base
            }
        }
    }

    private func normalizedYear(from value: String) -> String {
        let cleaned = clean(value)
        guard !cleaned.isEmpty else { return "" }
        if let range = cleaned.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            return String(cleaned[range])
        }
        return cleaned
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeRIFFText(_ data: Data) -> String {
        let trimmed = Data(data.prefix { $0 != 0 })
        if let value = String(data: trimmed, encoding: .utf8) { return clean(value) }
        if let value = String(data: trimmed, encoding: .isoLatin1) { return clean(value) }
        return ""
    }

    private func asciiString(_ data: Data, range: Range<Int>) -> String {
        guard range.lowerBound >= 0, range.upperBound <= data.count else { return "" }
        return String(data: data.subdata(in: range), encoding: .ascii) ?? ""
    }

    private func isValidID3FrameID(_ id: String) -> Bool {
        guard id.count == 4 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
        }
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }

    private func readSynchsafe32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return (UInt32(data[offset] & 0x7F) << 21) |
            (UInt32(data[offset + 1] & 0x7F) << 14) |
            (UInt32(data[offset + 2] & 0x7F) << 7) |
            UInt32(data[offset + 3] & 0x7F)
    }

    private func synchsafeBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F)
        ]
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }

    private func replaceUInt32LE(in data: inout Data, at offset: Int, value: UInt32) {
        guard offset + 4 <= data.count else { return }
        data.replaceSubrange(offset..<(offset + 4), with: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}

enum MetadataWriteError: LocalizedError {
    case notWritable(String)
    case unsupportedFile(String)
    case unsupportedWritableFormat(String)
    case unsupportedID3Version(Int)
    case complexID3(String)
    case malformedFile(String)
    case verificationFailed(String)
    case restoreFailed(name: String, backupPath: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .notWritable(let name):
            return "DeckReady can't write metadata to \(name). Check the file's permissions."
        case .unsupportedFile(let name):
            return "DeckReady couldn't open \(name) for metadata writing."
        case .unsupportedWritableFormat(let format):
            return "Tag writing for \(format.isEmpty ? "this format" : format) is not enabled in this Ventura build yet. WAV and MP3 are supported right now."
        case .unsupportedID3Version(let version):
            return "This MP3 uses ID3v2.\(version), which DeckReady doesn't edit yet."
        case .complexID3(let name):
            return "\(name) uses an uncommon compressed/extended ID3 tag. DeckReady left the file unchanged instead of risking its existing artwork or metadata."
        case .malformedFile(let name):
            return "\(name) has a malformed audio container, so DeckReady left it unchanged."
        case .verificationFailed(let name):
            return "DeckReady couldn't verify the new tags in \(name), so the original file was restored."
        case .restoreFailed(let name, let backupPath, let underlying):
            return "DeckReady couldn't restore \(name) after a metadata write failed. A safety copy was kept at \(backupPath). \(underlying)"
        }
    }
}
