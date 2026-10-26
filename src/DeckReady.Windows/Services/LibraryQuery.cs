using DeckReady.Models;
namespace DeckReady.Services;

public enum LibrarySort { Title, Artist, Album, Genre, Year, Duration, Filename }
public sealed class LibraryQuery
{
    public string Artist { get; set; } = "";
    public string Genre { get; set; } = "";
    public string Year { get; set; } = "";
    public string Format { get; set; } = "";
    public string Search { get; set; } = "";
    public LibrarySort Sort { get; set; }
    public bool Ascending { get; set; } = true;
    public static string Tag(string value) => string.IsNullOrWhiteSpace(value) ? "Unknown" : value.Trim();
    public List<LibraryTrack> Apply(IEnumerable<LibraryTrack> tracks)
    {
        var search = Search.Trim();
        var filtered = tracks.Where(x =>
            (Artist.Length == 0 || Tag(x.Metadata.Artist) == Artist) &&
            (Genre.Length == 0 || Tag(x.Metadata.Genre) == Genre) &&
            (Year.Length == 0 || Tag(x.Metadata.Year) == Year) &&
            (Format.Length == 0 || x.Format == Format) &&
            (search.Length == 0 || new[] { x.DisplayTitle, x.DisplayArtist, x.Metadata.Album,
                x.Metadata.Genre, x.Metadata.Year, Path.GetFileName(x.FilePath) }
                .Any(value => value.Contains(search, StringComparison.OrdinalIgnoreCase))));
        return filtered.OrderBy(x => x, Comparer<LibraryTrack>.Create((a, b) =>
        {
            var result = Sort switch
            {
                LibrarySort.Artist => StringComparer.OrdinalIgnoreCase.Compare(a.DisplayArtist, b.DisplayArtist),
                LibrarySort.Album => StringComparer.OrdinalIgnoreCase.Compare(a.Metadata.Album, b.Metadata.Album),
                LibrarySort.Genre => StringComparer.OrdinalIgnoreCase.Compare(a.Metadata.Genre, b.Metadata.Genre),
                LibrarySort.Year => (int.TryParse(a.Metadata.Year, out var ay) ? ay : 0).CompareTo(int.TryParse(b.Metadata.Year, out var by) ? by : 0),
                LibrarySort.Duration => a.Metadata.Duration.CompareTo(b.Metadata.Duration),
                LibrarySort.Filename => StringComparer.OrdinalIgnoreCase.Compare(Path.GetFileName(a.FilePath), Path.GetFileName(b.FilePath)),
                _ => StringComparer.OrdinalIgnoreCase.Compare(a.DisplayTitle, b.DisplayTitle)
            };
            if (result == 0) result = StringComparer.OrdinalIgnoreCase.Compare(a.FilePath, b.FilePath);
            return Ascending ? result : -result;
        })).ToList();
    }
}

public static class LibraryCrateScan
{
    public static List<string> Discover(string folder)
    {
        if (!Directory.Exists(folder)) throw new DirectoryNotFoundException("Choose an existing music library folder in Settings first.");
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = false,
            AttributesToSkip = FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReparsePoint };
        return Directory.EnumerateFiles(folder, "*", options).Where(ImportService.IsSupportedAudio)
            .Select(Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
    }
}
