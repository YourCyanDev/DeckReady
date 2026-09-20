using DeckReady.Models;

namespace DeckReady.Services;

public sealed class MetadataService
{
    public static readonly HashSet<string> SupportedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp3", ".m4a", ".wav", ".wave", ".aiff", ".aif", ".flac", ".aac"
    };

    public TrackMetadata Read(string path)
    {
        using var file = TagLib.File.Create(path);
        return new TrackMetadata
        {
            Title = file.Tag.Title ?? "",
            Artist = file.Tag.FirstPerformer ?? "",
            Album = file.Tag.Album ?? "",
            Genre = file.Tag.FirstGenre ?? "",
            Year = file.Tag.Year > 0 ? file.Tag.Year.ToString() : "",
            Duration = file.Properties.Duration
        };
    }

    public void WriteWithSafetyBackup(string path, TrackMetadata metadata)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new IOException("Could not determine track directory.");
        var backup = Path.Combine(directory, $".deckready-{Guid.NewGuid():N}-{Path.GetFileName(path)}.bak");

        File.Copy(path, backup, overwrite: true);
        try
        {
            using (var file = TagLib.File.Create(path))
            {
                file.Tag.Title = Clean(metadata.Title);
                file.Tag.Performers = string.IsNullOrWhiteSpace(metadata.Artist) ? [] : [Clean(metadata.Artist)];
                file.Tag.Album = Clean(metadata.Album);
                file.Tag.Genres = string.IsNullOrWhiteSpace(metadata.Genre) ? [] : [Clean(metadata.Genre)];
                file.Tag.Year = ParseYear(metadata.Year);
                file.Save();
            }

            var verified = Read(path);
            if (!Equivalent(metadata, verified))
                throw new IOException("The metadata write completed but verification did not match.");

            File.Delete(backup);
        }
        catch
        {
            try
            {
                File.Copy(backup, path, overwrite: true);
                File.Delete(backup);
            }
            catch { }
            throw;
        }
    }

    private static bool Equivalent(TrackMetadata expected, TrackMetadata actual)
    {
        return Normalize(expected.Title) == Normalize(actual.Title)
            && Normalize(expected.Artist) == Normalize(actual.Artist)
            && Normalize(expected.Album) == Normalize(actual.Album)
            && Normalize(expected.Genre) == Normalize(actual.Genre)
            && NormalizeYear(expected.Year) == NormalizeYear(actual.Year);
    }

    private static string Clean(string? value) => (value ?? "").Trim();
    private static string Normalize(string? value) => Clean(value).ToLowerInvariant();

    private static uint ParseYear(string? value)
    {
        var normalized = NormalizeYear(value);
        return uint.TryParse(normalized, out var year) ? year : 0;
    }

    private static string NormalizeYear(string? value)
    {
        var digits = new string((value ?? "").Where(char.IsDigit).Take(4).ToArray());
        return digits.Length == 4 ? digits : "";
    }
}
