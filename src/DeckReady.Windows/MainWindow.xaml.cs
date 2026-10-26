using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using DeckReady.Models;
using DeckReady.Services;
using DeckReady.Views;
using Microsoft.Win32;

namespace DeckReady;

public partial class MainWindow : Window
{
    public ObservableCollection<ImportItem> QueueItems { get; } = new();
    public ObservableCollection<HistoryRecord> RecentItems { get; } = new();
    public ObservableCollection<HistoryRecord> DuplicateItems { get; } = new();
    public ObservableCollection<LibraryTrack> LibraryItems { get; } = new();
    public ObservableCollection<SeratoDuplicateTrack> SeratoDuplicateItems { get; } = new();

    private readonly MetadataService _metadata = new();
    private readonly ZipService _zip = new();
    private readonly LogService _log = new();
    private readonly AppSettingsService _settingsService = new();
    private readonly HistoryStore _historyStore;
    private readonly ImportService _importService;
    private readonly SeratoService _serato;
    private readonly SeratoDuplicateScanner _seratoDuplicateScanner;
    private readonly AudioPreviewService _audioPreview = new();
    private AppSettings _settings;
    private readonly HashSet<string> _tempExtractionRoots = new(StringComparer.OrdinalIgnoreCase);
    private readonly SemaphoreSlim _autoImportGate = new(1, 1);
    private readonly AutoImportStateStore _autoImportState = new();
    private AutoImportWatcher? _autoImportWatcher;
    private bool _selectionMode;
    private AppPage _currentPage = AppPage.Queue;

    private enum AppPage
    {
        Queue,
        Library,
        TagEditor,
        Recent,
        ImportDuplicates,
        SeratoDuplicates
    }

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;

        _settings = _settingsService.Load();
        _historyStore = new HistoryStore();
        _importService = new ImportService(_metadata, _log);
        _serato = new SeratoService(_log);
        _seratoDuplicateScanner = new SeratoDuplicateScanner(_metadata, _log);
        _audioPreview.StateChanged += (_, _) => Dispatcher.BeginInvoke(new Action(UpdateNowPlaying));

        RefreshHistoryCollections();
        ShowQueuePage();
        ConfigureAutoImportWatcher();
        RefreshUI();

        Loaded += async (_, _) =>
        {
            if (_settings.AutoImportEnabled)
                await ScanAutoImportFolderAsync();
        };

