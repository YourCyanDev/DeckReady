namespace DeckReady.Models;

public sealed class TrackMetadata
{
    public string Title { get; set; } = "";
    public string Artist { get; set; } = "";
    public string Album { get; set; } = "";
    public string Genre { get; set; } = "";
    public string Year { get; set; } = "";
    public TimeSpan Duration { get; set; } = TimeSpan.Zero;

    [System.Text.Json.Serialization.JsonIgnore]
    public IReadOnlyList<string> MissingFields => new[]
    {
        ("Title", Title), ("Artist", Artist), ("Album", Album), ("Genre", Genre), ("Year", Year)
    }.Where(x => IsMissing(x.Item2, x.Item1)).Select(x => x.Item1).ToArray();

    [System.Text.Json.Serialization.JsonIgnore]
    public bool NeedsTagEditing => MissingFields.Count > 0;
    private static bool IsMissing(string? value, string field)
    {
        var tag = (value ?? "").Trim();
        return tag.Length == 0 || tag.Equals("Unknown", StringComparison.OrdinalIgnoreCase)
            || tag.Equals("Unknown " + field, StringComparison.OrdinalIgnoreCase)
            || (field == "Year" && tag.All(c => c == '0'));
    }

    public TrackMetadata Clone() => new()
    {
        Title = Title,
        Artist = Artist,
        Album = Album,
        Genre = Genre,
        Year = Year,
        Duration = Duration
    };
}
