import SwiftUI
import UniformTypeIdentifiers
import AppKit
import AVFoundation
import MediaPlayer

private enum LibrarySection: String, Hashable {
    case queue
    case musicLibrary
    case tagEditor
    case recent
    case duplicates
    case seratoDuplicates
}

private enum MetadataEditTarget: Equatable {
    case queue(UUID)
    case recent(UUID)
    case duplicate(UUID)
    case library(String)
    case seratoDuplicate(UUID)
}

private struct AudioPreviewEntry {
    let url: URL
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importer: ImportService
    @EnvironmentObject private var serato: SeratoService
    @EnvironmentObject private var inboxWatcher: InboxWatcher

    @StateObject private var preview = AudioPreviewController()
    @State private var selectedSection: LibrarySection = .queue
    @State private var isDropTargeted = false
    @State private var showingLog = false
    @State private var editingTarget: MetadataEditTarget?
    @State private var metadataDraft = TrackMetadata.empty
    @State private var searchText = ""
    @State private var libraryTracks: [LibraryTrack] = []
    @State private var tagEditorSelection: String?
    @State private var tagEditorDraft = TrackMetadata.empty
    @State private var tagEditorStatus = "Select a track to edit its embedded tags."
    @State private var seratoDuplicateTracks: [SeratoDuplicateTrack] = []
    @State private var isScanningLibrary = false
    @State private var isScanningSeratoDuplicates = false
    @State private var selectionMode = false
    @State private var selectedKeys: Set<String> = []

