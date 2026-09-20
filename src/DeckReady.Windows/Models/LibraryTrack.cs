using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DeckReady.Models;

public sealed class LibraryTrack : INotifyPropertyChanged
{
    private bool _isSelected;
    private TrackMetadata _metadata = new();

    public required string FilePath { get; init; }

    public TrackMetadata Metadata
    {
        get => _metadata;
        set
        {
            _metadata = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DisplayTitle));
            OnPropertyChanged(nameof(DisplayArtist));
            OnPropertyChanged(nameof(Album));
            OnPropertyChanged(nameof(DurationText));
        }
    }

    public bool IsSelected
    {
        get => _isSelected;
        set { _isSelected = value; OnPropertyChanged(); }
    }

    public string DisplayTitle => string.IsNullOrWhiteSpace(Metadata.Title) ? Path.GetFileNameWithoutExtension(FilePath) : Metadata.Title;
    public string DisplayArtist => string.IsNullOrWhiteSpace(Metadata.Artist) ? "Unknown Artist" : Metadata.Artist;
    public string Album => string.IsNullOrWhiteSpace(Metadata.Album) ? "—" : Metadata.Album;
    public string Format => Path.GetExtension(FilePath).TrimStart('.').ToUpperInvariant();
    public string DurationText => Metadata.Duration <= TimeSpan.Zero ? "—" : $"{(int)Metadata.Duration.TotalMinutes}:{Metadata.Duration.Seconds:00}";

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
