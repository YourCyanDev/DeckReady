import SwiftUI

struct ImportRowView: View {
    let item: ImportItem
    var isPreviewing: Bool = false
    var onPreview: (() -> Void)? = nil
    var onEditMetadata: (() -> Void)? = nil
    var onReveal: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .font(.title3)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.displayArtist)
                    Text("•")
                    Text(item.fileExtension)
                    if item.metadata.duration > 0 {
                        Text("•")
                        Text(formatDuration(item.metadata.duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !metadataDetail.isEmpty {
                    Text(metadataDetail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if let onPreview {
                    Button(action: onPreview) {
                        Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(isPreviewing ? "Pause preview" : "Preview track")
                }

                if let onEditMetadata {
                    Button(action: onEditMetadata) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit song metadata")
                }

                if let onReveal {
                    Button(action: onReveal) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }

                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from queue")
                }
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.state.rawValue)
                    .font(.caption.weight(.semibold))
                Text(item.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private var metadataDetail: String {
        var pieces: [String] = []
        if !item.metadata.album.isEmpty { pieces.append(item.metadata.album) }
        if !item.metadata.genre.isEmpty { pieces.append(item.metadata.genre) }
        if !item.metadata.year.isEmpty { pieces.append(item.metadata.year) }
        return pieces.joined(separator: " • ")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.state {
        case .queued, .scanning, .importing:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .duplicate:
            Image(systemName: "doc.on.doc.fill")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .waitingForSerato:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.yellow)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