        Closing += (_, _) =>
        {
            _autoImportWatcher?.Dispose();
            _autoImportGate.Dispose();
            _audioPreview.Dispose();
            foreach (var root in _tempExtractionRoots)
            {
                try { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); } catch { }
            }
        };
    }

    private async void ImportFiles_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Add Music to DeckReady",
            Multiselect = true,
            Filter = "Music and ZIP files|*.mp3;*.m4a;*.wav;*.wave;*.aiff;*.aif;*.flac;*.aac;*.zip|Audio files|*.mp3;*.m4a;*.wav;*.wave;*.aiff;*.aif;*.flac;*.aac|ZIP files|*.zip|All files|*.*"
        };

        if (dialog.ShowDialog(this) == true)
            await AddSourcesAsync(dialog.FileNames);
    }

    private async void ImportFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Choose a folder of music",
            Multiselect = false,
            InitialDirectory = Directory.Exists(_settings.LibraryFolder)
                ? _settings.LibraryFolder
                : Environment.GetFolderPath(Environment.SpecialFolder.MyMusic)
        };

        if (dialog.ShowDialog(this) == true)
            await AddSourcesAsync([dialog.FolderName]);
    }

    private async Task AddSourcesAsync(IEnumerable<string> sources, bool showErrors = true)
    {
        ShowQueuePage();

        foreach (var source in sources.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                if (Directory.Exists(source))
                {
                    await AddFolderAsync(source);
                }
                else if (File.Exists(source) && Path.GetExtension(source).Equals(".zip", StringComparison.OrdinalIgnoreCase))
                {
                    await AddZipAsync(source);
                }
                else if (File.Exists(source) && ImportService.IsSupportedAudio(source))
                {
                    await AddAudioAsync(new ImportItem { SourcePath = source });
                }
            }
            catch (Exception ex)
            {
                _log.Error($"Could not add '{source}': {ex.Message}");
                if (showErrors)
                    MessageBox.Show(this, $"DeckReady could not add:\n{source}\n\n{ex.Message}", "Import Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        RefreshUI();
    }

    private async Task AddFolderAsync(string folder)
    {
        var files = Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories)
            .Where(ImportService.IsSupportedAudio)
            .ToList();

        foreach (var file in files)
        {
            await AddAudioAsync(new ImportItem
            {
                SourcePath = file,
                SourceContainerPath = folder,
                SourceContainerKind = SourceContainerKind.Folder
            });
        }

        _log.Info($"Scanned folder '{folder}' and found {files.Count} audio files.");
    }

    private async Task AddZipAsync(string zipPath)
    {
        var extractionRoot = await Task.Run(() => _zip.ExtractSafely(zipPath));
        _tempExtractionRoots.Add(extractionRoot);

        var files = Directory.EnumerateFiles(extractionRoot, "*", SearchOption.AllDirectories)
            .Where(ImportService.IsSupportedAudio)
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}__MACOSX{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase))
            .ToList();

        foreach (var file in files)
        {
            await AddAudioAsync(new ImportItem
            {
                SourcePath = file,
                SourceContainerPath = zipPath,
                SourceContainerKind = SourceContainerKind.Zip,
                ExtractionRoot = extractionRoot
            });
        }

        _log.Info($"Extracted ZIP '{zipPath}' and found {files.Count} audio files.");
    }

    private async Task AddAudioAsync(ImportItem item)
    {
        QueueItems.Add(item);
        item.State = ImportState.Scanning;
        item.StatusMessage = "Reading metadata...";

        try
        {
            item.Metadata = await Task.Run(() => _metadata.Read(item.SourcePath));
            item.State = ImportState.Ready;
            item.StatusMessage = "Ready";
        }
        catch (Exception ex)
        {
            item.Metadata = new TrackMetadata { Title = Path.GetFileNameWithoutExtension(item.SourcePath) };
            item.State = ImportState.Ready;
            item.StatusMessage = "Metadata unavailable — ready";
            _log.Warning($"Metadata read failed for '{item.SourcePath}': {ex.Message}");
        }

        RefreshUI();
    }

    private async void ImportReady_Click(object sender, RoutedEventArgs e)
    {
        var ready = QueueItems.Where(x => x.State == ImportState.Ready).ToList();
        await ImportItemsAsync(ready, interactive: true);
    }

    private async Task ImportItemsAsync(List<ImportItem> ready, bool interactive)
    {
        if (ready.Count == 0) return;

        if (string.IsNullOrWhiteSpace(_settings.LibraryFolder))
        {
            if (interactive)
            {
                MessageBox.Show(this, "Choose a music storage folder in Settings first.", "DeckReady", MessageBoxButton.OK, MessageBoxImage.Information);
                OpenSettings();
            }
            else
            {
                _log.Warning("Auto Import is waiting because no music library folder is configured.");
            }
            return;
        }

        ImportReadyButton.IsEnabled = false;
        try
        {
            var hashIndex = await _importService.BuildLibraryHashIndexAsync(_settings.LibraryFolder);

            foreach (var item in ready)
            {
                if (item.State != ImportState.Ready) continue;

                item.State = ImportState.Importing;
                item.StatusMessage = item.IsAutoImport ? "Auto importing..." : "Importing...";
                try
                {
                    var (destination, duplicate) = await _importService.ImportAsync(item, _settings, hashIndex);
                    item.DestinationPath = destination;
                    item.WasDuplicate = duplicate;

                    if (duplicate)
                    {
                        item.State = ImportState.Duplicate;
                        item.StatusMessage = item.IsAutoImport ? "Auto import matched existing duplicate" : "Duplicate already exists in library";
                    }
                    else
                    {
                        item.State = ImportState.Imported;
                        item.StatusMessage = item.IsAutoImport ? "Auto imported" : "Stored";
                    }

                    _historyStore.Add(new HistoryRecord
                    {
                        Metadata = item.Metadata.Clone(),
                        FilePath = destination,
                        ImportedAt = DateTime.Now,
                        WasDuplicate = duplicate,
                        SeratoSynced = false
                    });
                }
                catch (Exception ex)
                {
                    item.State = ImportState.Failed;
                    item.StatusMessage = ex.Message;
                    _log.Error($"Import failed for '{item.SourcePath}': {ex.Message}");
                }
            }

            CleanupSuccessfulSources(ready);
            RefreshHistoryCollections();

            var candidates = ready
                .Where(x => x.State is ImportState.Imported or ImportState.Duplicate)
                .Select(x => x.DestinationPath)
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Cast<string>()
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            if (_settings.AutomaticSeratoImport && candidates.Count > 0)
                await SyncOrDeferSeratoAsync(candidates);

            RefreshUI();
        }
        finally
        {
            ImportReadyButton.IsEnabled = QueueItems.Any(x => x.State == ImportState.Ready);
        }
    }

    private async Task SyncOrDeferSeratoAsync(List<string> paths)
    {
        _serato.RefreshStatus();
        if (_serato.IsRunning)
        {
            MarkWaitingForSerato(paths);
            var dialog = new SeratoRestartDialog { Owner = this };
            dialog.ShowDialog();

            if (dialog.RestartRequested)
            {
                var closed = await _serato.QuitAndWaitAsync();
                if (!closed)
                {
                    MessageBox.Show(this,
                        "Serato is still open. DeckReady left the tracks waiting so nothing is overwritten. Close Serato manually, then click Retry Serato.",
                        "Serato Still Open", MessageBoxButton.OK, MessageBoxImage.Warning);
                    RefreshUI();
                    return;
                }

                await CompleteSeratoSyncAsync(paths, reopen: true);
            }
            return;
        }

        await CompleteSeratoSyncAsync(paths, reopen: _settings.LaunchSeratoWhenNeeded);
    }

    private async Task CompleteSeratoSyncAsync(List<string> paths, bool reopen)
    {
        try
        {
            // Snapshot edited metadata on the UI thread, including deferred/retried imports.
            var mode = _settings.OrganizationMode;
            var modes = new[] { mode }.Concat(_settings.AdditionalOrganizationModes ?? new()).Distinct().ToArray();
            var needsTags = modes.Any(x => x is OrganizationMode.YearArtist or OrganizationMode.GenreArtist);
            var crateName = _settings.SeratoCrateName;
            var metadata = QueueItems.Where(x => x.DestinationPath is not null)
                .GroupBy(x => x.DestinationPath!, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(x => x.Key, x => x.First().Metadata.Clone(), StringComparer.OrdinalIgnoreCase);
            await Task.Run(() =>
            {
                var tracks = paths.Select(path => (Path: path, Metadata:
                    !needsTags ? new TrackMetadata() :
                    metadata.TryGetValue(path, out var tags) ? tags : _metadata.Read(path))).ToList();
                _serato.SyncOrganizedCrates(tracks, modes, crateName);
            });
            var syncTarget = needsTags ? "selected crates (including need tag editing when needed)" : crateName;
            _historyStore.UpdateSeratoSynced(paths);

            foreach (var item in QueueItems.Where(x => x.DestinationPath is not null && paths.Contains(x.DestinationPath, StringComparer.OrdinalIgnoreCase)))
            {
                if (item.State == ImportState.WaitingForSerato)
                    item.State = item.WasDuplicate ? ImportState.Duplicate : ImportState.Imported;
                item.StatusMessage = $"Synced to {syncTarget}";
            }

            var reopened = !reopen || _serato.Launch(_settings.PreferredSeratoApp);
            MessageBox.Show(this,
                $"{paths.Count} track{(paths.Count == 1 ? "" : "s")} synced to “{syncTarget}”."
                + (reopen ? $"\n\nSerato {(reopened ? "was reopened." : "could not be reopened automatically.")}" : ""),
                "Serato Import Complete", MessageBoxButton.OK, MessageBoxImage.Information);

            RefreshHistoryCollections();
        }
        catch (Exception ex)
        {
            MarkWaitingForSerato(paths);
            _log.Error($"Serato sync failed: {ex.Message}");
            MessageBox.Show(this, $"DeckReady could not sync the pending tracks to Serato.\n\n{ex.Message}", "Serato Sync Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }

        RefreshUI();
    }

    private void MarkWaitingForSerato(IEnumerable<string> paths)
    {
        var set = new HashSet<string>(paths, StringComparer.OrdinalIgnoreCase);
        foreach (var item in QueueItems.Where(x => x.DestinationPath is not null && set.Contains(x.DestinationPath)))
        {
            item.State = ImportState.WaitingForSerato;
            item.StatusMessage = "Stored • waiting for Serato";
        }
    }

    private async void RetrySerato_Click(object sender, RoutedEventArgs e)
    {
        var pending = QueueItems
            .Where(x => x.State == ImportState.WaitingForSerato && !string.IsNullOrWhiteSpace(x.DestinationPath))
            .Select(x => x.DestinationPath!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (pending.Count == 0) return;

        _serato.RefreshStatus();
        if (_serato.IsRunning)
        {
            MessageBox.Show(this, "Serato is still open. Close it first, then click Retry Serato.", "Serato Is Open", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        await CompleteSeratoSyncAsync(pending, reopen: _settings.LaunchSeratoWhenNeeded);
    }

    private void CleanupSuccessfulSources(IReadOnlyCollection<ImportItem> processed)
    {
        var successStates = new[] { ImportState.Imported, ImportState.Duplicate, ImportState.WaitingForSerato };

        // Manual source-container cleanup follows the existing destructive setting.
        if (_settings.DeleteSourceContainerAfterImport)
        {
            var manualContainers = processed
                .Where(x => !x.IsAutoImport && !string.IsNullOrWhiteSpace(x.SourceContainerPath))
                .GroupBy(x => x.SourceContainerPath!, StringComparer.OrdinalIgnoreCase);

            foreach (var group in manualContainers)
                DeleteContainerIfComplete(group, successStates, "source container");
        }

        // The DeckReady Inbox can behave like a true staging area.
        if (_settings.ClearAutoImportFolderAfterImport)
        {
            var autoContainers = processed
                .Where(x => x.IsAutoImport && !string.IsNullOrWhiteSpace(x.SourceContainerPath))
                .GroupBy(x => x.SourceContainerPath!, StringComparer.OrdinalIgnoreCase);

            foreach (var group in autoContainers)
                DeleteContainerIfComplete(group, successStates, "Inbox item");

            foreach (var item in processed.Where(x => x.IsAutoImport && x.SourceContainerKind == SourceContainerKind.None))
            {
                if (!successStates.Contains(item.State)) continue;
                if (!IsInsideFolder(item.SourcePath, _settings.AutoImportFolder)) continue;
                if (!File.Exists(item.SourcePath)) continue;
                if (!string.IsNullOrWhiteSpace(item.DestinationPath) && Path.GetFullPath(item.SourcePath).Equals(Path.GetFullPath(item.DestinationPath), StringComparison.OrdinalIgnoreCase)) continue;

                try
                {
                    File.Delete(item.SourcePath);
                    _log.Info($"Removed imported Inbox file '{item.SourcePath}'.");
                }
                catch (Exception ex)
                {
                    _log.Warning($"Could not remove Inbox file '{item.SourcePath}': {ex.Message}");
                }
            }
        }

        // Clean ZIP extraction folders only after every associated track has completed successfully.
        var extractionGroups = processed
            .Where(x => !string.IsNullOrWhiteSpace(x.ExtractionRoot))
            .GroupBy(x => x.ExtractionRoot!, StringComparer.OrdinalIgnoreCase);

        foreach (var group in extractionGroups)
        {
            if (!group.All(x => successStates.Contains(x.State))) continue;
            var root = group.Key;
            try
            {
                if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
                _tempExtractionRoots.Remove(root);
            }
            catch (Exception ex)
            {
                _log.Warning($"Could not remove temporary ZIP extraction folder '{root}': {ex.Message}");
            }
        }
    }

    private void DeleteContainerIfComplete(IGrouping<string, ImportItem> group, ImportState[] successStates, string description)
    {
        if (!group.All(x => successStates.Contains(x.State))) return;
        var containerPath = group.Key;
        if (!IsSafeToDeleteContainer(containerPath)) return;

        try
        {
            var kind = group.First().SourceContainerKind;
            if (kind == SourceContainerKind.Zip && File.Exists(containerPath))
                File.Delete(containerPath);
            else if (kind == SourceContainerKind.Folder && Directory.Exists(containerPath))
                Directory.Delete(containerPath, recursive: true);

            _log.Info($"Deleted {description} after successful import: {containerPath}");
        }
        catch (Exception ex)
        {
            _log.Warning($"Could not delete {description} '{containerPath}': {ex.Message}");
        }
    }

    private bool IsSafeToDeleteContainer(string containerPath)
    {
        if (string.IsNullOrWhiteSpace(_settings.LibraryFolder)) return false;

        var container = Path.GetFullPath(containerPath).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var library = Path.GetFullPath(_settings.LibraryFolder).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

        if (container.Equals(library, StringComparison.OrdinalIgnoreCase)) return false;
        if (library.StartsWith(container + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) return false;

        if (!string.IsNullOrWhiteSpace(_settings.AutoImportFolder))
        {
            var inbox = Path.GetFullPath(_settings.AutoImportFolder).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (container.Equals(inbox, StringComparison.OrdinalIgnoreCase)) return false;
        }
        return true;
    }

    private void QueueGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (_selectionMode) return;
        if (QueueGrid.SelectedItem is ImportItem item)
            EditTrack(item.ActivePath, item.Metadata, metadata => item.Metadata = metadata);
    }

    private void LibraryGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (_selectionMode) return;
        if (LibraryGrid.SelectedItem is LibraryTrack track)
            EditLibraryTrack(track);
    }

    private void RecentGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (_selectionMode) return;
        if (RecentGrid.SelectedItem is HistoryRecord record && File.Exists(record.FilePath))
        {
            EditTrack(record.FilePath, record.Metadata, metadata =>
            {
                record.Metadata = metadata;
                _historyStore.Save();
                RefreshHistoryCollections();
            });
        }
    }

    private void DuplicatesGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (_selectionMode) return;
        if (DuplicatesGrid.SelectedItem is HistoryRecord record && File.Exists(record.FilePath))
            EditTrack(record.FilePath, record.Metadata, metadata =>
            {
                record.Metadata = metadata;
                _historyStore.Save();
                RefreshHistoryCollections();
            });
    }

    private void SeratoDuplicatesGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (_selectionMode) return;
        if (SeratoDuplicatesGrid.SelectedItem is SeratoDuplicateTrack track && File.Exists(track.FilePath))
            EditTrack(track.FilePath, track.Metadata, metadata => track.Metadata = metadata);
    }

    private void EditLibraryTrack(LibraryTrack track)
    {
        EditTrack(track.FilePath, track.Metadata, metadata => track.Metadata = metadata);
    }

    private void EditTrack(string path, TrackMetadata metadata, Action<TrackMetadata> apply)
    {
        if (!File.Exists(path))
        {
            MessageBox.Show(this, "That audio file can no longer be found.", "DeckReady", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var editor = new MetadataEditorWindow(path, metadata, _metadata) { Owner = this };
        if (editor.ShowDialog() == true)
            apply(editor.Result);
    }

    private void Settings_Click(object sender, RoutedEventArgs e) => OpenSettings();

    private void OpenSettings()
    {
        var dialog = new SettingsWindow(_settings, _serato) { Owner = this };
        if (dialog.ShowDialog() == true)
        {
            _settingsService.Save(_settings);
            ConfigureAutoImportWatcher();
            RefreshUI();
            if (_settings.AutoImportEnabled)
                _ = ScanAutoImportFolderAsync();
            if (_currentPage is AppPage.Library or AppPage.TagEditor)
                _ = RefreshLibraryAsync();
        }
    }

    private void LaunchSerato_Click(object sender, RoutedEventArgs e)
    {
        if (!_serato.Launch(_settings.PreferredSeratoApp))
            MessageBox.Show(this, "DeckReady could not find or launch Serato DJ on this PC.", "Serato", MessageBoxButton.OK, MessageBoxImage.Warning);
        RefreshUI();
    }

    private void ClearFinished_Click(object sender, RoutedEventArgs e)
    {
        var finished = QueueItems.Where(x => x.State is ImportState.Imported or ImportState.Duplicate or ImportState.Failed).ToList();
        foreach (var item in finished) QueueItems.Remove(item);
        RefreshUI();
    }

    private void QueueNav_Click(object sender, RoutedEventArgs e) => ShowQueuePage();
    private async void LibraryNav_Click(object sender, RoutedEventArgs e)
    {
        ShowLibraryPage();
        if (LibraryItems.Count == 0)
            await RefreshLibraryAsync();
    }

    private async void TagEditorNav_Click(object sender, RoutedEventArgs e)
    {
        ShowTagEditorPage();
        if (LibraryItems.Count == 0)
            await RefreshLibraryAsync();
        if (TagEditorGrid.SelectedItem is null && LibraryItems.Count > 0)
            TagEditorGrid.SelectedIndex = 0;
    }
    private void RecentNav_Click(object sender, RoutedEventArgs e) => ShowRecentPage();
    private void DuplicatesNav_Click(object sender, RoutedEventArgs e) => ShowDuplicatesPage();
    private void SeratoDuplicatesNav_Click(object sender, RoutedEventArgs e) => ShowSeratoDuplicatesPage();

    private void ShowQueuePage()
    {
        _currentPage = AppPage.Queue;
        SetNavSelection(QueueNavButton);
        SetPageVisibility(QueuePage);
        PageTitleText.Text = "Import Queue";
        PageSubtitleText.Text = string.IsNullOrWhiteSpace(_settings.LibraryFolder) ? "Choose a music storage folder in Settings." : _settings.LibraryFolder;
        RefreshHeaderActions();
        RefreshSelectionUI();
    }

    private void ShowLibraryPage()
    {
        _currentPage = AppPage.Library;
        SetNavSelection(LibraryNavButton);
        SetPageVisibility(LibraryPage);
        PageTitleText.Text = "Music Library";
        PageSubtitleText.Text = "Browse the songs in your DeckReady music directory, preview them, and edit their actual tags.";
        RefreshHeaderActions();
        RefreshSelectionUI();
    }

    private void ShowTagEditorPage()
    {
        _currentPage = AppPage.TagEditor;
        _selectionMode = false;
        ClearAllSelections();
        SetNavSelection(TagEditorNavButton);
        SetPageVisibility(TagEditorPage);
        PageTitleText.Text = "Tag Editor";
        PageSubtitleText.Text = "Edit a track's title, artist, album, genre, and year without leaving DeckReady.";
        RefreshHeaderActions();
        RefreshSelectionUI();
    }

    private void ShowRecentPage()
    {
        _currentPage = AppPage.Recent;
        SetNavSelection(RecentNavButton);
        SetPageVisibility(RecentPage);
        PageTitleText.Text = "Recent Imports";
        PageSubtitleText.Text = "Double-click a track to edit its actual tags.";
        RefreshHeaderActions();
        RefreshSelectionUI();
    }

    private void ShowDuplicatesPage()
    {
        _currentPage = AppPage.ImportDuplicates;
        SetNavSelection(DuplicatesNavButton);
        SetPageVisibility(DuplicatesPage);
        PageTitleText.Text = "Import Duplicates";
        PageSubtitleText.Text = "Tracks DeckReady matched to an existing file by SHA-256 while importing.";
        RefreshHeaderActions();
        RefreshSelectionUI();
    }

    private void ShowSeratoDuplicatesPage()
    {
        _currentPage = AppPage.SeratoDuplicates;
        SetNavSelection(SeratoDuplicatesNavButton);
        SetPageVisibility(SeratoDuplicatesPage);
        PageTitleText.Text = "Serato Duplicate Checker";
        PageSubtitleText.Text = "Finds exact duplicate files (SHA-256) among tracks referenced by your Serato crates. Main-library tracks that are not in a crate are not scanned yet.";
        RefreshHeaderActions();
        RefreshSelectionUI();
    }

    private void SetPageVisibility(FrameworkElement active)
    {
        foreach (var page in new FrameworkElement[] { QueuePage, LibraryPage, TagEditorPage, RecentPage, DuplicatesPage, SeratoDuplicatesPage })
            page.Visibility = ReferenceEquals(page, active) ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SetNavSelection(System.Windows.Controls.Button active)
    {
        foreach (var button in new[] { QueueNavButton, LibraryNavButton, TagEditorNavButton, RecentNavButton, DuplicatesNavButton, SeratoDuplicatesNavButton })
        {
            button.ClearValue(System.Windows.Controls.Control.BackgroundProperty);
            button.ClearValue(System.Windows.Controls.Control.ForegroundProperty);
        }

        active.Background = (System.Windows.Media.Brush)FindResource("PanelSelectedBrush");
        active.Foreground = (System.Windows.Media.Brush)FindResource("AccentBrush");
    }

    private void RefreshHeaderActions()
    {
        var queue = _currentPage == AppPage.Queue;
        var library = _currentPage == AppPage.Library;
        var tagEditor = _currentPage == AppPage.TagEditor;
        var seratoDuplicates = _currentPage == AppPage.SeratoDuplicates;

        AddMusicButton.Visibility = queue ? Visibility.Visible : Visibility.Collapsed;
        AddFolderButton.Visibility = queue ? Visibility.Visible : Visibility.Collapsed;
        ClearFinishedButton.Visibility = queue ? Visibility.Visible : Visibility.Collapsed;
        RefreshLibraryButton.Visibility = library ? Visibility.Visible : Visibility.Collapsed;
        PlayPauseButton.Visibility = library ? Visibility.Visible : Visibility.Collapsed;
        EditTagsButton.Visibility = library ? Visibility.Visible : Visibility.Collapsed;
        ScanSeratoButton.Visibility = seratoDuplicates ? Visibility.Visible : Visibility.Collapsed;
        SelectModeButton.Visibility = tagEditor ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void RefreshLibrary_Click(object sender, RoutedEventArgs e) => await RefreshLibraryAsync();

    private async Task RefreshLibraryAsync()
    {
        LibraryItems.Clear();
        if (string.IsNullOrWhiteSpace(_settings.LibraryFolder) || !Directory.Exists(_settings.LibraryFolder))
        {
            PageSubtitleText.Text = "Choose or create a music storage folder in Settings first.";
            RefreshUI();
            return;
        }

        var files = await Task.Run(() => Directory.EnumerateFiles(_settings.LibraryFolder, "*", SearchOption.AllDirectories)
            .Where(ImportService.IsSupportedAudio)
            .OrderBy(x => x, StringComparer.OrdinalIgnoreCase)
            .ToList());

        PageSubtitleText.Text = $"Loading {files.Count} tracks from {_settings.LibraryFolder}...";
        foreach (var path in files)
        {
            TrackMetadata metadata;
            try { metadata = await Task.Run(() => _metadata.Read(path)); }
            catch { metadata = new TrackMetadata { Title = Path.GetFileNameWithoutExtension(path) }; }
            LibraryItems.Add(new LibraryTrack { FilePath = path, Metadata = metadata });
        }

        PageSubtitleText.Text = _currentPage == AppPage.TagEditor
            ? $"{LibraryItems.Count} tracks available for tag editing"
            : $"{LibraryItems.Count} tracks • {_settings.LibraryFolder}";
        if (_currentPage == AppPage.TagEditor && TagEditorGrid.SelectedItem is null && LibraryItems.Count > 0)
            TagEditorGrid.SelectedIndex = 0;
        RefreshUI();
    }

    private LibraryTrack? SelectedTagEditorTrack => TagEditorGrid.SelectedItem as LibraryTrack;

    private void TagEditorGrid_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        LoadSelectedTagEditorTrack();
    }

    private void LoadSelectedTagEditorTrack()
    {
        var track = SelectedTagEditorTrack;
        var enabled = track is not null && File.Exists(track.FilePath);

        TagTitleBox.IsEnabled = enabled;
        TagArtistBox.IsEnabled = enabled;
        TagAlbumBox.IsEnabled = enabled;
        TagGenreBox.IsEnabled = enabled;
        TagYearBox.IsEnabled = enabled;
        TagEditorPlayButton.IsEnabled = enabled;
        TagEditorRevealButton.IsEnabled = enabled;
        TagEditorReloadButton.IsEnabled = enabled;
        TagEditorSaveButton.IsEnabled = enabled;

        if (!enabled || track is null)
        {
            TagEditorSelectedTitle.Text = "Select a track";
            TagEditorPathText.Text = "Choose a song from the list to begin editing.";
            TagTitleBox.Text = "";
            TagArtistBox.Text = "";
            TagAlbumBox.Text = "";
            TagGenreBox.Text = "";
            TagYearBox.Text = "";
            TagEditorStatusText.Text = "Tag changes are written to the actual audio file with a safety backup and verification.";
            return;
        }

        TagEditorSelectedTitle.Text = track.DisplayTitle;
        TagEditorPathText.Text = $"{track.Format} • {track.DurationText}\n{track.FilePath}";
        TagTitleBox.Text = track.Metadata.Title;
        TagArtistBox.Text = track.Metadata.Artist;
        TagAlbumBox.Text = track.Metadata.Album;
        TagGenreBox.Text = track.Metadata.Genre;
        TagYearBox.Text = track.Metadata.Year;
        TagEditorStatusText.Text = "Ready. Save Tags writes these values to the actual audio file and verifies the result.";
        TagEditorPlayButton.Content = _audioPreview.IsPlaying && string.Equals(_audioPreview.CurrentPath, track.FilePath, StringComparison.OrdinalIgnoreCase)
            ? "Pause"
            : "Play";
    }

    private void TagEditorSave_Click(object sender, RoutedEventArgs e)
    {
        var track = SelectedTagEditorTrack;
        if (track is null || !File.Exists(track.FilePath)) return;

        var updated = new TrackMetadata
        {
            Title = TagTitleBox.Text.Trim(),
            Artist = TagArtistBox.Text.Trim(),
            Album = TagAlbumBox.Text.Trim(),
            Genre = TagGenreBox.Text.Trim(),
            Year = TagYearBox.Text.Trim(),
            Duration = track.Metadata.Duration
        };

        if (string.IsNullOrWhiteSpace(updated.Title))
        {
            MessageBox.Show(this, "Title cannot be empty.", "Tag Editor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        try
        {
            TagEditorSaveButton.IsEnabled = false;
            TagEditorStatusText.Text = "Saving tags and verifying the audio file...";
            _metadata.WriteWithSafetyBackup(track.FilePath, updated);
            track.Metadata = _metadata.Read(track.FilePath);
            LoadSelectedTagEditorTrack();
            TagEditorStatusText.Text = "Saved and verified successfully.";
            RefreshUI();
        }
        catch (Exception ex)
        {
            TagEditorStatusText.Text = "Save failed. The original file was restored from DeckReady's safety backup.";
            MessageBox.Show(this, $"DeckReady could not save those tags.\n\n{ex.Message}", "Tag Editor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            TagEditorSaveButton.IsEnabled = true;
        }
    }

    private void TagEditorReload_Click(object sender, RoutedEventArgs e)
    {
        var track = SelectedTagEditorTrack;
        if (track is null || !File.Exists(track.FilePath)) return;
        try
        {
            track.Metadata = _metadata.Read(track.FilePath);
            LoadSelectedTagEditorTrack();
            TagEditorStatusText.Text = "Reloaded tags from the audio file.";
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"DeckReady could not reload that file's tags.\n\n{ex.Message}", "Tag Editor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void TagEditorReveal_Click(object sender, RoutedEventArgs e)
    {
        var track = SelectedTagEditorTrack;
        if (track is null || !File.Exists(track.FilePath)) return;
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{track.FilePath}\"") { UseShellExecute = true });
    }

    private void TagEditorPlay_Click(object sender, RoutedEventArgs e)
    {
        var track = SelectedTagEditorTrack;
        if (track is null || !File.Exists(track.FilePath)) return;
        try
        {
            if (_audioPreview.IsPlaying && _audioPreview.CurrentPath?.Equals(track.FilePath, StringComparison.OrdinalIgnoreCase) == true)
                _audioPreview.Pause();
            else
                _audioPreview.Play(track.FilePath);
            UpdateNowPlaying();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"DeckReady could not preview that track.\n\n{ex.Message}", "Tag Editor Preview", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void OpenLibraryFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(_settings.LibraryFolder);
            Process.Start(new ProcessStartInfo("explorer.exe", _settings.LibraryFolder) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"DeckReady could not open your music library.\n\n{ex.Message}", "Music Library", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async void ScanSeratoDuplicates_Click(object sender, RoutedEventArgs e)
    {
        ShowSeratoDuplicatesPage();
        ScanSeratoButton.IsEnabled = false;
        SeratoDuplicateItems.Clear();

        try
        {
            var progress = new Progress<string>(message =>
            {
                PageSubtitleText.Text = message;
                SummaryText.Text = message;
            });
            var results = await _seratoDuplicateScanner.ScanAsync(progress);
            foreach (var result in results)
                SeratoDuplicateItems.Add(result);

            var groups = results.Select(x => x.Hash).Distinct(StringComparer.OrdinalIgnoreCase).Count();
            PageSubtitleText.Text = groups == 0
                ? "No exact duplicate files were found among tracks referenced by Serato crates."
                : $"Found {groups} exact duplicate group{(groups == 1 ? "" : "s")} across {results.Count} files.";
        }
        catch (Exception ex)
        {
            _log.Error($"Serato duplicate scan failed: {ex.Message}");
            MessageBox.Show(this, $"DeckReady could not scan Serato duplicates.\n\n{ex.Message}", "Serato Duplicate Checker", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            ScanSeratoButton.IsEnabled = true;
            RefreshUI();
        }
    }

    private void SelectionCheckBox_Click(object sender, RoutedEventArgs e)
    {
        Dispatcher.BeginInvoke(new Action(UpdateSelectedCount));
    }

    private void Grid_CurrentCellChanged(object? sender, EventArgs e)
    {
        if (!_selectionMode) return;
        Dispatcher.BeginInvoke(new Action(UpdateSelectedCount));
    }

    private void SelectMode_Click(object sender, RoutedEventArgs e)
    {
        _selectionMode = !_selectionMode;
        if (!_selectionMode)
            ClearAllSelections();
        RefreshSelectionUI();
    }

    private void RefreshSelectionUI()
    {
        QueueSelectColumn.Visibility = _selectionMode ? Visibility.Visible : Visibility.Collapsed;
        LibrarySelectColumn.Visibility = _selectionMode ? Visibility.Visible : Visibility.Collapsed;
        RecentSelectColumn.Visibility = _selectionMode ? Visibility.Visible : Visibility.Collapsed;
        DuplicatesSelectColumn.Visibility = _selectionMode ? Visibility.Visible : Visibility.Collapsed;
        SeratoDuplicatesSelectColumn.Visibility = _selectionMode ? Visibility.Visible : Visibility.Collapsed;

        SelectModeButton.Content = _selectionMode ? "Done" : "Select";
        SelectionActionsPanel.Visibility = _selectionMode ? Visibility.Visible : Visibility.Collapsed;
        RemoveSelectedButton.Visibility = _selectionMode && _currentPage == AppPage.Queue ? Visibility.Visible : Visibility.Collapsed;
        UpdateSelectedCount();
    }

    private void ClearAllSelections()
    {
        foreach (var x in QueueItems) x.IsSelected = false;
        foreach (var x in LibraryItems) x.IsSelected = false;
        foreach (var x in RecentItems) x.IsSelected = false;
        foreach (var x in DuplicateItems) x.IsSelected = false;
        foreach (var x in SeratoDuplicateItems) x.IsSelected = false;
    }

    private int SelectedCount() => _currentPage switch
    {
        AppPage.Queue => QueueItems.Count(x => x.IsSelected),
        AppPage.Library => LibraryItems.Count(x => x.IsSelected),
        AppPage.Recent => RecentItems.Count(x => x.IsSelected),
        AppPage.ImportDuplicates => DuplicateItems.Count(x => x.IsSelected),
        AppPage.SeratoDuplicates => SeratoDuplicateItems.Count(x => x.IsSelected),
        _ => 0
    };

    private void UpdateSelectedCount() => SelectedCountText.Text = $"{SelectedCount()} selected";

    private IEnumerable<(string path, TrackMetadata metadata)> SelectedTracks()
    {
        return _currentPage switch
        {
            AppPage.Queue => QueueItems.Where(x => x.IsSelected).Select(x => (x.ActivePath, x.Metadata)),
            AppPage.Library => LibraryItems.Where(x => x.IsSelected).Select(x => (x.FilePath, x.Metadata)),
            AppPage.Recent => RecentItems.Where(x => x.IsSelected).Select(x => (x.FilePath, x.Metadata)),
            AppPage.ImportDuplicates => DuplicateItems.Where(x => x.IsSelected).Select(x => (x.FilePath, x.Metadata)),
            AppPage.SeratoDuplicates => SeratoDuplicateItems.Where(x => x.IsSelected).Select(x => (x.FilePath, x.Metadata)),
            _ => Enumerable.Empty<(string, TrackMetadata)>()
        };
    }

    private (string path, TrackMetadata metadata)? CurrentTrackForAction()
    {
        var selected = SelectedTracks().Where(x => File.Exists(x.path)).ToList();
        if (selected.Count > 0) return selected[0];

        return _currentPage switch
        {
            AppPage.Queue when QueueGrid.SelectedItem is ImportItem item => (item.ActivePath, item.Metadata),
            AppPage.Library when LibraryGrid.SelectedItem is LibraryTrack item => (item.FilePath, item.Metadata),
            AppPage.Recent when RecentGrid.SelectedItem is HistoryRecord item => (item.FilePath, item.Metadata),
            AppPage.ImportDuplicates when DuplicatesGrid.SelectedItem is HistoryRecord item => (item.FilePath, item.Metadata),
            AppPage.SeratoDuplicates when SeratoDuplicatesGrid.SelectedItem is SeratoDuplicateTrack item => (item.FilePath, item.Metadata),
            _ => null
        };
    }

    private void PlayPause_Click(object sender, RoutedEventArgs e)
    {
        var track = CurrentTrackForAction();
        if (track is null || !File.Exists(track.Value.path))
        {
            MessageBox.Show(this, "Select a song to preview first.", "DeckReady Preview", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        try
        {
            if (_audioPreview.IsPlaying && _audioPreview.CurrentPath?.Equals(track.Value.path, StringComparison.OrdinalIgnoreCase) == true)
                _audioPreview.Pause();
            else
                _audioPreview.Play(track.Value.path);
            UpdateNowPlaying();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"DeckReady could not preview that song.\n\n{ex.Message}", "DeckReady Preview", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void BulkPlay_Click(object sender, RoutedEventArgs e) => PlayPause_Click(sender, e);

    private void UpdateNowPlaying()
    {
        PlayPauseButton.Content = _audioPreview.IsPlaying ? "Pause" : "Play";
        if (TagEditorGrid.SelectedItem is LibraryTrack tagTrack)
            TagEditorPlayButton.Content = _audioPreview.IsPlaying && string.Equals(_audioPreview.CurrentPath, tagTrack.FilePath, StringComparison.OrdinalIgnoreCase) ? "Pause" : "Play";

        var path = _audioPreview.CurrentPath;
        if (string.IsNullOrWhiteSpace(path))
        {
            NowPlayingPanel.Visibility = Visibility.Collapsed;
            NowPlayingText.Text = "";
            return;
        }

        var metadata = MetadataForPath(path);
        var title = !string.IsNullOrWhiteSpace(metadata?.Title)
            ? metadata!.Title
            : Path.GetFileNameWithoutExtension(path);
        var artist = !string.IsNullOrWhiteSpace(metadata?.Artist)
            ? metadata!.Artist
            : "Unknown Artist";
        var state = _audioPreview.IsPlaying ? "Playing" : "Paused";

        NowPlayingText.Text = $"{state} • {title} — {artist}";
        NowPlayingPanel.Visibility = Visibility.Visible;
    }

    private TrackMetadata? MetadataForPath(string path)
    {
        var library = LibraryItems.FirstOrDefault(x => x.FilePath.Equals(path, StringComparison.OrdinalIgnoreCase));
        if (library is not null) return library.Metadata;

        var queue = QueueItems.FirstOrDefault(x => x.ActivePath.Equals(path, StringComparison.OrdinalIgnoreCase));
        if (queue is not null) return queue.Metadata;

        var recent = RecentItems.FirstOrDefault(x => x.FilePath.Equals(path, StringComparison.OrdinalIgnoreCase));
        if (recent is not null) return recent.Metadata;

        var duplicate = DuplicateItems.FirstOrDefault(x => x.FilePath.Equals(path, StringComparison.OrdinalIgnoreCase));
        if (duplicate is not null) return duplicate.Metadata;

        var seratoDuplicate = SeratoDuplicateItems.FirstOrDefault(x => x.FilePath.Equals(path, StringComparison.OrdinalIgnoreCase));
        return seratoDuplicate?.Metadata;
    }

    private void EditSelectedTags_Click(object sender, RoutedEventArgs e)
    {
        var tracks = SelectedTracks().Where(x => File.Exists(x.path)).ToList();
        if (tracks.Count == 0)
        {
            var current = CurrentTrackForAction();
            if (current is not null && File.Exists(current.Value.path)) tracks.Add(current.Value);
        }

        if (tracks.Count != 1)
        {
            MessageBox.Show(this, "Select exactly one song to edit its tags.", "Edit Tags", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var (path, metadata) = tracks[0];
        EditTrack(path, metadata, updated => ApplyMetadataUpdate(path, updated));
    }

    private void ApplyMetadataUpdate(string path, TrackMetadata updated)
    {
        var library = LibraryItems.FirstOrDefault(x => x.FilePath.Equals(path, StringComparison.OrdinalIgnoreCase));
        if (library is not null) library.Metadata = updated;

        foreach (var history in _historyStore.Records.Where(x => x.FilePath.Equals(path, StringComparison.OrdinalIgnoreCase)))
            history.Metadata = updated.Clone();
        _historyStore.Save();

        foreach (var item in QueueItems.Where(x => x.ActivePath.Equals(path, StringComparison.OrdinalIgnoreCase)))
            item.Metadata = updated.Clone();

        foreach (var item in SeratoDuplicateItems.Where(x => x.FilePath.Equals(path, StringComparison.OrdinalIgnoreCase)))
            item.Metadata = updated.Clone();

        RefreshHistoryCollections();
    }

    private void BulkReveal_Click(object sender, RoutedEventArgs e)
    {
        var paths = SelectedTracks().Select(x => x.path).Where(File.Exists).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (paths.Count == 0)
        {
            var current = CurrentTrackForAction();
            if (current is not null && File.Exists(current.Value.path)) paths.Add(current.Value.path);
        }

        if (paths.Count == 0) return;
        foreach (var path in paths.Take(10))
        {
            try { Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true }); }
            catch { }
        }
    }

    private void RemoveSelected_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPage != AppPage.Queue) return;
        var selected = QueueItems.Where(x => x.IsSelected).ToList();
        foreach (var item in selected) QueueItems.Remove(item);
        RefreshSelectionUI();
        RefreshUI();
    }

    private void RefreshHistoryCollections()
    {
        RecentItems.Clear();
        DuplicateItems.Clear();
        foreach (var record in _historyStore.Records)
        {
            RecentItems.Add(record);
            if (record.WasDuplicate) DuplicateItems.Add(record);
        }
    }

    private void RefreshUI()
    {
        _serato.RefreshStatus();
        SeratoStatusText.Text = _serato.StatusText;
        LibraryPathText.Text = string.IsNullOrWhiteSpace(_settings.LibraryFolder) ? "No storage folder selected" : _settings.LibraryFolder;
        AutoImportStatusText.Text = !_settings.AutoImportEnabled
            ? "Disabled"
            : _autoImportWatcher?.IsRunning == true
                ? $"Watching: {ShortenPath(_settings.AutoImportFolder, 30)}"
                : "Not watching — check folder settings";

        var ready = QueueItems.Count(x => x.State == ImportState.Ready);
        var imported = QueueItems.Count(x => x.State == ImportState.Imported);
        var duplicates = QueueItems.Count(x => x.State == ImportState.Duplicate);
        var waiting = QueueItems.Count(x => x.State == ImportState.WaitingForSerato);

        SummaryText.Text = _currentPage switch
        {
            AppPage.Library => $"{LibraryItems.Count} library tracks",
            AppPage.TagEditor => $"{LibraryItems.Count} tracks available for tag editing",
            AppPage.Recent => $"{RecentItems.Count} recent imports",
            AppPage.ImportDuplicates => $"{DuplicateItems.Count} import duplicates",
            AppPage.SeratoDuplicates => $"{SeratoDuplicateItems.Select(x => x.Hash).Distinct(StringComparer.OrdinalIgnoreCase).Count()} duplicate groups • {SeratoDuplicateItems.Count} files",
            _ => $"{ready} ready • {imported} imported • {duplicates} duplicates" + (waiting > 0 ? $" • {waiting} waiting for Serato" : "")
        };

        RetrySeratoButton.Visibility = waiting > 0 ? Visibility.Visible : Visibility.Collapsed;
        ImportReadyButton.Visibility = _currentPage == AppPage.Queue ? Visibility.Visible : Visibility.Collapsed;
        ImportReadyButton.IsEnabled = ready > 0;
        UpdateSelectedCount();
        UpdateNowPlaying();
    }

    private void ConfigureAutoImportWatcher()
    {
        _autoImportWatcher?.Dispose();
        _autoImportWatcher = null;

        if (!_settings.AutoImportEnabled) return;
        if (PathsOverlap(_settings.LibraryFolder, _settings.AutoImportFolder))
        {
            _log.Error("Auto Import disabled because the Inbox overlaps the permanent music library.");
            return;
        }

        Directory.CreateDirectory(_settings.AutoImportFolder);
        _autoImportWatcher = new AutoImportWatcher(_log);
        _autoImportWatcher.ItemReady += path =>
        {
            Dispatcher.BeginInvoke(new Action(async () => await ProcessAutoImportSourcesAsync([path])));
        };
        _autoImportWatcher.Start(_settings.AutoImportFolder);
    }

    private async Task ScanAutoImportFolderAsync()
    {
        if (!_settings.AutoImportEnabled) return;
        if (!Directory.Exists(_settings.AutoImportFolder)) Directory.CreateDirectory(_settings.AutoImportFolder);

        var sources = Directory.EnumerateFileSystemEntries(_settings.AutoImportFolder, "*", SearchOption.TopDirectoryOnly)
            .Where(IsAutoImportCandidate)
            .Where(path => !_autoImportState.IsAlreadyProcessed(path))
            .ToList();

        if (sources.Count == 0)
        {
            RefreshUI();
            return;
        }

        _log.Info($"Auto Import startup scan found {sources.Count} item(s) in the DeckReady Inbox.");
        await ProcessAutoImportSourcesAsync(sources);
    }

    private async Task ProcessAutoImportSourcesAsync(IEnumerable<string> incoming)
    {
        await _autoImportGate.WaitAsync();
        try
        {
            var sources = incoming
                .Where(path => File.Exists(path) || Directory.Exists(path))
                .Select(Path.GetFullPath)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Where(IsAutoImportCandidate)
                .Where(path => !_autoImportState.IsAlreadyProcessed(path))
                .ToList();

            if (sources.Count == 0) return;

            var existingIds = QueueItems.Select(x => x.Id).ToHashSet();
            await AddSourcesAsync(sources, showErrors: false);

            var newItems = QueueItems
                .Where(x => !existingIds.Contains(x.Id) && x.State == ImportState.Ready)
                .ToList();

            foreach (var item in newItems)
            {
                item.IsAutoImport = true;
                item.StatusMessage = "Ready • DeckReady Inbox";
            }

            if (newItems.Count == 0)
            {
                foreach (var source in sources.Where(path => File.Exists(path) || Directory.Exists(path)))
                    _autoImportState.MarkProcessed(source);
                return;
            }

            ShowQueuePage();
            RefreshUI();
            await ImportItemsAsync(newItems, interactive: false);

            foreach (var source in sources)
            {
                var related = RelatedItemsForAutoSource(newItems, source).ToList();
                if (related.Count > 0 && related.All(x => x.State is ImportState.Imported or ImportState.Duplicate or ImportState.WaitingForSerato))
                {
                    if (File.Exists(source) || Directory.Exists(source))
                        _autoImportState.MarkProcessed(source);
                }
            }
        }
        catch (Exception ex)
        {
            _log.Error($"Auto Import failed: {ex.Message}");
        }
        finally
        {
            _autoImportGate.Release();
            RefreshUI();
        }
    }

    private static IEnumerable<ImportItem> RelatedItemsForAutoSource(IEnumerable<ImportItem> items, string source)
    {
        var full = Path.GetFullPath(source);
        if (Directory.Exists(source) || Path.GetExtension(source).Equals(".zip", StringComparison.OrdinalIgnoreCase))
            return items.Where(x => !string.IsNullOrWhiteSpace(x.SourceContainerPath) && Path.GetFullPath(x.SourceContainerPath!).Equals(full, StringComparison.OrdinalIgnoreCase));
        return items.Where(x => Path.GetFullPath(x.SourcePath).Equals(full, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsAutoImportCandidate(string path)
    {
        if (Directory.Exists(path)) return true;
        if (!File.Exists(path)) return false;
        if (Path.GetFileName(path).StartsWith(".", StringComparison.Ordinal)) return false;
        return ImportService.IsSupportedAudio(path) || Path.GetExtension(path).Equals(".zip", StringComparison.OrdinalIgnoreCase);
    }

    private async void ScanAutoImportFolder_Click(object sender, RoutedEventArgs e) => await ScanAutoImportFolderAsync();

    private void OpenAutoImportFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(_settings.AutoImportFolder);
            Process.Start(new ProcessStartInfo("explorer.exe", _settings.AutoImportFolder) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"DeckReady could not open the Inbox.\n\n{ex.Message}", "DeckReady Inbox", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static bool IsInsideFolder(string path, string folder)
    {
        if (string.IsNullOrWhiteSpace(path) || string.IsNullOrWhiteSpace(folder)) return false;
        var fullPath = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var fullFolder = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return fullPath.Equals(fullFolder, StringComparison.OrdinalIgnoreCase)
            || fullPath.StartsWith(fullFolder + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    private static bool PathsOverlap(string first, string second)
    {
        if (string.IsNullOrWhiteSpace(first) || string.IsNullOrWhiteSpace(second)) return false;
        var a = Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var b = Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return a.Equals(b, StringComparison.OrdinalIgnoreCase)
            || a.StartsWith(b + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            || b.StartsWith(a + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    private static string ShortenPath(string path, int max)
    {
        if (string.IsNullOrWhiteSpace(path) || path.Length <= max) return path;
        return "…" + path[^Math.Max(1, max - 1)..];
    }

    private async void Window_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] files)
            await AddSourcesAsync(files);
    }

    private void Window_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private const string GitHubUrl = "https://github.com/YourCyanDev/DeckReady";
    private const string DiscordUrl = "https://discord.gg/BuVnCQ5fG9";
    private const string IssuesUrl = "https://github.com/YourCyanDev/DeckReady/issues";

    private void OpenGitHub_Click(object sender, RoutedEventArgs e) => OpenExternalUrl(GitHubUrl);

    private void OpenDiscord_Click(object sender, RoutedEventArgs e) => OpenExternalUrl(DiscordUrl);

    private void ReportIssue_Click(object sender, RoutedEventArgs e) => OpenExternalUrl(IssuesUrl);

    private void OpenExternalUrl(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            _log.Error($"Could not open URL '{url}': {ex.Message}");
            MessageBox.Show(this,
                $"DeckReady could not open your web browser.\n\n{url}\n\n{ex.Message}",
                "Open Link", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void About_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show(this,
            "DeckReady for Windows\nAlpha a1.09.2\n\nOrganize. Prepare. Play.\n\nIncludes Music Library browsing, song selection tools, the Serato duplicate checker, DeckReady Inbox automation, and community/support links in the Help menu.",
            "About DeckReady", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void Exit_Click(object sender, RoutedEventArgs e) => Close();
}
