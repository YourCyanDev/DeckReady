using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DeckReady.Models;

public sealed class HistoryRecord : INotifyPropertyChanged
{
    private bool _isSelected;
    private TrackMetadata _metadata = new();

    public Guid Id { get; set; } = Guid.NewGuid();
    public TrackMetadata Metadata
    {
        get => _metadata;
        set
        {
            _metadata = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DisplayTitle));
            OnPropertyChanged(nameof(DisplayArtist));
        }
    }
    public string FilePath { get; set; } = "";
    public DateTime ImportedAt { get; set; } = DateTime.Now;
    public bool WasDuplicate { get; set; }
    public bool SeratoSynced { get; set; }

    public bool IsSelected
    {
        get => _isSelected;
        set { _isSelected = value; OnPropertyChanged(); }
    }

    public string DisplayTitle => string.IsNullOrWhiteSpace(Metadata.Title) ? Path.GetFileNameWithoutExtension(FilePath) : Metadata.Title;
    public string DisplayArtist => string.IsNullOrWhiteSpace(Metadata.Artist) ? "Unknown Artist" : Metadata.Artist;
    public string Format => Path.GetExtension(FilePath).TrimStart('.').ToUpperInvariant();
    public string ImportedAtText => ImportedAt.ToString("g");

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
