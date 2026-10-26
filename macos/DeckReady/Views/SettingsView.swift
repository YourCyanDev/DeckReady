import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var serato: SeratoService
    @EnvironmentObject private var inboxWatcher: InboxWatcher

    var body: some View {
        Form {
            Section("Music Library") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Music Storage Location")
                        Text(settings.libraryFolder?.path ?? "No folder selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Choose…") { settings.chooseLibraryFolder() }
                    Button("Reveal") { settings.revealLibraryFolder() }
                        .disabled(settings.libraryFolder == nil)
                }

                Picker("Import files by", selection: $settings.importMode) {
                    ForEach(AppSettings.ImportMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Organize by", selection: $settings.organizationMode) {
                    ForEach(AppSettings.OrganizationMode.allCases) { Text($0.rawValue).tag($0) }
                }

                ForEach(Array(settings.additionalOrganizationModes.enumerated()), id: \.offset) { index, mode in
                    HStack {
                        Picker("Also organize by", selection: Binding(
                            get: { mode },
                            set: { value in
                                guard settings.additionalOrganizationModes.indices.contains(index) else { return }
                                settings.additionalOrganizationModes[index] = value
                            }
                        )) {
                            ForEach([AppSettings.OrganizationMode.yearArtist, .genreArtist]) { option in
                                Text(option.rawValue).tag(option)
                                    .disabled(option != mode && settings.activeOrganizationModes.contains(option))
                            }
                        }
                        Button("Remove") { settings.additionalOrganizationModes.remove(at: index) }
                    }
                }
                Button("Add more") {
                    if let mode = settings.availableAdditionalOrganizationModes.first {
                        settings.additionalOrganizationModes.append(mode)
                    }
                }
                .disabled(settings.availableAdditionalOrganizationModes.isEmpty)
                Text("The first option controls file storage. Serato gets every selected crate structure using the same audio files. Tracks missing the selected year/genre or artist go to need tag editing. Songs stay inside artist crates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Write edited metadata into audio files", isOn: $settings.writeMetadataToFiles)
                Text("When enabled, Save Tags writes Title, Artist, Album, Genre, and Year directly into supported files. WAV/WAVE and MP3 tag writing are supported in this Ventura build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("DeckReady Inbox") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Watched Inbox Folder")
                        Text(settings.inboxFolder?.path ?? "No folder selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Choose…") { settings.chooseInboxFolder() }
                    Button("Reveal") { settings.revealInboxFolder() }
                        .disabled(settings.inboxFolder == nil)
                }

                Toggle("Automatically import music dropped into the Inbox", isOn: $settings.automaticInboxImport)
                Toggle("Remove successfully imported items from the Inbox", isOn: $settings.removeInboxItemsAfterImport)
                    .disabled(!settings.automaticInboxImport)

                HStack(spacing: 8) {
                    Circle()
                        .fill(inboxWatcher.isWatching ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(inboxWatcher.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Scan Now") { inboxWatcher.scanNow() }
                        .disabled(settings.inboxFolder == nil || settings.libraryFolder == nil)
                }

                if let error = settings.inboxConfigurationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("DeckReady scans this folder when the app opens and watches it while running. Songs, folders, and ZIP files are automatically imported and organized. The default Inbox is ~/Music/DeckReady/Inbox.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Source Cleanup") {
                Toggle("Delete original ZIP or source folder after successful manual import", isOn: $settings.deleteSourceContainerAfterImport)
                Text("This applies to normal drag/drop and Add Music imports. Inbox cleanup is controlled separately above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Serato") {
                HStack {
                    Circle()
                        .fill(serato.isInstalled ? (serato.isRunning ? .green : .orange) : .red)
                        .frame(width: 9, height: 9)
                    Text(serato.statusText)
                    Spacer()
                    Button("Refresh") { serato.refreshStatus() }
                }

                TextField("Crate name", text: $settings.seratoCrateName)
                Text("Year/artist and genre/artist modes use tag names instead of the single crate name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Automatically sync new imports to Serato", isOn: $settings.automaticSeratoImport)
                Toggle("Reopen Serato after DeckReady closes it", isOn: $settings.launchSeratoWhenNeeded)
                    .disabled(!settings.automaticSeratoImport)

                Picker("Open after sync", selection: $settings.preferredSeratoApp) {
                    ForEach(AppSettings.SeratoAppPreference.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .disabled(!settings.automaticSeratoImport || !serato.preferenceSelectorEnabled(openWhenComplete: settings.launchSeratoWhenNeeded))

                if settings.launchSeratoWhenNeeded {
                    if serato.proInstalled && serato.liteInstalled {
                        Text("Both Serato DJ Pro and Lite are installed. Choose which one DeckReady should reopen after DeckReady closes Serato to apply crate changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if serato.proInstalled {
                        Text("Only Serato DJ Pro is installed, so DeckReady will reopen it automatically when needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if serato.liteInstalled {
                        Text("Only Serato DJ Lite is installed, so DeckReady will reopen it automatically when needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("If Serato is already closed, DeckReady syncs the crate without launching it. If Serato is open, DeckReady safely stores the tracks first and can quit it, apply the crate changes, and optionally reopen it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "Alpha a1.10.0")
                Text("Built for macOS Ventura 13+ and Xcode 15.2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: settings.organizationMode) { mode in
            settings.additionalOrganizationModes.removeAll { $0 == mode }
        }
        .onAppear {
            serato.refreshStatus()
            if !serato.preferenceSelectorEnabled(openWhenComplete: settings.launchSeratoWhenNeeded) {
                settings.preferredSeratoApp = serato.effectivePreference(settings.preferredSeratoApp)
            }
        }
    }
}
