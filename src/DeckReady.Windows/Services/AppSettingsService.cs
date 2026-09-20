using System.Text.Json;
using System.Text.Json.Serialization;
using DeckReady.Models;

namespace DeckReady.Services;

public sealed class AppSettingsService
{
    private readonly JsonSerializerOptions _options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public AppSettings Load()
    {
        AppPaths.Ensure();
        try
        {
            AppSettings settings;
            if (!File.Exists(AppPaths.SettingsPath))
            {
                settings = new AppSettings();
            }
            else
            {
                settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(AppPaths.SettingsPath), _options) ?? new AppSettings();
            }

            Normalize(settings);
            return settings;
        }
        catch
        {
            var settings = new AppSettings();
            Normalize(settings);
            return settings;
        }
    }

    public void Save(AppSettings settings)
    {
        AppPaths.Ensure();
        Normalize(settings);
        File.WriteAllText(AppPaths.SettingsPath, JsonSerializer.Serialize(settings, _options));
    }

    private static void Normalize(AppSettings settings)
    {
        if (string.IsNullOrWhiteSpace(settings.LibraryFolder))
            settings.LibraryFolder = AppSettings.DefaultLibraryFolder;
        if (string.IsNullOrWhiteSpace(settings.AutoImportFolder))
            settings.AutoImportFolder = AppSettings.DefaultAutoImportFolder;

        Directory.CreateDirectory(settings.LibraryFolder);
        Directory.CreateDirectory(settings.AutoImportFolder);
    }
}
