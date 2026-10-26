import Foundation

struct ZipService {
    enum ZipError: LocalizedError {
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .extractionFailed(let message): return "ZIP extraction failed: \(message)"
            }
        }
    }

    func extract(_ zipURL: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeckReady-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            try? FileManager.default.removeItem(at: destination)
            throw ZipError.extractionFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return destination
    }
}
