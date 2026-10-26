using System.Text.Json;
using System.Text.Json.Serialization;
using DeckReady.Models;
using DeckReady.Services;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}
var tracks = new (string Path, TrackMetadata Metadata)[]
{
    ("one.wav", new() { Year = "2026", Artist = "Yo DJ Hill" }),
    ("two.wav", new() { Year = "2026", Artist = "Yo DJ Hill" }),
    ("three.wav", new() { Year = "2026", Artist = "Other Artist" }),
    ("four.wav", new() { Year = "2025", Artist = "Yo DJ Hill" }),
    ("one.wav", new() { Year = "2026", Artist = "Yo DJ Hill" })
};
var plan = CrateOrganization.Plan(tracks, OrganizationMode.YearArtist, "Ignored");
Check(plan.Count == 5, "Two years and three artist subcrates expected");
Check(plan["2026"].Count == 3, "Year must contain its tracks without duplicates");
Check(plan["2026%%Yo DJ Hill"].SequenceEqual(new[] { "one.wav", "two.wav" }), "Artist tracks grouped incorrectly");
Check(plan["2025%%Yo DJ Hill"].Single() == "four.wav", "Same artist in another year must be separate");
Check(plan.Keys.All(x => !x.Contains("Songs") && x.Split("%%").Length <= 2), "Songs must not be a crate");
var unknown = CrateOrganization.Plan(new[] { ("missing.wav", new TrackMetadata()) }, OrganizationMode.YearArtist, "Ignored");
Check(unknown.Count == 1 && unknown["need tag editing"].Single() == "missing.wav", "Missing metadata must go to tag editing");
var incomplete = CrateOrganization.Plan(new[]
{
    ("no-year.wav", new TrackMetadata { Artist = "Yo DJ Hill" }),
    ("no-artist.wav", new TrackMetadata { Year = "2026", Artist = "  " }),
    ("both.wav", new TrackMetadata())
}, OrganizationMode.YearArtist, "Ignored");
Check(incomplete.Count == 1 && incomplete["need tag editing"].Count == 3, "Either missing tag must route only to tag editing");
var unsafeNames = CrateOrganization.Plan(new[] { ("x.wav", new TrackMetadata { Year = "2026", Artist = "../Bad%%Name" }) }, OrganizationMode.YearArtist, "Ignored");
Check(unsafeNames.Keys.All(x => x.Split("%%").Length <= 2 && !x.Contains('/')), "Metadata must not escape or inject levels");
foreach (var mode in new[] { OrganizationMode.NoSubfolders, OrganizationMode.Artist, OrganizationMode.Genre, OrganizationMode.Year })
{
    var flat = CrateOrganization.Plan(tracks, mode, "My Crate");
    Check(flat.Count == 1 && flat["My Crate"].Count == 4, "Existing modes must retain one crate");
}
var genreTracks = new[]
{
    ("a.wav", new TrackMetadata { Genre = "Hip-Hop", Artist = "Yo DJ Hill" }),
    ("b.wav", new TrackMetadata { Genre = "R&B", Artist = "Yo DJ Hill" }),
    ("c.wav", new TrackMetadata { Genre = "Hip-Hop", Artist = "Guest" }),
    ("d.wav", new TrackMetadata { Artist = "Yo DJ Hill" }),
    ("e.wav", new TrackMetadata { Genre = "Hip-Hop" })
};
var genres = CrateOrganization.Plan(genreTracks, OrganizationMode.GenreArtist, "Ignored");
Check(genres["Hip-Hop%%Yo DJ Hill"].Single() == "a.wav", "Genre artist nesting");
Check(genres["R&B%%Yo DJ Hill"].Single() == "b.wav", "Same artist under different genre");
Check(genres["need tag editing"].Count == 2, "Missing genre or artist needs tag editing");
Check(genres.Keys.All(x => x.Split("%%").Length <= 2 && !x.Contains("Songs")), "No third crate level");
var combined = CrateOrganization.Plan(new[]
{
    ("ready.wav", new TrackMetadata { Year = "2026", Genre = "Hip-Hop", Artist = "Yo DJ Hill" }),
    ("partial.wav", new TrackMetadata { Genre = "Hip-Hop", Artist = "Yo DJ Hill" }),
    ("missing.wav", new TrackMetadata())
}, new[] { OrganizationMode.YearArtist, OrganizationMode.GenreArtist, OrganizationMode.YearArtist }, "Ignored");
Check(combined["2026%%Yo DJ Hill"].Single() == "ready.wav", "Combined year structure");
Check(combined["Hip-Hop%%Yo DJ Hill"].Count == 2, "Combined genre structure");
Check(combined["need tag editing"].Count == 2, "Review crate must deduplicate incomplete tags across modes");
Check(combined["Hip-Hop%%Yo DJ Hill"].Contains("ready.wav"), "Same audio referenced by both structures");
var options = new JsonSerializerOptions { Converters = { new JsonStringEnumConverter() } };
foreach (var mode in Enum.GetValues<OrganizationMode>())
{
    var settings = new AppSettings { OrganizationMode = mode, AdditionalOrganizationModes = new() { OrganizationMode.GenreArtist }, ShowSeratoRestartPrompt = false };
    Check(JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(settings, options), options)!.OrganizationMode == mode, "Settings mode round trip");
    Check(JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(settings, options), options)!.AdditionalOrganizationModes.Single() == OrganizationMode.GenreArtist, "Extra options persist");
    Check(!JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(settings, options), options)!.ShowSeratoRestartPrompt, "Existing restart reminder preference persists");
}
Check((int)OrganizationMode.Year == 3, "Existing numeric settings must remain compatible");

