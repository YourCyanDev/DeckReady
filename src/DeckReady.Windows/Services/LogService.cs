namespace DeckReady.Services;

public sealed class LogService
{
    private readonly object _gate = new();

    public event Action<string>? LineWritten;

    public void Info(string message) => Write("INFO", message);
    public void Warning(string message) => Write("WARN", message);
    public void Error(string message) => Write("ERROR", message);

    private void Write(string level, string message)
    {
        AppPaths.Ensure();
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [{level}] {message}";
        lock (_gate)
        {
            File.AppendAllText(AppPaths.LogPath, line + Environment.NewLine);
        }
        LineWritten?.Invoke(line);
    }
}
