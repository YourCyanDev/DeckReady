namespace DeckReady.Services;

public static class AppPaths
{
    public static string AppDataRoot { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "DeckReady");

    public static string SettingsPath => Path.Combine(AppDataRoot, "settings.json");
    public static string HistoryPath => Path.Combine(AppDataRoot, "history.json");
    public static string LogPath => Path.Combine(AppDataRoot, "deckready.log");
    public static string SeratoBackupRoot => Path.Combine(AppDataRoot, "Serato Backups");

    public static void Ensure()
    {
        Directory.CreateDirectory(AppDataRoot);
        Directory.CreateDirectory(SeratoBackupRoot);
    }
}
