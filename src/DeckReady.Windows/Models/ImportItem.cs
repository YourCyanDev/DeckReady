using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DeckReady.Models;

public enum SourceContainerKind
{
    None,
    Zip,
    Folder
}

public enum ImportState
{
    Queued,
    Scanning,
    Ready,
    Importing,
    Imported,
    Duplicate,
    Failed,
    WaitingForSerato
}

public sealed class ImportItem : INotifyPropertyChanged
{
    private TrackMetadata _metadata = new();
    private ImportState _state = ImportState.Queued;
    private string _statusMessage = "Waiting to scan";
    private string? _destinationPath;
    private bool _isSelected;

    public Guid Id { get; } = Guid.NewGuid();
    public required string SourcePath { get; init; }
    public string? SourceContainerPath { get; init; }
    public SourceContainerKind SourceContainerKind { get; init; }
    public string? ExtractionRoot { get; init; }
    public bool IsAutoImport { get; set; }

    public TrackMetadata Metadata
    {
        get => _metadata;
        set { _metadata = value; OnPropertyChanged(); OnPropertyChanged(nameof(DisplayTitle)); OnPropertyChanged(nameof(DisplayArtist)); OnPropertyChanged(nameof(DurationText)); }
    }

    public ImportState State
    {
        get => _state;
        set { _state = value; OnPropertyChanged(); OnPropertyChanged(nameof(StateText)); }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        set { _statusMessage = value; OnPropertyChanged(); }
    }

    public string? DestinationPath
    {
        get => _destinationPath;
        set { _destinationPath = value; OnPropertyChanged(); OnPropertyChanged(nameof(ActivePath)); OnPropertyChanged(nameof(Format)); }
    }

    public bool WasDuplicate { get; set; }

    public bool IsSelected
    {
        get => _isSelected;
        set { _isSelected = value; OnPropertyChanged(); }
    }

    public string ActivePath => DestinationPath ?? SourcePath;
    public string DisplayTitle => string.IsNullOrWhiteSpace(Metadata.Title) ? Path.GetFileNameWithoutExtension(ActivePath) : Metadata.Title;
    public string DisplayArtist => string.IsNullOrWhiteSpace(Metadata.Artist) ? "Unknown Artist" : Metadata.Artist;
    public string Format => Path.GetExtension(ActivePath).TrimStart('.').ToUpperInvariant();
    public string DurationText => Metadata.Duration <= TimeSpan.Zero ? "—" : $"{(int)Metadata.Duration.TotalMinutes}:{Metadata.Duration.Seconds:00}";
    public string StateText => State switch
    {
        ImportState.WaitingForSerato => "Waiting for Serato",
        _ => State.ToString()
    };

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
