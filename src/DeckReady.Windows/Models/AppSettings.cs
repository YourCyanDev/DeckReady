namespace DeckReady.Models;

public enum ImportMode
{
    Copy,
    Move
}

public enum OrganizationMode
{
    NoSubfolders,
    Artist,
    Genre,
    Year,
    YearArtist,
    GenreArtist
}

public enum SeratoAppPreference
{
    Pro,
    Lite
}

public sealed class AppSettings
{
    public static string DefaultDeckReadyFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyMusic), "DeckReady");
    public static string DefaultLibraryFolder => Path.Combine(DefaultDeckReadyFolder, "Library");
    public static string DefaultAutoImportFolder => Path.Combine(DefaultDeckReadyFolder, "Inbox");

    public string LibraryFolder { get; set; } = DefaultLibraryFolder;
    public ImportMode ImportMode { get; set; } = ImportMode.Copy;
    public OrganizationMode OrganizationMode { get; set; } = OrganizationMode.NoSubfolders;
    public List<OrganizationMode> AdditionalOrganizationModes { get; set; } = new();
    public bool AutomaticSeratoImport { get; set; } = true;
    public bool ShowSeratoRestartPrompt { get; set; } = true;
    // Legacy property name retained so existing settings.json files stay compatible.
    // a1.10.0+: this only controls reopening Serato after DeckReady had to close a running Serato instance.
    public bool LaunchSeratoWhenNeeded { get; set; } = true;
    public SeratoAppPreference PreferredSeratoApp { get; set; } = SeratoAppPreference.Pro;
    public bool WriteMetadataToFiles { get; set; } = true;
    public string SeratoCrateName { get; set; } = "DeckReady Imports";
    public bool DeleteSourceContainerAfterImport { get; set; } = false;

    // DeckReady Inbox / watched-folder automation.
    public bool AutoImportEnabled { get; set; } = true;
    public string AutoImportFolder { get; set; } = DefaultAutoImportFolder;
    public bool ClearAutoImportFolderAfterImport { get; set; } = true;
}
