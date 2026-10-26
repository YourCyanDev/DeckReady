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
var options = new JsonSerializerOptions { Converters = { new JsonStringEnumConverter() } };
foreach (var mode in Enum.GetValues<OrganizationMode>())
{
    var settings = new AppSettings { OrganizationMode = mode };
    Check(JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(settings, options), options)!.OrganizationMode == mode, "Settings mode round trip");
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
Console.WriteLine("All organization, settings compatibility, and import regression checks passed.");
