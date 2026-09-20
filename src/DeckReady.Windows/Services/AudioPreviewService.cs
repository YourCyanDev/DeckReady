using System.Windows.Media;

namespace DeckReady.Services;

public sealed class AudioPreviewService : IDisposable
{
    private readonly MediaPlayer _player = new();
    private string? _currentPath;
    private bool _isPlaying;

    public string? CurrentPath => _currentPath;
    public bool IsPlaying => _isPlaying;

    public event EventHandler? StateChanged;

    public AudioPreviewService()
    {
        _player.MediaEnded += (_, _) =>
        {
            _isPlaying = false;
            StateChanged?.Invoke(this, EventArgs.Empty);
        };
        _player.MediaFailed += (_, _) =>
        {
            _isPlaying = false;
            StateChanged?.Invoke(this, EventArgs.Empty);
        };
    }

    public void Play(string path)
    {
        var fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath))
            throw new FileNotFoundException("The audio file could not be found.", fullPath);

        if (_currentPath is null || !_currentPath.Equals(fullPath, StringComparison.OrdinalIgnoreCase))
        {
            _player.Close();
            _player.Open(new Uri(fullPath));
            _currentPath = fullPath;
        }

        _player.Play();
        _isPlaying = true;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Pause()
    {
        _player.Pause();
        _isPlaying = false;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Stop()
    {
        _player.Stop();
        _isPlaying = false;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        try { _player.Close(); } catch { }
    }
}