    private let supportedAudioExtensions: Set<String> = ["mp3", "m4a", "wav", "wave", "aiff", "aif", "flac", "aac"]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                mainContent
                if preview.currentURL != nil {
                    Divider()
                    nowPlayingBar
                }
                if selectionMode && !selectedKeys.isEmpty {
                    Divider()
                    selectionBar
                } else if selectedSection == .queue {
                    Divider()
                    bottomBar
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search tracks")
        .alert("DeckReady", isPresented: Binding(
            get: { importer.lastError != nil },
            set: { if !$0 { importer.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { importer.lastError = nil }
        } message: {
            Text(importer.lastError ?? "")
        }
        .alert("Restart Serato to Apply Changes", isPresented: $importer.showSeratoRestartPrompt) {
            Button(settings.launchSeratoWhenNeeded ? "Quit & Reopen Serato" : "Quit Serato & Sync") {
                importer.quitSeratoAndSync(reopenAfterSync: settings.launchSeratoWhenNeeded)
            }
            Button("Later", role: .cancel) { importer.deferSeratoRestart() }
        } message: {
            Text(settings.launchSeratoWhenNeeded
                 ? "Your imported tracks have been saved in DeckReady, but Serato is still open. DeckReady can quit Serato, apply the pending crate changes, and reopen the Serato app that was already in use."
                 : "Your imported tracks have been saved in DeckReady, but Serato is still open. DeckReady can quit Serato and apply the pending crate changes without reopening it.")
        }
        .alert("Serato Import Complete", isPresented: $importer.showSeratoSyncSuccessPrompt) {
            Button("OK", role: .cancel) { importer.showSeratoSyncSuccessPrompt = false }
        } message: {
            Text(importer.seratoSyncSuccessMessage)
        }
        .sheet(isPresented: Binding(
            get: { editingTarget != nil },
            set: { if !$0 { editingTarget = nil } }
        )) {
            let ext = metadataTargetURL?.pathExtension.lowercased() ?? ""
            MetadataEditorSheet(
                metadata: $metadataDraft,
                fileExtension: ext,
                writesToFile: settings.writeMetadataToFiles
            ) {
                saveEditedMetadata()
                editingTarget = nil
            } onCancel: {
                editingTarget = nil
            }
        }
        .onChange(of: selectedSection) { _ in
            selectionMode = false
            selectedKeys.removeAll()
            preview.stop()
            if (selectedSection == .musicLibrary || selectedSection == .tagEditor) && libraryTracks.isEmpty {
                refreshMusicLibrary()
            }
            if selectedSection == .tagEditor, tagEditorSelection == nil, let first = libraryTracks.first {
                selectTagEditorTrack(first)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deckReadyImportMusic)) { _ in chooseFiles(allowDirectories: false) }
        .onReceive(NotificationCenter.default.publisher(for: .deckReadyImportFolder)) { _ in chooseFolder() }
        .onReceive(NotificationCenter.default.publisher(for: .deckReadyOpenInbox)) { _ in settings.revealInboxFolder() }
        .onReceive(NotificationCenter.default.publisher(for: .deckReadyScanInbox)) { _ in inboxWatcher.scanNow() }
        .onReceive(NotificationCenter.default.publisher(for: .deckReadyOpenMusicLibrary)) { _ in settings.revealLibraryFolder() }
        .onDisappear { preview.stop() }
    }

    private var sidebar: some View {
        List {
            Section("Library") {
                sidebarButton(title: "Import Queue", systemImage: "tray.and.arrow.down.fill", section: .queue, badge: nil)
                sidebarButton(title: "Music Library", systemImage: "music.note.list", section: .musicLibrary, badge: libraryTracks.count)
                sidebarButton(title: "Tag Editor", systemImage: "tag.fill", section: .tagEditor, badge: nil)
                sidebarButton(title: "Recent Imports", systemImage: "clock.arrow.circlepath", section: .recent, badge: importer.recentImports.count)
                sidebarButton(title: "Import Duplicates", systemImage: "doc.on.doc", section: .duplicates, badge: importer.duplicateHistory.count)
                sidebarButton(title: "Serato Duplicates", systemImage: "square.on.square.badge.person.crop", section: .seratoDuplicates, badge: seratoDuplicateTracks.count)
            }

            Section("Automation") {
                HStack {
                    Circle().fill(inboxWatcher.isWatching ? .green : .orange).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DeckReady Inbox")
                        Text(inboxWatcher.statusText).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("Open Inbox") { settings.revealInboxFolder() }
                    .disabled(settings.inboxFolder == nil)
                Button("Scan Inbox Now") { inboxWatcher.scanNow() }
                    .disabled(settings.inboxFolder == nil || settings.libraryFolder == nil)
            }

            Section("Serato") {
                HStack {
                    Circle().fill(serato.isInstalled ? (serato.isRunning ? .green : .orange) : .red).frame(width: 8, height: 8)
                    Text(serato.isRunning ? "Running" : serato.isInstalled ? "Installed" : "Not found")
                }
                Button("Launch Serato") {
                    Task { _ = await serato.launch(preferred: settings.preferredSeratoApp) }
                }
                .disabled(!serato.isInstalled)
            }

            Section {
                Text("DeckReady Alpha a1.09.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("DeckReady")
        .frame(minWidth: 225)
    }

    private func sidebarButton(title: String, systemImage: String, section: LibrarySection, badge: Int?) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedSection == section ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sectionTitle).font(.title2.weight(.semibold))
                Text(sectionSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()

            if sectionHasSelectableRows {
                Button(selectionMode ? "Done" : "Select") {
                    selectionMode.toggle()
                    selectedKeys.removeAll()
                }
            }

            Button { openSettingsWindow() } label: { Label("Settings", systemImage: "gearshape") }

            switch selectedSection {
            case .queue:
                Button { chooseFiles() } label: { Label("Add Music", systemImage: "plus") }
                Button("Clear Finished") { importer.clearCompleted() }
                    .disabled(!importer.items.contains(where: { [.imported, .duplicate, .failed].contains($0.state) }))
            case .musicLibrary:
                Button(isScanningLibrary ? "Scanning…" : "Refresh Library") { refreshMusicLibrary() }
                    .disabled(isScanningLibrary || settings.libraryFolder == nil)
            case .tagEditor:
                Button(isScanningLibrary ? "Scanning…" : "Refresh Tracks") { refreshMusicLibrary() }
                    .disabled(isScanningLibrary || settings.libraryFolder == nil)
            case .recent:
                Button("Clear History") { importer.clearRecentHistory() }
                    .disabled(importer.recentImports.isEmpty)
            case .duplicates:
                Button("Clear History") { importer.clearDuplicateHistory() }
                    .disabled(importer.duplicateHistory.isEmpty)
            case .seratoDuplicates:
                Button(isScanningSeratoDuplicates ? "Scanning…" : "Scan Serato Duplicates") { scanSeratoDuplicates() }
                    .disabled(isScanningSeratoDuplicates)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedSection {
        case .queue:
            queueContent
        case .musicLibrary:
            musicLibraryContent
        case .tagEditor:
            tagEditorContent
        case .recent:
            historyContent(records: filteredRecent, duplicateHistory: false, emptyTitle: "No recent imports", emptyMessage: "Tracks you import with DeckReady will show up here.")
        case .duplicates:
            historyContent(records: filteredDuplicates, duplicateHistory: true, emptyTitle: "No import duplicates", emptyMessage: "Exact duplicate files that DeckReady skips will show up here.")
        case .seratoDuplicates:
            seratoDuplicatesContent
        }
    }

    @ViewBuilder
    private var queueContent: some View {
        if importer.items.isEmpty {
            dropZone
        } else if filteredQueue.isEmpty {
            EmptyStateView(title: "No matching tracks", systemImage: "magnifyingglass", message: "Try a different search.")
        } else {
            List(filteredQueue) { item in
                HStack(spacing: 8) {
                    selectionButton(key: keyForQueue(item.id))
                    ImportRowView(
                        item: item,
                        isPreviewing: preview.isPlaying(item.activeURL),
                        onPreview: { togglePreview(item.activeURL) },
                        onEditMetadata: {
                            metadataDraft = item.metadata
                            editingTarget = .queue(item.id)
                        },
                        onReveal: { importer.reveal(item.activeURL) },
                        onRemove: { importer.removeItem(item.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var musicLibraryContent: some View {
        if isScanningLibrary && libraryTracks.isEmpty {
            ProgressView("Scanning Music Library…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if settings.libraryFolder == nil {
            EmptyStateView(title: "Choose a Music Library", systemImage: "folder", message: "Pick your permanent music storage folder in Settings first.")
        } else if filteredLibraryTracks.isEmpty {
            EmptyStateView(title: libraryTracks.isEmpty ? "No songs found" : "No matching tracks", systemImage: "music.note.list", message: libraryTracks.isEmpty ? "Import music or click Refresh Library." : "Try a different search.")
        } else {
            List(filteredLibraryTracks) { track in
                HStack(spacing: 10) {
                    selectionButton(key: keyForLibrary(track.id))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.displayTitle).font(.headline).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(track.displayArtist)
                            Text("•")
                            Text(track.fileExtension)
                            if !track.metadata.album.isEmpty { Text("•"); Text(track.metadata.album) }
                            if track.metadata.duration > 0 { Text("•"); Text(formatDuration(track.metadata.duration)) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        Text(track.fileURL.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    Button { togglePreview(track.fileURL) } label: { Image(systemName: preview.isPlaying(track.fileURL) ? "pause.fill" : "play.fill") }
                        .buttonStyle(.borderless)
                    Button {
                        metadataDraft = track.metadata
                        editingTarget = .library(track.id)
                    } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                    Button { revealURL(track.fileURL) } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var tagEditorContent: some View {
        if isScanningLibrary && libraryTracks.isEmpty {
            ProgressView("Scanning Music Library…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if settings.libraryFolder == nil {
            EmptyStateView(title: "Choose a Music Library", systemImage: "folder", message: "Pick your permanent music storage folder in Settings first.")
        } else if filteredLibraryTracks.isEmpty {
            EmptyStateView(title: libraryTracks.isEmpty ? "No songs found" : "No matching tracks", systemImage: "tag", message: libraryTracks.isEmpty ? "Import music or click Refresh Tracks." : "Try a different search.")
        } else {
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tracks").font(.headline)
                            Text("Choose a song to edit its embedded metadata.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(filteredLibraryTracks.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                    .padding(12)

                    Divider()

                    List(filteredLibraryTracks) { track in
                        Button {
                            selectTagEditorTrack(track)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tagEditorSelection == track.id ? "tag.fill" : "music.note")
                                    .foregroundStyle(tagEditorSelection == track.id ? Color.accentColor : Color.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.displayTitle).fontWeight(.medium).lineLimit(1)
                                    Text("\(track.displayArtist) • \(track.fileExtension)")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if tagEditorSelection == track.id {
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(tagEditorSelection == track.id ? Color.accentColor.opacity(0.14) : Color.clear)
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 380, idealWidth: 440)

                tagEditorDetail
                    .frame(minWidth: 390, idealWidth: 470)
            }
        }
    }

    private var tagEditorDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let track = selectedTagEditorTrack {
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                            .overlay(Image(systemName: "music.note").font(.system(size: 38)).foregroundStyle(Color.accentColor))
                            .frame(width: 112, height: 112)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(tagEditorDraft.title.isEmpty ? track.displayTitle : tagEditorDraft.title)
                                .font(.title2.weight(.semibold)).lineLimit(2)
                            Text(tagEditorDraft.artist.isEmpty ? "Unknown Artist" : tagEditorDraft.artist)
                                .foregroundStyle(.secondary).lineLimit(1)
                            Text("\(track.fileExtension) • \(track.metadata.duration > 0 ? formatDuration(track.metadata.duration) : "Unknown length")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        tagEditorField("Title", text: $tagEditorDraft.title)
                        tagEditorField("Artist", text: $tagEditorDraft.artist)
                        tagEditorField("Album", text: $tagEditorDraft.album)
                        HStack(spacing: 12) {
                            tagEditorField("Genre", text: $tagEditorDraft.genre)
                            tagEditorField("Year", text: $tagEditorDraft.year)
                                .frame(maxWidth: 130)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.fileURL.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            if tagEditorSupportsWriting(track) {
                                Label("Save Tags writes to the actual audio file using DeckReady's safety-backup verification.", systemImage: "checkmark.shield")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Label("This Ventura build can currently write embedded tags to MP3 and WAV/WAVE files. Other formats stay read-only here for now.", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(tagEditorStatus).font(.caption).foregroundStyle(.secondary)

                    HStack {
                        Button(preview.isPlaying(track.fileURL) ? "Pause" : "Play") { togglePreview(track.fileURL) }
                        Button("Reveal") { revealURL(track.fileURL) }
                        Button("Reload Tags") { reloadTagEditorTrack(track) }
                        Spacer()
                        Button("Save Tags") { saveTagEditorChanges() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!tagEditorCanSave)
                    }
                } else {
                    EmptyStateView(title: "Select a track", systemImage: "tag", message: "Choose a song on the left to edit its title, artist, album, genre, and year.")
                        .frame(minHeight: 420)
                }
            }
            .padding(22)
        }
    }

    private func tagEditorField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedTagEditorTrack: LibraryTrack? {
        guard let id = tagEditorSelection else { return nil }
        return libraryTracks.first(where: { $0.id == id })
    }

    private var tagEditorCanSave: Bool {
        guard let track = selectedTagEditorTrack, tagEditorSupportsWriting(track) else { return false }
        return !tagEditorDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func tagEditorSupportsWriting(_ track: LibraryTrack) -> Bool {
        ["mp3", "wav", "wave"].contains(track.fileURL.pathExtension.lowercased())
    }

    private func selectTagEditorTrack(_ track: LibraryTrack) {
        tagEditorSelection = track.id
        tagEditorDraft = track.metadata
        tagEditorStatus = "Ready to edit. Changes are not written until you click Save Tags."
    }

    private func reloadTagEditorTrack(_ track: LibraryTrack) {
        tagEditorStatus = "Reloading tags from file…"
        Task {
            let metadata = await MetadataService().metadata(for: track.fileURL)
            if let index = libraryTracks.firstIndex(where: { $0.id == track.id }) {
                libraryTracks[index].metadata = metadata
                tagEditorDraft = metadata
                tagEditorStatus = "Reloaded tags from the audio file."
            }
        }
    }

    private func saveTagEditorChanges() {
        guard let track = selectedTagEditorTrack else { return }
        guard tagEditorSupportsWriting(track) else {
            tagEditorStatus = "This file format is read-only in the current macOS build."
            return
        }
        do {
            tagEditorStatus = "Saving tags and verifying the audio file…"
            var updated = tagEditorDraft
            updated.duration = track.metadata.duration
            try MetadataService().write(metadata: updated, to: track.fileURL)
            if let index = libraryTracks.firstIndex(where: { $0.id == track.id }) {
                libraryTracks[index].metadata = updated
            }
            tagEditorDraft = updated
            tagEditorStatus = "Saved and verified successfully."
        } catch {
            tagEditorStatus = "Save failed. DeckReady restored the original file from its safety backup."
            importer.lastError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func historyContent(records: [ImportHistoryRecord], duplicateHistory: Bool, emptyTitle: String, emptyMessage: String) -> some View {
        if records.isEmpty {
            EmptyStateView(title: emptyTitle, systemImage: duplicateHistory ? "doc.on.doc" : "clock", message: emptyMessage)
        } else {
            List(records) { record in
                HStack(spacing: 8) {
                    selectionButton(key: keyForHistory(record.id, duplicate: duplicateHistory))
                    HistoryRowView(
                        record: record,
                        isPreviewing: preview.isPlaying(record.fileURL),
                        onPreview: { togglePreview(record.fileURL) },
                        onEdit: {
                            metadataDraft = record.metadata
                            editingTarget = duplicateHistory ? .duplicate(record.id) : .recent(record.id)
                        },
                        onReveal: { importer.reveal(record.fileURL) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var seratoDuplicatesContent: some View {
        if isScanningSeratoDuplicates {
            ProgressView("Scanning Serato crates and hashing tracks…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredSeratoDuplicates.isEmpty {
            EmptyStateView(title: "No Serato duplicates found", systemImage: "checkmark.circle", message: "Click Scan Serato Duplicates to check exact duplicate files referenced by your Serato crates.")
        } else {
            List(filteredSeratoDuplicates) { track in
                HStack(spacing: 10) {
                    selectionButton(key: keyForSeratoDuplicate(track.id))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(track.groupID).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            Text("\(track.copyCount) copies").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(track.displayTitle).font(.headline).lineLimit(1)
                        Text("\(track.displayArtist) • \(track.crateNames.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(track.fileURL.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    Button { togglePreview(track.fileURL) } label: { Image(systemName: preview.isPlaying(track.fileURL) ? "pause.fill" : "play.fill") }
                        .buttonStyle(.borderless)
                    Button {
                        metadataDraft = track.metadata
                        editingTarget = .seratoDuplicate(track.id)
                    } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                    Button { revealURL(track.fileURL) } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Drop music here").font(.title3.weight(.semibold))
            Text("Songs, folders, and ZIP files are supported.").foregroundStyle(.secondary)
            Button("Choose Files or Folders…") { chooseFiles() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var nowPlayingBar: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = preview.currentArtwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                        Image(systemName: "music.note")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preview.playing ? "Now Playing" : "Paused")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(nowPlayingTitle)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(nowPlayingArtist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }

                HStack(spacing: 8) {
                    Text(formatPlaybackTime(preview.elapsedTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { min(preview.elapsedTime, max(preview.duration, 1)) },
                            set: { preview.seek(to: $0) }
                        ),
                        in: 0...max(preview.duration, 1)
                    )
                    .disabled(preview.duration <= 0)
                    .controlSize(.small)

                    Text(formatPlaybackTime(preview.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .leading)
                }
            }

            Spacer(minLength: 12)

            Button { preview.skipToPrevious() } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!preview.canSkipToPrevious)
            .help(preview.canSkipToPrevious ? "Skip to previous track" : "No previous track")

            Button {
                preview.toggleCurrent()
            } label: {
                Image(systemName: preview.playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help(preview.playing ? "Pause preview" : "Resume preview")

            Button { preview.skipToNext() } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!preview.canSkipToNext)
            .help(preview.canSkipToNext ? "Skip to next track" : "No next track")

            Button { preview.stop() } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .help("Stop preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private func formatPlaybackTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var nowPlayingTitle: String {
        guard let url = preview.currentURL?.standardizedFileURL else { return "" }
        if let track = libraryTracks.first(where: { $0.fileURL.standardizedFileURL == url }) { return track.displayTitle }
        if let item = importer.items.first(where: { $0.activeURL.standardizedFileURL == url }) { return item.displayTitle }
        if let record = importer.recentImports.first(where: { $0.fileURL.standardizedFileURL == url }) { return record.displayTitle }
        if let record = importer.duplicateHistory.first(where: { $0.fileURL.standardizedFileURL == url }) { return record.displayTitle }
        if let track = seratoDuplicateTracks.first(where: { $0.fileURL.standardizedFileURL == url }) {
            return track.metadata.title.isEmpty ? url.deletingPathExtension().lastPathComponent : track.metadata.title
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private var nowPlayingArtist: String {
        guard let url = preview.currentURL?.standardizedFileURL else { return "" }
        if let track = libraryTracks.first(where: { $0.fileURL.standardizedFileURL == url }) { return track.displayArtist }
        if let item = importer.items.first(where: { $0.activeURL.standardizedFileURL == url }) { return item.displayArtist }
        if let record = importer.recentImports.first(where: { $0.fileURL.standardizedFileURL == url }) { return record.displayArtist }
        if let record = importer.duplicateHistory.first(where: { $0.fileURL.standardizedFileURL == url }) { return record.displayArtist }
        if let track = seratoDuplicateTracks.first(where: { $0.fileURL.standardizedFileURL == url }) {
            return track.metadata.artist.isEmpty ? "Unknown Artist" : track.metadata.artist
        }
        return "Unknown Artist"
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(showingLog ? "Hide Activity" : "Show Activity") { showingLog.toggle() }
            Text(summaryText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if importer.items.contains(where: { $0.state == .waitingForSerato }) {
                Button("Retry Serato") { importer.retrySerato() }
            }
            Button("Import Ready Tracks") { importer.importReadyItems() }
                .buttonStyle(.borderedProminent)
                .disabled(importer.isBusy || !importer.items.contains(where: { $0.state == .ready }))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .topLeading) {
            if showingLog {
                ScrollView {
                    Text(importer.activityLog.suffix(40).joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 150)
                .background(.regularMaterial)
                .offset(y: -150)
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedKeys.count) selected").font(.caption.weight(.semibold))
            Button("Play") { if let url = firstSelectedURL { togglePreview(url) } }
                .disabled(firstSelectedURL == nil)
            Button("Edit Tags") { editSingleSelectedTrack() }
                .disabled(selectedKeys.count != 1)
            Button("Reveal") { if let url = firstSelectedURL { revealURL(url) } }
                .disabled(firstSelectedURL == nil)
            if selectedSection == .queue {
                Button("Remove from Queue", role: .destructive) { removeSelectedQueueItems() }
            }
            Spacer()
            Button("Clear Selection") { selectedKeys.removeAll() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func selectionButton(key: String) -> some View {
        if selectionMode {
            Button {
                if selectedKeys.contains(key) { selectedKeys.remove(key) } else { selectedKeys.insert(key) }
            } label: {
                Image(systemName: selectedKeys.contains(key) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedKeys.contains(key) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var metadataTargetURL: URL? {
        guard let target = editingTarget else { return nil }
        switch target {
        case .queue(let id): return importer.items.first(where: { $0.id == id })?.activeURL
        case .recent(let id): return importer.recentImports.first(where: { $0.id == id })?.fileURL
        case .duplicate(let id): return importer.duplicateHistory.first(where: { $0.id == id })?.fileURL
        case .library(let path): return URL(fileURLWithPath: path)
        case .seratoDuplicate(let id): return seratoDuplicateTracks.first(where: { $0.id == id })?.fileURL
        }
    }

    private func saveEditedMetadata() {
        guard let target = editingTarget else { return }
        switch target {
        case .queue(let id):
            importer.updateMetadata(for: id, metadata: metadataDraft)
        case .recent(let id):
            importer.updateHistoryMetadata(for: id, duplicate: false, metadata: metadataDraft)
        case .duplicate(let id):
            importer.updateHistoryMetadata(for: id, duplicate: true, metadata: metadataDraft)
        case .library(let path):
            let url = URL(fileURLWithPath: path)
            writeMetadataIfNeeded(metadataDraft, to: url)
            if let index = libraryTracks.firstIndex(where: { $0.id == path }) { libraryTracks[index].metadata = metadataDraft }
        case .seratoDuplicate(let id):
            guard let index = seratoDuplicateTracks.firstIndex(where: { $0.id == id }) else { return }
            let url = seratoDuplicateTracks[index].fileURL
            writeMetadataIfNeeded(metadataDraft, to: url)
            seratoDuplicateTracks[index] = SeratoDuplicateTrack(
                groupID: seratoDuplicateTracks[index].groupID,
                fileURL: url,
                metadata: metadataDraft,
                crateNames: seratoDuplicateTracks[index].crateNames,
                copyCount: seratoDuplicateTracks[index].copyCount,
                sha256: seratoDuplicateTracks[index].sha256
            )
        }
    }

    private func writeMetadataIfNeeded(_ metadata: TrackMetadata, to url: URL) {
        guard settings.writeMetadataToFiles else { return }
        do { try MetadataService().write(metadata: metadata, to: url) }
        catch { importer.lastError = error.localizedDescription }
    }

    private func refreshMusicLibrary() {
        guard let root = settings.libraryFolder else { return }
        isScanningLibrary = true
        Task {
            var urls: [URL] = []
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator where supportedAudioExtensions.contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                }
            }
            let metadataService = MetadataService()
            var tracks: [LibraryTrack] = []
            for url in urls.sorted(by: { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }) {
                tracks.append(LibraryTrack(fileURL: url, metadata: await metadataService.metadata(for: url)))
            }
            libraryTracks = tracks
            if selectedSection == .tagEditor {
                if let selected = tagEditorSelection, let match = tracks.first(where: { $0.id == selected }) {
                    selectTagEditorTrack(match)
                } else if let first = tracks.first {
                    selectTagEditorTrack(first)
                } else {
                    tagEditorSelection = nil
                    tagEditorDraft = .empty
                    tagEditorStatus = "No tracks are available to edit."
                }
            }
            isScanningLibrary = false
        }
    }

    private func scanSeratoDuplicates() {
        isScanningSeratoDuplicates = true
        Task {
            seratoDuplicateTracks = await serato.scanExactDuplicates()
            isScanningSeratoDuplicates = false
        }
    }

    private var filteredQueue: [ImportItem] {
        guard !searchQuery.isEmpty else { return importer.items }
        return importer.items.filter { item in
            item.displayTitle.lowercased().contains(searchQuery) ||
            item.displayArtist.lowercased().contains(searchQuery) ||
            item.metadata.album.lowercased().contains(searchQuery) ||
            item.metadata.genre.lowercased().contains(searchQuery) ||
            item.activeURL.lastPathComponent.lowercased().contains(searchQuery)
        }
    }

    private var filteredLibraryTracks: [LibraryTrack] {
        guard !searchQuery.isEmpty else { return libraryTracks }
        return libraryTracks.filter {
            $0.displayTitle.lowercased().contains(searchQuery) ||
            $0.displayArtist.lowercased().contains(searchQuery) ||
            $0.metadata.album.lowercased().contains(searchQuery) ||
            $0.metadata.genre.lowercased().contains(searchQuery) ||
            $0.fileURL.lastPathComponent.lowercased().contains(searchQuery)
        }
    }

    private var filteredRecent: [ImportHistoryRecord] { filterHistory(importer.recentImports) }
    private var filteredDuplicates: [ImportHistoryRecord] { filterHistory(importer.duplicateHistory) }

    private var filteredSeratoDuplicates: [SeratoDuplicateTrack] {
        guard !searchQuery.isEmpty else { return seratoDuplicateTracks }
        return seratoDuplicateTracks.filter {
            $0.displayTitle.lowercased().contains(searchQuery) ||
            $0.displayArtist.lowercased().contains(searchQuery) ||
            $0.groupID.lowercased().contains(searchQuery) ||
            $0.crateNames.joined(separator: " ").lowercased().contains(searchQuery) ||
            $0.fileURL.lastPathComponent.lowercased().contains(searchQuery)
        }
    }

    private func filterHistory(_ records: [ImportHistoryRecord]) -> [ImportHistoryRecord] {
        guard !searchQuery.isEmpty else { return records }
        return records.filter {
            $0.displayTitle.lowercased().contains(searchQuery) ||
            $0.displayArtist.lowercased().contains(searchQuery) ||
            $0.metadata.album.lowercased().contains(searchQuery) ||
            $0.metadata.genre.lowercased().contains(searchQuery) ||
            $0.fileURL.lastPathComponent.lowercased().contains(searchQuery)
        }
    }

    private var currentPreviewQueue: [AudioPreviewEntry] {
        switch selectedSection {
        case .queue:
            return filteredQueue.map { previewEntry(url: $0.activeURL, title: $0.displayTitle, artist: $0.displayArtist, metadata: $0.metadata) }
        case .musicLibrary, .tagEditor:
            return filteredLibraryTracks.map { previewEntry(url: $0.fileURL, title: $0.displayTitle, artist: $0.displayArtist, metadata: $0.metadata) }
        case .recent:
            return filteredRecent.map { previewEntry(url: $0.fileURL, title: $0.displayTitle, artist: $0.displayArtist, metadata: $0.metadata) }
        case .duplicates:
            return filteredDuplicates.map { previewEntry(url: $0.fileURL, title: $0.displayTitle, artist: $0.displayArtist, metadata: $0.metadata) }
        case .seratoDuplicates:
            return filteredSeratoDuplicates.map { previewEntry(url: $0.fileURL, title: $0.displayTitle, artist: $0.displayArtist, metadata: $0.metadata) }
        }
    }

    private func previewEntry(url: URL, title: String, artist: String, metadata: TrackMetadata) -> AudioPreviewEntry {
        AudioPreviewEntry(
            url: url.standardizedFileURL,
            title: title,
            artist: artist,
            album: metadata.album,
            duration: metadata.duration
        )
    }

    private func togglePreview(_ url: URL) {
        preview.toggle(url, queue: currentPreviewQueue)
    }

    private var searchQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private var sectionTitle: String {
        switch selectedSection {
        case .queue: return "Import Queue"
        case .musicLibrary: return "Music Library"
        case .tagEditor: return "Tag Editor"
        case .recent: return "Recent Imports"
        case .duplicates: return "Import Duplicates"
        case .seratoDuplicates: return "Serato Duplicate Checker"
        }
    }

    private var sectionSubtitle: String {
        switch selectedSection {
        case .queue: return settings.libraryFolder?.path ?? "Choose a music storage folder in Settings"
        case .musicLibrary: return "\(libraryTracks.count) song\(libraryTracks.count == 1 ? "" : "s") in your DeckReady music directory"
        case .tagEditor: return "Edit embedded song metadata directly from your DeckReady library"
        case .recent: return "\(importer.recentImports.count) stored track\(importer.recentImports.count == 1 ? "" : "s")"
        case .duplicates: return "\(importer.duplicateHistory.count) exact import duplicate\(importer.duplicateHistory.count == 1 ? "" : "s") skipped"
        case .seratoDuplicates: return "Exact SHA-256 duplicates referenced by Serato crate files"
        }
    }

    private var sectionHasSelectableRows: Bool {
        switch selectedSection {
        case .queue: return !filteredQueue.isEmpty
        case .musicLibrary: return !filteredLibraryTracks.isEmpty
        case .tagEditor: return false
        case .recent: return !filteredRecent.isEmpty
        case .duplicates: return !filteredDuplicates.isEmpty
        case .seratoDuplicates: return !filteredSeratoDuplicates.isEmpty
        }
    }

    private var summaryText: String {
        let ready = importer.items.filter { $0.state == .ready }.count
        let imported = importer.items.filter { $0.state == .imported }.count
        let duplicates = importer.items.filter { $0.state == .duplicate }.count
        return "\(ready) ready • \(imported) imported • \(duplicates) duplicates"
    }

    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func chooseFiles(allowDirectories: Bool = true) {
        let panel = NSOpenPanel()
        panel.title = "Add Music to DeckReady"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = allowDirectories
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowDirectories ? [.audio, .zip, .folder] : [.audio, .zip]
        if panel.runModal() == .OK { importer.add(urls: panel.urls) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import Music Folder"
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importer.add(urls: panel.urls) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let nsurl = item as? NSURL { url = nsurl as URL }
                if let url { Task { @MainActor in importer.add(urls: [url]) } }
            }
        }
        return true
    }

    private func revealURL(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func keyForQueue(_ id: UUID) -> String { "q:\(id.uuidString)" }
    private func keyForLibrary(_ id: String) -> String { "l:\(id)" }
    private func keyForHistory(_ id: UUID, duplicate: Bool) -> String { "h:\(duplicate ? "d" : "r"):\(id.uuidString)" }
    private func keyForSeratoDuplicate(_ id: UUID) -> String { "s:\(id.uuidString)" }

    private var firstSelectedURL: URL? {
        switch selectedSection {
        case .queue:
            return importer.items.first(where: { selectedKeys.contains(keyForQueue($0.id)) })?.activeURL
        case .musicLibrary:
            return libraryTracks.first(where: { selectedKeys.contains(keyForLibrary($0.id)) })?.fileURL
        case .tagEditor:
            return selectedTagEditorTrack?.fileURL
        case .recent:
            return importer.recentImports.first(where: { selectedKeys.contains(keyForHistory($0.id, duplicate: false)) })?.fileURL
        case .duplicates:
            return importer.duplicateHistory.first(where: { selectedKeys.contains(keyForHistory($0.id, duplicate: true)) })?.fileURL
        case .seratoDuplicates:
            return seratoDuplicateTracks.first(where: { selectedKeys.contains(keyForSeratoDuplicate($0.id)) })?.fileURL
        }
    }

    private func editSingleSelectedTrack() {
        guard selectedKeys.count == 1 else { return }
        switch selectedSection {
        case .queue:
            if let item = importer.items.first(where: { selectedKeys.contains(keyForQueue($0.id)) }) {
                metadataDraft = item.metadata; editingTarget = .queue(item.id)
            }
        case .musicLibrary:
            if let track = libraryTracks.first(where: { selectedKeys.contains(keyForLibrary($0.id)) }) {
                metadataDraft = track.metadata; editingTarget = .library(track.id)
            }
        case .tagEditor:
            break
        case .recent:
            if let record = importer.recentImports.first(where: { selectedKeys.contains(keyForHistory($0.id, duplicate: false)) }) {
                metadataDraft = record.metadata; editingTarget = .recent(record.id)
            }
        case .duplicates:
            if let record = importer.duplicateHistory.first(where: { selectedKeys.contains(keyForHistory($0.id, duplicate: true)) }) {
                metadataDraft = record.metadata; editingTarget = .duplicate(record.id)
            }
        case .seratoDuplicates:
            if let track = seratoDuplicateTracks.first(where: { selectedKeys.contains(keyForSeratoDuplicate($0.id)) }) {
                metadataDraft = track.metadata; editingTarget = .seratoDuplicate(track.id)
            }
        }
    }

    private func removeSelectedQueueItems() {
        let ids = importer.items.filter { selectedKeys.contains(keyForQueue($0.id)) }.map(\.id)
        for id in ids { importer.removeItem(id) }
        selectedKeys.removeAll()
    }
}

private struct HistoryRowView: View {
    let record: ImportHistoryRecord
    let isPreviewing: Bool
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.wasDuplicate ? "doc.on.doc.fill" : "checkmark.circle.fill")
                .foregroundStyle(record.wasDuplicate ? .orange : .green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayTitle).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(record.displayArtist)
                    if !record.metadata.album.isEmpty { Text("•"); Text(record.metadata.album) }
                    if !record.metadata.genre.isEmpty { Text("•"); Text(record.metadata.genre) }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(record.filePath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Button(action: onPreview) { Image(systemName: isPreviewing ? "pause.fill" : "play.fill") }
                .buttonStyle(.borderless).disabled(!FileManager.default.fileExists(atPath: record.filePath))
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.borderless).disabled(!FileManager.default.fileExists(atPath: record.filePath))
            Button(action: onReveal) { Image(systemName: "folder") }
                .buttonStyle(.borderless).disabled(!FileManager.default.fileExists(atPath: record.filePath))
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.wasDuplicate ? "Duplicate" : "Imported").font(.caption.weight(.semibold))
                Text(record.seratoSynced ? "Serato synced" : historyDate(record.importedAt)).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 110, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private func historyDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MetadataEditorSheet: View {
    @Binding var metadata: TrackMetadata
    let fileExtension: String
    let writesToFile: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var supportsTagWriting: Bool { ["mp3", "wav", "wave"].contains(fileExtension.lowercased()) }
    private var canSave: Bool { !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!writesToFile || supportsTagWriting) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Song Metadata").font(.title2.weight(.semibold))
            Form {
                TextField("Title", text: $metadata.title)
                TextField("Artist", text: $metadata.artist)
                TextField("Album", text: $metadata.album)
                TextField("Genre", text: $metadata.genre)
                TextField("Year", text: $metadata.year)
            }
            .formStyle(.grouped)

            if writesToFile {
                if supportsTagWriting {
                    Label("Save Tags will update the actual \(fileExtension.uppercased()) file. DeckReady creates a temporary safety backup and verifies the tags after writing.", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Actual tag writing for .\(fileExtension.lowercased()) is not enabled in this Ventura build yet. MP3 and WAV/WAVE are supported.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("Tag writing is disabled in Settings. This edit will only change DeckReady's current metadata.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(writesToFile ? "Save Tags" : "Save", action: onSave)
                    .buttonStyle(.borderedProminent).disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

@MainActor
private final class AudioPreviewController: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var playing = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var canSkipToPrevious = false
    @Published private(set) var canSkipToNext = false
    @Published private(set) var currentArtwork: NSImage?

    private let player: AVPlayer
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private var queue: [AudioPreviewEntry] = []
    private var currentIndex: Int?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        let player = AVPlayer()
        self.player = player
        configureRemoteCommands()
        installPlaybackObservers()
    }

    func toggle(_ url: URL, queue newQueue: [AudioPreviewEntry]) {
        let standardized = url.standardizedFileURL

        if currentURL?.standardizedFileURL == standardized {
            toggleCurrent()
            return
        }

        queue = normalizedQueue(newQueue, ensuring: standardized)
        currentIndex = queue.firstIndex(where: { $0.url.standardizedFileURL == standardized })
        playCurrentEntry()
    }

    func toggleCurrent() {
        guard currentURL != nil else { return }
        if playing {
            pause()
        } else {
            resume()
        }
    }

    func skipToPrevious() {
        guard let index = currentIndex, queue.indices.contains(index - 1) else { return }
        currentIndex = index - 1
        playCurrentEntry()
    }

    func skipToNext() {
        guard let index = currentIndex, queue.indices.contains(index + 1) else { return }
        currentIndex = index + 1
        playCurrentEntry()
    }

    func isPlaying(_ url: URL) -> Bool {
        playing && currentURL?.standardizedFileURL == url.standardizedFileURL
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        currentIndex = nil
        queue = []
        elapsedTime = 0
        duration = 0
        playing = false
        canSkipToPrevious = false
        canSkipToNext = false
        currentArtwork = nil
        nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingInfoCenter.playbackState = .stopped
        updateRemoteCommandAvailability()
    }

    private func pause() {
        player.pause()
        playing = false
        publishNowPlayingInfo()
    }

    private func resume() {
        guard currentURL != nil else { return }
        player.play()
        playing = true
        publishNowPlayingInfo()
    }

    private func playCurrentEntry() {
        guard let index = currentIndex, queue.indices.contains(index) else {
            stop()
            return
        }

        let entry = queue[index]
        let item = AVPlayerItem(url: entry.url)
        player.replaceCurrentItem(with: item)
        installEndObserver(for: item)
        player.seek(to: .zero)
        currentURL = entry.url
        elapsedTime = 0
        duration = max(0, entry.duration)
        currentArtwork = embeddedArtwork(for: entry.url)
        playing = true
        canSkipToPrevious = queue.indices.contains(index - 1)
        canSkipToNext = queue.indices.contains(index + 1)
        updateRemoteCommandAvailability()
        publishNowPlayingInfo()
        player.play()
    }

    private func normalizedQueue(_ entries: [AudioPreviewEntry], ensuring url: URL) -> [AudioPreviewEntry] {
        var seen = Set<String>()
        var result: [AudioPreviewEntry] = []

        for entry in entries {
            let standardized = entry.url.standardizedFileURL
            let key = standardized.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(AudioPreviewEntry(
                url: standardized,
                title: entry.title,
                artist: entry.artist,
                album: entry.album,
                duration: entry.duration
            ))
        }

        if !seen.contains(url.path) {
            result.append(AudioPreviewEntry(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                artist: "Unknown Artist",
                album: "",
                duration: 0
            ))
        }
        return result
    }

    private func configureRemoteCommands() {
        let commands = remoteCommandCenter

        commands.playCommand.isEnabled = false
        commands.pauseCommand.isEnabled = false
        commands.togglePlayPauseCommand.isEnabled = false
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
        commands.changePlaybackPositionCommand.isEnabled = false

        commands.playCommand.addTarget { [weak self] _ in
            guard let controller = self else { return .commandFailed }
            Task { @MainActor in controller.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            guard let controller = self else { return .commandFailed }
            Task { @MainActor in controller.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let controller = self else { return .commandFailed }
            Task { @MainActor in controller.toggleCurrent() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            guard let controller = self else { return .commandFailed }
            Task { @MainActor in controller.skipToPrevious() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            guard let controller = self else { return .commandFailed }
            Task { @MainActor in controller.skipToNext() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let controller = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let requestedTime = positionEvent.positionTime
            Task { @MainActor in controller.seek(to: requestedTime) }
            return .success
        }
    }

    private func updateRemoteCommandAvailability() {
        let hasTrack = currentURL != nil
        let commands = remoteCommandCenter
        commands.playCommand.isEnabled = hasTrack
        commands.pauseCommand.isEnabled = hasTrack
        commands.togglePlayPauseCommand.isEnabled = hasTrack
        commands.changePlaybackPositionCommand.isEnabled = hasTrack
        commands.previousTrackCommand.isEnabled = canSkipToPrevious
        commands.nextTrackCommand.isEnabled = canSkipToNext
    }

    private func installPlaybackObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds

            Task { @MainActor [self] in
                if seconds.isFinite {
                    self.elapsedTime = max(0, seconds)
                    if let itemDuration = self.player.currentItem?.duration.seconds,
                       itemDuration.isFinite, itemDuration > 0 {
                        self.duration = itemDuration
                    }
                    self.publishNowPlayingInfo()
                }
            }
        }
    }

    private func installEndObserver(for item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor [self] in
                if self.canSkipToNext {
                    self.skipToNext()
                } else {
                    self.playing = false
                    self.publishNowPlayingInfo()
                }
            }
        }
    }

    func seek(to seconds: TimeInterval) {
        guard currentURL != nil else { return }
        let upperBound = duration > 0 ? duration : seconds
        let safeSeconds = min(max(0, seconds), max(0, upperBound))
        player.seek(to: CMTime(seconds: safeSeconds, preferredTimescale: 600))
        elapsedTime = safeSeconds
        publishNowPlayingInfo()
    }

    private func publishNowPlayingInfo() {
        guard let index = currentIndex, queue.indices.contains(index) else {
            nowPlayingInfoCenter.nowPlayingInfo = nil
            nowPlayingInfoCenter.playbackState = .stopped
            return
        }

        let entry = queue[index]
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: entry.title,
            MPMediaItemPropertyArtist: entry.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyAssetURL: entry.url
        ]

        if !entry.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = entry.album
        }
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork = currentArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }

        nowPlayingInfoCenter.nowPlayingInfo = info
        nowPlayingInfoCenter.playbackState = playing ? .playing : .paused
    }

    private func embeddedArtwork(for url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        for item in asset.commonMetadata where item.commonKey?.rawValue == "artwork" {
            if let data = item.dataValue, let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }
}