var temp = Path.Combine(Path.GetTempPath(), "DeckReady-test-" + Guid.NewGuid());
Directory.CreateDirectory(temp);
try
{
    var source = Path.Combine(temp, "song.wav");
    // Imports with file-tag writing off accept the source bytes as-is.
    await File.WriteAllBytesAsync(source, new byte[] { 1, 2, 3, 4 });
    var settings = new AppSettings { LibraryFolder = Path.Combine(temp, "Library"),
        OrganizationMode = OrganizationMode.YearArtist, WriteMetadataToFiles = false };
    var item = new ImportItem { SourcePath = source, Metadata = new() { Year = "2026", Artist = "Yo DJ Hill" } };
    var importer = new ImportService(new MetadataService(), new LogService());
    var hashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    var imported = await importer.ImportAsync(item, settings, hashes);
    Check(imported.destinationPath == Path.Combine(settings.LibraryFolder, "2026", "Yo DJ Hill", "song.wav"), "Nested destination");
    Check(File.Exists(source) && File.Exists(imported.destinationPath), "Copy must preserve source");
    Check(!Directory.Exists(Path.Combine(settings.LibraryFolder, "2026", "Yo DJ Hill", "Songs")), "No Songs folder");
    var duplicate = await importer.ImportAsync(item, settings, hashes);
    Check(duplicate.duplicate && duplicate.destinationPath == imported.destinationPath, "Duplicate detection regression");
    Check(ImportService.ResolveDestinationFolder(settings, new()) == Path.Combine(settings.LibraryFolder, "Unknown Year", "Unknown Artist"), "Folder fallbacks");
    Check(ImportService.SanitizeFolderName("..") == "Unknown", "Empty sanitized name fallback");
    settings.OrganizationMode = OrganizationMode.GenreArtist;
    item.Metadata.Genre = "Hip-Hop";
    Check(ImportService.ResolveDestinationFolder(settings, item.Metadata) == Path.Combine(settings.LibraryFolder, "Hip-Hop", "Yo DJ Hill"), "Genre folder layout");
    Check(ImportService.ResolveDestinationFolder(settings, new()) == Path.Combine(settings.LibraryFolder, "Unknown Genre", "Unknown Artist"), "Genre folder fallbacks");
    settings.OrganizationMode = OrganizationMode.Artist;
    Check(ImportService.ResolveDestinationFolder(settings, item.Metadata) == Path.Combine(settings.LibraryFolder, "Yo DJ Hill"), "Old artist layout");
    settings.OrganizationMode = OrganizationMode.NoSubfolders;
    Check(ImportService.ResolveDestinationFolder(settings, item.Metadata) == settings.LibraryFolder, "Old flat layout");
}
finally { Directory.Delete(temp, true); }
var libraryTemp = Path.Combine(Path.GetTempPath(), "DeckReady-library-test-" + Guid.NewGuid());
Directory.CreateDirectory(Path.Combine(libraryTemp, "Nested"));
try
{
    var unmanaged = Path.Combine(libraryTemp, "never-imported.MP3");
    var nested = Path.Combine(libraryTemp, "Nested", "song.wav");
    var bytes = new byte[] { 7, 8, 9, 10 };
    await File.WriteAllBytesAsync(unmanaged, bytes);
    await File.WriteAllBytesAsync(nested, bytes);
    await File.WriteAllTextAsync(Path.Combine(libraryTemp, "notes.txt"), "Leave me alone");
    var discovered = LibraryCrateScan.Discover(libraryTemp);
    Check(discovered.Count == 2 && discovered.Contains(unmanaged), "Whole library scan includes unmanaged and nested audio, not text files");
    var rows = new[]
    {
        new LibraryTrack { FilePath = unmanaged, Metadata = new() { Title = "Zulu", Artist = "Artist B", Genre = "Pop", Year = "2026", Duration = TimeSpan.FromSeconds(100) } },
        new LibraryTrack { FilePath = nested, Metadata = new() { Title = "Alpha", Artist = "Artist A", Genre = "Hip-Hop", Year = "2025", Duration = TimeSpan.FromSeconds(20) } },
        new LibraryTrack { FilePath = Path.Combine(libraryTemp, "blank.wav"), Metadata = new() }
    };
    var query = new LibraryQuery { Artist = "Artist A", Genre = "Hip-Hop", Year = "2025", Format = "WAV" };
    Check(query.Apply(rows).Single().FilePath == nested, "Library filters must combine with AND");
    query.Genre = "Pop";
    Check(query.Apply(rows).Count == 0, "Filters exclude nonmatching genre");
    Check(new LibraryQuery { Artist = "Unknown" }.Apply(rows).Count == 1, "Unknown artist filter");
    Check(new LibraryQuery { Search = "2026" }.Apply(rows).Count == 1, "Search includes year");
    Check(new LibraryQuery { Sort = LibrarySort.Duration, Ascending = false }.Apply(rows).First().FilePath == unmanaged, "Numeric duration sort");
    Check(new LibraryQuery { Sort = LibrarySort.Year, Ascending = false }.Apply(rows).First().FilePath == unmanaged, "Numeric year sort");
    foreach (var sort in Enum.GetValues<LibrarySort>())
    {
        var up = new LibraryQuery { Sort = sort }.Apply(rows).Select(x => x.FilePath).ToList();
        var down = new LibraryQuery { Sort = sort, Ascending = false }.Apply(rows).Select(x => x.FilePath).Reverse().ToList();
        Check(up.SequenceEqual(down), "All sort categories must reverse consistently with deterministic ties");
    }
    _ = CrateOrganization.Plan(discovered.Select(x => (x, new TrackMetadata())), new[] { OrganizationMode.YearArtist, OrganizationMode.GenreArtist }, "Ignored");
    Check((await File.ReadAllBytesAsync(unmanaged)).SequenceEqual(bytes), "Unmanaged audio must remain untouched");
    Check((await File.ReadAllBytesAsync(nested)).SequenceEqual(bytes), "Nested audio must remain untouched");
}
finally { Directory.Delete(libraryTemp, true); }
Console.WriteLine("All organization, settings compatibility, and import regression checks passed.");
