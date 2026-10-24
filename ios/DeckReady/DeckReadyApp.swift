import SwiftUI
import UniformTypeIdentifiers

@main
struct DeckReadyApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var player = PreviewPlayer()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(player)
                .tint(Color(red: 0.12, green: 0.88, blue: 0.75)).preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PreviewPlayer
    var body: some View {
        TabView {
            LibraryView().tabItem { Label("Library", systemImage: "music.note.list") }
            CratesView().tabItem { Label("Crates", systemImage: "square.stack") }
            NavigationStack {
                List {
                    Section("DeckReady for iPhone") {
                        Text("Alpha a1.01 · Local music preparation")
                        Text("Your imported files are copied into DeckReady. Your original files stay where they are.")
                    }
                    Section("Send a crate to Serato") {
                        Text("1. Open a crate and tap Export to Files.")
                        Text("2. Save the folder to On My iPhone or iCloud Drive.")
                        Text("3. In Serato, open Transfer & Files → Import Folder, then select the exported folder.")
                        Text("Exports contain audio files. Serato creates the crate during import. Cue points, beatgrids and desktop library sync are not included in this alpha.")
                    }
                    Section("Storage") { Text("\(store.tracks.count) tracks · \(store.crates.count) crates") }
                }.navigationTitle("Settings")
            }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom) {
            if let track = player.track {
                VStack(spacing: 5) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(track.title).font(.subheadline.bold()).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").padding(10) }
                            .accessibilityLabel(player.playing ? "Pause preview" : "Play preview")
                        Button { player.stop() } label: { Image(systemName: "xmark").padding(10) }.accessibilityLabel("Close preview")
                    }
                    Slider(value: $player.volume, in: 0...1).accessibilityLabel("Preview volume")
                }.padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
            }
        }
        .alert("DeckReady", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}

struct TrackRow: View {
    let track: Track
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PreviewPlayer
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = track.artwork, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: "music.note").frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.07)) }
            }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).lineLimit(1)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                do { try player.play(track, url: store.fileURL(track)) } catch { store.message = "Could not play this file: \(error.localizedDescription)" }
            } label: { Image(systemName: "play.circle.fill").font(.title2) }
                .buttonStyle(.borderless).accessibilityLabel("Preview \(track.title)")
        }.padding(.vertical, 3)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PreviewPlayer
    @State private var query = ""
    @State private var importer = false
    @State private var folders = false
    @State private var pendingDelete: Track?
    @State private var sortByArtist = false
    var filtered: [Track] {
        store.tracks.filter { query.isEmpty || "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(query) }
            .sorted { (sortByArtist ? $0.artist + $0.title : $0.title).localizedStandardCompare(sortByArtist ? $1.artist + $1.title : $1.title) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                if store.tracks.isEmpty {
                    ContentUnavailableView("Your next set starts here", systemImage: "waveform", description: Text("Import songs, folders or ZIP files to get your library ready."))
                }
                if store.busy { HStack { ProgressView(); Text("Importing music…") } }
                ForEach(filtered) { track in
                    TrackRow(track: track).swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = track }.disabled(store.busy)
                    }
                }
            }
            .navigationTitle("DeckReady")
            .searchable(text: $query, prompt: "Title, artist or album")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { Toggle("Sort by artist", isOn: $sortByArtist) } label: { Image(systemName: "arrow.up.arrow.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import songs or ZIP", systemImage: "doc.badge.plus") { folders = false; importer = true }
                        Button("Import folder", systemImage: "folder.badge.plus") { folders = true; importer = true }
                    } label: { Image(systemName: "plus.circle.fill") }.disabled(store.busy)
                }
            }
            .fileImporter(isPresented: $importer, allowedContentTypes: folders ? [.folder] : [.audio, .zip], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await store.importFiles(urls) }
                case .failure(let error): store.message = error.localizedDescription
                }
            }
            .confirmationDialog("Delete this track from DeckReady and its crates? Your original file stays untouched.", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete track", role: .destructive) {
                    if let track = pendingDelete { if player.track?.id == track.id { player.stop() }; store.removeTrack(track) }; pendingDelete = nil
                }
            }
        }
    }
}

struct CratesView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                if store.crates.isEmpty { ContentUnavailableView("Build your first crate", systemImage: "square.stack", description: Text("Group tracks for your next gig, practice session or mix.")) }
                ForEach(store.crates) { crate in
                    NavigationLink { CrateView(id: crate.id) } label: {
                        Label { VStack(alignment: .leading) { Text(crate.name); Text("\(crate.trackIDs.count) tracks").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "square.stack.fill") }
                    }
                }.onDelete { indexes in store.change { value in value.crates.remove(atOffsets: indexes) } }
            }.navigationTitle("Crates")
                .toolbar { Button("New crate", systemImage: "plus") { creating = true }.disabled(store.busy) }
                .alert("New crate", isPresented: $creating) {
                    TextField("Crate name", text: $name)
                    Button("Create") { store.createCrate(name); name = "" }
                    Button("Cancel", role: .cancel) { name = "" }
                }
        }
    }
}

struct CrateView: View {
    let id: UUID
    @EnvironmentObject private var store: LibraryStore
    @State private var adding = false
    @State private var exporting = false
    @State private var document: CrateDocument?
    var crate: Crate? { store.crates.first { $0.id == id } }
    var body: some View {
        List {
            if let crate {
                if crate.trackIDs.isEmpty { Text("Tap Add songs to choose tracks from your library.").foregroundStyle(.secondary) }
                ForEach(store.tracks(in: crate)) { track in TrackRow(track: track) }
                    .onMove { source, destination in store.change { value in
                        if let i = value.crates.firstIndex(where: { $0.id == id }) { value.crates[i].trackIDs.move(fromOffsets: source, toOffset: destination) }
                    } }
                    .onDelete { offsets in store.change { value in
                        if let i = value.crates.firstIndex(where: { $0.id == id }) { value.crates[i].trackIDs.remove(atOffsets: offsets) }
                    } }
            }
        }.navigationTitle(crate?.name ?? "Crate")
            .toolbar {
                EditButton().disabled(store.busy)
                Menu {
                    Button("Add songs", systemImage: "plus") { adding = true }
                    Button("Export to Files", systemImage: "square.and.arrow.up") {
                        guard let crate else { return }
                        do { document = try CrateDocument(tracks: store.tracks(in: crate), store: store); exporting = true }
                        catch { store.message = "Export failed: \(error.localizedDescription)" }
                    }.disabled(crate?.trackIDs.isEmpty != false)
                } label: { Image(systemName: "ellipsis.circle") }.disabled(store.busy)
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    List(store.tracks) { track in
                        Button { store.toggle(track, in: id) } label: {
                            HStack { Text(track.title).foregroundStyle(.primary); Spacer(); if crate?.trackIDs.contains(track.id) == true { Image(systemName: "checkmark.circle.fill") } }
                        }
                    }.navigationTitle("Add songs").toolbar { Button("Done") { adding = false } }
                }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .folder, defaultFilename: FileRules.safeName(crate?.name ?? "Crate")) { result in
                switch result {
                case .success: store.message = "Crate saved. In Serato, use Transfer & Files → Import Folder and select your exported folder."
                case .failure(let error): store.message = "Export failed: \(error.localizedDescription)"
                }
            }
    }
}
