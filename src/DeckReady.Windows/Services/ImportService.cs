using DeckReady.Models;

namespace DeckReady.Services;

public sealed class ImportService
{
    private readonly MetadataService _metadata;
    private readonly LogService _log;

    public ImportService(MetadataService metadata, LogService log)
    {
        _metadata = metadata;
        _log = log;
    }

    public async Task<Dictionary<string, string>> BuildLibraryHashIndexAsync(string libraryFolder)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!Directory.Exists(libraryFolder)) return result;

        var files = Directory.EnumerateFiles(libraryFolder, "*", SearchOption.AllDirectories)
            .Where(IsSupportedAudio)
            .ToList();

        foreach (var file in files)
        {
            try
            {
                var hash = await HashService.Sha256Async(file);
                result.TryAdd(hash, file);
            }
            catch (Exception ex)
            {
                _log.Warning($"Could not hash library file '{file}': {ex.Message}");
            }
        }
        return result;
    }

    public async Task<(string destinationPath, bool duplicate)> ImportAsync(
        ImportItem item,
        AppSettings settings,
        Dictionary<string, string> hashIndex)
    {
        if (string.IsNullOrWhiteSpace(settings.LibraryFolder))
            throw new InvalidOperationException("Choose a music storage folder in Settings first.");

        Directory.CreateDirectory(settings.LibraryFolder);

        var sourceHash = await HashService.Sha256Async(item.SourcePath);
        if (hashIndex.TryGetValue(sourceHash, out var existing))
            return (existing, true);

        var folder = ResolveDestinationFolder(settings, item.Metadata);
        Directory.CreateDirectory(folder);

        var desired = Path.Combine(folder, Path.GetFileName(item.SourcePath));
        var destination = UniquePath(desired);

        if (settings.ImportMode == ImportMode.Move && !IsTemporaryExtraction(item.SourcePath))
        {
            try
            {
                File.Move(item.SourcePath, destination);
            }
            catch (IOException)
            {
                // Cross-volume moves are not guaranteed to succeed as a single filesystem move.
                File.Copy(item.SourcePath, destination);
                File.Delete(item.SourcePath);
            }
        }
        else
        {
            File.Copy(item.SourcePath, destination);
        }

        if (settings.WriteMetadataToFiles)
            _metadata.WriteWithSafetyBackup(destination, item.Metadata);

        var destHash = await HashService.Sha256Async(destination);
        hashIndex[destHash] = destination;
        return (destination, false);
    }

    public static bool IsSupportedAudio(string path) =>
        MetadataService.SupportedExtensions.Contains(Path.GetExtension(path));

    public static string SanitizeFolderName(string value)
    {
        var cleaned = value.Trim();
        if (string.IsNullOrWhiteSpace(cleaned)) return "Unknown";
        foreach (var c in Path.GetInvalidFileNameChars())
            cleaned = cleaned.Replace(c, '-');
        cleaned = cleaned.Trim().TrimEnd('.');
        return string.IsNullOrWhiteSpace(cleaned) ? "Unknown" : cleaned;
    }

    public static string ResolveDestinationFolder(AppSettings settings, TrackMetadata metadata)
    {
        var baseFolder = settings.LibraryFolder;
        return settings.OrganizationMode switch
        {
            OrganizationMode.Artist => Path.Combine(baseFolder, SanitizeFolderName(string.IsNullOrWhiteSpace(metadata.Artist) ? "Unknown Artist" : metadata.Artist)),
            OrganizationMode.Genre => Path.Combine(baseFolder, SanitizeFolderName(string.IsNullOrWhiteSpace(metadata.Genre) ? "Unknown Genre" : metadata.Genre)),
            OrganizationMode.GenreArtist => Path.Combine(baseFolder,
                SanitizeFolderName(string.IsNullOrWhiteSpace(metadata.Genre) ? "Unknown Genre" : metadata.Genre),
                SanitizeFolderName(string.IsNullOrWhiteSpace(metadata.Artist) ? "Unknown Artist" : metadata.Artist)),
            OrganizationMode.YearArtist => Path.Combine(baseFolder,
                SanitizeFolderName(string.IsNullOrWhiteSpace(metadata.Year) ? "Unknown Year" : metadata.Year),
                SanitizeFolderName(string.IsNullOrWhiteSpace(metadata.Artist) ? "Unknown Artist" : metadata.Artist)),
            OrganizationMode.Year => Path.Combine(baseFolder, SanitizeFolderName(string.IsNullOrWhiteSpace(metadata.Year) ? "Unknown Year" : metadata.Year)),
            _ => baseFolder
        };
    }

    private static string UniquePath(string path)
    {
        if (!File.Exists(path)) return path;
        var directory = Path.GetDirectoryName(path)!;
        var name = Path.GetFileNameWithoutExtension(path);
        var extension = Path.GetExtension(path);

        for (var i = 2; i < 10000; i++)
        {
            var candidate = Path.Combine(directory, $"{name} ({i}){extension}");
            if (!File.Exists(candidate)) return candidate;
        }

        return Path.Combine(directory, $"{name}-{Guid.NewGuid():N}{extension}");
    }

    private static bool IsTemporaryExtraction(string path)
    {
        var tempRoot = Path.GetFullPath(Path.GetTempPath());
        var full = Path.GetFullPath(path);
        return full.StartsWith(tempRoot, StringComparison.OrdinalIgnoreCase);
    }
}
