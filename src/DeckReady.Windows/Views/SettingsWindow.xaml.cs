using System.Windows;
using System.Windows.Controls;
using DeckReady.Models;
using DeckReady.Services;
using Microsoft.Win32;

namespace DeckReady.Views;

public partial class SettingsWindow : Window
{
    private readonly AppSettings _settings;
    private readonly SeratoService _serato;
    private readonly List<ComboBox> _additionalOrganizationBoxes = new();
    private sealed record OrganizationOption(OrganizationMode Mode, string Label);
    private static readonly OrganizationOption[] OrganizationOptions =
    {
        new(OrganizationMode.NoSubfolders, "No subfolders"),
        new(OrganizationMode.Artist, "Artist"),
        new(OrganizationMode.Genre, "Genre"),
        new(OrganizationMode.Year, "Year"),
        new(OrganizationMode.YearArtist, "Year → Artist (songs inside)"),
        new(OrganizationMode.GenreArtist, "Genre → Artist (songs inside)")
    };

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
        OrganizationBox.ItemsSource = OrganizationOptions;
        OrganizationBox.DisplayMemberPath = "Label";
        OrganizationBox.SelectedValuePath = "Mode";
        OrganizationBox.SelectedValue = settings.OrganizationMode;
        foreach (var mode in settings.AdditionalOrganizationModes ?? new())
            if (mode != settings.OrganizationMode &&
                mode is OrganizationMode.YearArtist or OrganizationMode.GenreArtist &&
                !_additionalOrganizationBoxes.Any(x => Equals(x.SelectedValue, mode)))
                AddOrganizationRow(mode);
        OrganizationBox.SelectionChanged += (_, _) => RefreshAddOrganizationButton();
        RefreshAddOrganizationButton();
        WriteTagsCheck.IsChecked = settings.WriteMetadataToFiles;
        DeleteContainerCheck.IsChecked = settings.DeleteSourceContainerAfterImport;
        AutoSeratoCheck.IsChecked = settings.AutomaticSeratoImport;

        PreferredSeratoBox.ItemsSource = new[] { "Serato DJ Pro", "Serato DJ Lite" };
        PreferredSeratoBox.SelectedIndex = settings.PreferredSeratoApp == SeratoAppPreference.Lite ? 1 : 0;
        LaunchSeratoCheck.IsChecked = settings.LaunchSeratoWhenNeeded;
        CrateNameBox.Text = settings.SeratoCrateName;
        RefreshSeratoControls();
    }

    private IEnumerable<OrganizationMode> SelectedOrganizationModes() =>
        new[] { (OrganizationMode)(OrganizationBox.SelectedValue ?? OrganizationMode.NoSubfolders) }
            .Concat(_additionalOrganizationBoxes.Select(x =>
                (OrganizationMode)(x.SelectedValue ?? OrganizationMode.YearArtist)));

    private void AddOrganization_Click(object sender, RoutedEventArgs e)
    {
        var selected = SelectedOrganizationModes().ToHashSet();
        var next = OrganizationOptions.FirstOrDefault(x =>
            x.Mode is OrganizationMode.YearArtist or OrganizationMode.GenreArtist && !selected.Contains(x.Mode));
        if (next is not null) AddOrganizationRow(next.Mode);
        RefreshAddOrganizationButton();
    }

    private void AddOrganizationRow(OrganizationMode mode)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(170, 0, 0, 8) };
        var box = new ComboBox
        {
            Width = 260, ItemsSource = OrganizationOptions.Where(x =>
                x.Mode is OrganizationMode.YearArtist or OrganizationMode.GenreArtist).ToArray(),
            DisplayMemberPath = "Label", SelectedValuePath = "Mode", SelectedValue = mode
        };
        var remove = new Button { Content = "Remove", Margin = new Thickness(8, 0, 0, 0) };
        remove.Click += (_, _) =>
        {
            _additionalOrganizationBoxes.Remove(box);
            AdditionalOrganizationRows.Children.Remove(row);
            RefreshAddOrganizationButton();
        };
        box.SelectionChanged += (_, _) => RefreshAddOrganizationButton();
        row.Children.Add(box);
        row.Children.Add(remove);
        _additionalOrganizationBoxes.Add(box);
        AdditionalOrganizationRows.Children.Add(row);
    }

    private void RefreshAddOrganizationButton()
    {
        var selected = SelectedOrganizationModes().ToHashSet();
        AddOrganizationButton.IsEnabled = _additionalOrganizationBoxes.Count < 2 &&
            new[] { OrganizationMode.YearArtist, OrganizationMode.GenreArtist }.Any(x => !selected.Contains(x));
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

        var modes = SelectedOrganizationModes().ToList();
        if (modes.Distinct().Count() != modes.Count)
        {
            MessageBox.Show(this, "Choose each organization option only once, or remove the duplicate row.",
                "Duplicate Organization", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        _settings.LibraryFolder = library;
        _settings.AutoImportFolder = inbox;
        _settings.AutoImportEnabled = AutoImportEnabledCheck.IsChecked == true;
        _settings.ClearAutoImportFolderAfterImport = ClearAutoImportCheck.IsChecked == true;
        _settings.ImportMode = (ImportMode)(ImportModeBox.SelectedItem ?? ImportMode.Copy);
        _settings.OrganizationMode = (OrganizationMode)(OrganizationBox.SelectedValue ?? OrganizationMode.NoSubfolders);
        _settings.AdditionalOrganizationModes = modes.Skip(1).ToList();
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
