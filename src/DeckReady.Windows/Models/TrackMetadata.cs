namespace DeckReady.Models;

public sealed class TrackMetadata
{
    public string Title { get; set; } = "";
    public string Artist { get; set; } = "";
    public string Album { get; set; } = "";
    public string Genre { get; set; } = "";
    public string Year { get; set; } = "";
    public TimeSpan Duration { get; set; } = TimeSpan.Zero;

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
