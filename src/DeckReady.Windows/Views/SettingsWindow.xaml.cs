using System.Windows;
using DeckReady.Models;
using DeckReady.Services;
using Microsoft.Win32;

namespace DeckReady.Views;

public partial class SettingsWindow : Window
{
    private readonly AppSettings _settings;
    private readonly SeratoService _serato;

    public SettingsWindow(AppSettings settings, SeratoService serato)
    {
        _settings = settings;
        _serato = serato;
        InitializeComponent();

        LibraryFolderBox.Text = settings.LibraryFolder;
        AutoImportFolderBox.Text = settings.AutoImportFolder;
        AutoImportEnabledCheck.IsChecked = settings.AutoImportEnabled;
        ClearAutoImportCheck.IsChecked = settings.ClearAutoImportFolderAfterImport;
        ImportModeBox.ItemsSource = Enum.GetValues<ImportMode>();
        ImportModeBox.SelectedItem = settings.ImportMode;
        OrganizationBox.ItemsSource = new[]
        {
            new { Mode = OrganizationMode.NoSubfolders, Label = "No subfolders" },
            new { Mode = OrganizationMode.Artist, Label = "Artist" },
            new { Mode = OrganizationMode.Genre, Label = "Genre" },
            new { Mode = OrganizationMode.Year, Label = "Year" },
            new { Mode = OrganizationMode.YearArtist, Label = "Year → Artist (songs inside)" },
            new { Mode = OrganizationMode.GenreArtist, Label = "Genre → Artist (songs inside)" }
        };
        OrganizationBox.DisplayMemberPath = "Label";
        OrganizationBox.SelectedValuePath = "Mode";
        OrganizationBox.SelectedValue = settings.OrganizationMode;
        WriteTagsCheck.IsChecked = settings.WriteMetadataToFiles;
        DeleteContainerCheck.IsChecked = settings.DeleteSourceContainerAfterImport;
        AutoSeratoCheck.IsChecked = settings.AutomaticSeratoImport;

        PreferredSeratoBox.ItemsSource = new[] { "Serato DJ Pro", "Serato DJ Lite" };
        PreferredSeratoBox.SelectedIndex = settings.PreferredSeratoApp == SeratoAppPreference.Lite ? 1 : 0;
        LaunchSeratoCheck.IsChecked = settings.LaunchSeratoWhenNeeded;
        CrateNameBox.Text = settings.SeratoCrateName;
        RefreshSeratoControls();
    }

    private void BrowseLibrary_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Choose DeckReady Music Library",
            Multiselect = false,
            InitialDirectory = Directory.Exists(LibraryFolderBox.Text)
                ? LibraryFolderBox.Text
                : Environment.GetFolderPath(Environment.SpecialFolder.MyMusic)
        };

        if (dialog.ShowDialog(this) == true)
            LibraryFolderBox.Text = dialog.FolderName;
    }

    private void BrowseAutoImport_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Choose DeckReady Inbox",
            Multiselect = false,
            InitialDirectory = Directory.Exists(AutoImportFolderBox.Text)
                ? AutoImportFolderBox.Text
                : AppSettings.DefaultAutoImportFolder
        };

        if (dialog.ShowDialog(this) == true)
            AutoImportFolderBox.Text = dialog.FolderName;
    }

    private void LaunchSeratoCheck_Changed(object sender, RoutedEventArgs e) => RefreshSeratoControls();

    private void RefreshSeratoControls()
    {
        if (!IsInitialized) return;

        _serato.RefreshStatus();
        var pro = _serato.IsProInstalled;
        var lite = _serato.IsLiteInstalled;
        var launchEnabled = LaunchSeratoCheck.IsChecked == true;

        if (pro && lite)
        {
            SeratoDetectionText.Text = "Detected Serato DJ Pro and Serato DJ Lite.";
            PreferredSeratoBox.IsEnabled = launchEnabled;
            PreferredSeratoHelpText.Text = launchEnabled
                ? "Choose which Serato app DeckReady opens after a successful sync."
                : "Turn on “Open Serato when sync is complete” to choose Pro or Lite.";
        }
        else if (pro)
        {
            SeratoDetectionText.Text = "Detected Serato DJ Pro.";
            PreferredSeratoBox.SelectedIndex = 0;
            PreferredSeratoBox.IsEnabled = false;
            PreferredSeratoHelpText.Text = "Only Serato DJ Pro is installed, so DeckReady will use it automatically.";
        }
        else if (lite)
        {
            SeratoDetectionText.Text = "Detected Serato DJ Lite.";
            PreferredSeratoBox.SelectedIndex = 1;
            PreferredSeratoBox.IsEnabled = false;
            PreferredSeratoHelpText.Text = "Only Serato DJ Lite is installed, so DeckReady will use it automatically.";
        }
        else
        {
            SeratoDetectionText.Text = "Serato DJ Pro or Lite was not detected on this PC.";
            PreferredSeratoBox.IsEnabled = false;
            PreferredSeratoHelpText.Text = "The selector will become available when DeckReady detects Serato.";
        }
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var library = NormalizePath(LibraryFolderBox.Text);
        var inbox = NormalizePath(AutoImportFolderBox.Text);

        if (PathsOverlap(library, inbox))
        {
            MessageBox.Show(this,
                "The DeckReady Inbox and permanent music library must be separate folders. Choose folders that are not inside one another.",
                "Folder Conflict", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        _settings.LibraryFolder = library;
        _settings.AutoImportFolder = inbox;
        _settings.AutoImportEnabled = AutoImportEnabledCheck.IsChecked == true;
        _settings.ClearAutoImportFolderAfterImport = ClearAutoImportCheck.IsChecked == true;
        _settings.ImportMode = (ImportMode)(ImportModeBox.SelectedItem ?? ImportMode.Copy);
        _settings.OrganizationMode = (OrganizationMode)(OrganizationBox.SelectedValue ?? OrganizationMode.NoSubfolders);
        _settings.WriteMetadataToFiles = WriteTagsCheck.IsChecked == true;
        _settings.DeleteSourceContainerAfterImport = DeleteContainerCheck.IsChecked == true;
        _settings.AutomaticSeratoImport = AutoSeratoCheck.IsChecked == true;
        _settings.LaunchSeratoWhenNeeded = LaunchSeratoCheck.IsChecked == true;
        _settings.PreferredSeratoApp = PreferredSeratoBox.SelectedIndex == 1
            ? SeratoAppPreference.Lite
            : SeratoAppPreference.Pro;
        _settings.SeratoCrateName = string.IsNullOrWhiteSpace(CrateNameBox.Text) ? "DeckReady Imports" : CrateNameBox.Text.Trim();

        Directory.CreateDirectory(_settings.LibraryFolder);
        Directory.CreateDirectory(_settings.AutoImportFolder);
        DialogResult = true;
        Close();
    }

    private static string NormalizePath(string value)
    {
        var fallback = string.IsNullOrWhiteSpace(value) ? AppSettings.DefaultDeckReadyFolder : value.Trim();
        return Path.GetFullPath(fallback).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static bool PathsOverlap(string first, string second)
    {
        if (first.Equals(second, StringComparison.OrdinalIgnoreCase)) return true;
        return first.StartsWith(second + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            || second.StartsWith(first + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
