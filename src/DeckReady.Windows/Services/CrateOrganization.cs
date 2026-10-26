using DeckReady.Models;

namespace DeckReady.Services;

public static class CrateOrganization
{
    public static IReadOnlyDictionary<string, List<string>> Plan(
        IEnumerable<(string Path, TrackMetadata Metadata)> tracks,
        OrganizationMode mode, string flatCrateName)
        => Plan(tracks, new[] { mode }, flatCrateName);

    public static IReadOnlyDictionary<string, List<string>> Plan(
        IEnumerable<(string Path, TrackMetadata Metadata)> tracks,
        IEnumerable<OrganizationMode> modes, string flatCrateName)
    {
        var selectedModes = modes.Distinct().ToArray();
        var crates = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var (path, metadata) in tracks)
        foreach (var mode in selectedModes)
        {
            if (mode is OrganizationMode.YearArtist or OrganizationMode.GenreArtist)
            {
                var category = mode == OrganizationMode.YearArtist ? metadata.Year : metadata.Genre;
                if (string.IsNullOrWhiteSpace(category) || string.IsNullOrWhiteSpace(metadata.Artist))
                {
                    Add("need tag editing", path);
                    continue;
                }
                var parent = Component(category, mode == OrganizationMode.YearArtist ? "Unknown Year" : "Unknown Genre");
                var artist = Component(metadata.Artist, "Unknown Artist");
                Add(parent, path);
                Add(parent + "%%" + artist, path);
            }
            else
                Add(Component(flatCrateName, "DeckReady Imports"), path);
        }
        return crates;

        void Add(string name, string path)
        {
            if (!crates.TryGetValue(name, out var paths))
                crates[name] = paths = new List<string>();
            if (!paths.Contains(path, StringComparer.OrdinalIgnoreCase)) paths.Add(path);
        }
    }

    private static string Component(string value, string fallback)
    {
        // %% is Serato's hierarchy separator; metadata must not create extra levels.
        var result = string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
        foreach (var c in Path.GetInvalidFileNameChars()) result = result.Replace(c, '-');
        result = result.Replace('%', '-').Trim().TrimEnd('.');
        return string.IsNullOrWhiteSpace(result) ? fallback : result;
    }
}
