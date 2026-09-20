namespace DeckReady.Services;

public sealed class AutoImportWatcher : IDisposable
{
    private readonly LogService _log;
    private readonly HashSet<string> _pending = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();
    private FileSystemWatcher? _watcher;
    private CancellationTokenSource _cts = new();

    public event Action<string>? ItemReady;
    public string Folder { get; private set; } = "";
    public bool IsRunning => _watcher?.EnableRaisingEvents == true;

    public AutoImportWatcher(LogService log)
    {
        _log = log;
    }

    public void Start(string folder)
    {
        Stop();
        Folder = Path.GetFullPath(folder);
        Directory.CreateDirectory(Folder);
        _cts = new CancellationTokenSource();

        _watcher = new FileSystemWatcher(Folder)
        {
            IncludeSubdirectories = false,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.CreationTime | NotifyFilters.Size,
            EnableRaisingEvents = true
        };
        _watcher.Created += OnCreated;
        _watcher.Renamed += OnRenamed;
        _watcher.Error += (_, e) => _log.Warning($"Auto Import watcher error: {e.GetException().Message}");

        _log.Info($"Auto Import is watching '{Folder}'.");
    }

    public void Stop()
    {
        try { _cts.Cancel(); } catch { }
        if (_watcher is not null)
        {
            _watcher.EnableRaisingEvents = false;
            _watcher.Created -= OnCreated;
            _watcher.Renamed -= OnRenamed;
            _watcher.Dispose();
            _watcher = null;
        }
        lock (_gate) _pending.Clear();
    }

    private void OnCreated(object sender, FileSystemEventArgs e) => Queue(e.FullPath);
    private void OnRenamed(object sender, RenamedEventArgs e) => Queue(e.FullPath);

    private void Queue(string path)
    {
        if (ShouldIgnore(path)) return;
        lock (_gate)
        {
            if (!_pending.Add(path)) return;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                var ready = Directory.Exists(path)
                    ? await WaitForDirectoryStableAsync(path, _cts.Token)
                    : await WaitForFileStableAsync(path, _cts.Token);

                if (ready && !_cts.IsCancellationRequested)
                    ItemReady?.Invoke(path);
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                _log.Warning($"Auto Import could not prepare '{path}': {ex.Message}");
            }
            finally
            {
                lock (_gate) _pending.Remove(path);
            }
        });
    }

    private static bool ShouldIgnore(string path)
    {
        var name = Path.GetFileName(path);
        if (string.IsNullOrWhiteSpace(name)) return true;
        if (name.StartsWith(".", StringComparison.Ordinal)) return true;

        var ext = Path.GetExtension(path);
        return ext.Equals(".tmp", StringComparison.OrdinalIgnoreCase)
            || ext.Equals(".part", StringComparison.OrdinalIgnoreCase)
            || ext.Equals(".crdownload", StringComparison.OrdinalIgnoreCase)
            || ext.Equals(".download", StringComparison.OrdinalIgnoreCase);
    }

    private static async Task<bool> WaitForFileStableAsync(string path, CancellationToken token)
    {
        long previousLength = -1;
        var stableChecks = 0;

        for (var i = 0; i < 80; i++)
        {
            token.ThrowIfCancellationRequested();
            if (!File.Exists(path)) return false;

            try
            {
                var length = new FileInfo(path).Length;
                using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read)) { }
                stableChecks = length == previousLength ? stableChecks + 1 : 0;
                previousLength = length;
                if (stableChecks >= 2) return true;
            }
            catch (IOException)
            {
                stableChecks = 0;
            }
            catch (UnauthorizedAccessException)
            {
                stableChecks = 0;
            }

            await Task.Delay(500, token);
        }

        return File.Exists(path);
    }

    private static async Task<bool> WaitForDirectoryStableAsync(string path, CancellationToken token)
    {
        var previousSignature = "";
        var stableChecks = 0;

        for (var i = 0; i < 80; i++)
        {
            token.ThrowIfCancellationRequested();
            if (!Directory.Exists(path)) return false;

            try
            {
                var files = Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)
                    .Select(f => new FileInfo(f))
                    .ToList();
                var signature = $"{files.Count}:{files.Sum(f => f.Exists ? f.Length : 0)}";
                stableChecks = signature == previousSignature ? stableChecks + 1 : 0;
                previousSignature = signature;
                if (stableChecks >= 3) return true;
            }
            catch
            {
                stableChecks = 0;
            }

            await Task.Delay(600, token);
        }

        return Directory.Exists(path);
    }

    public void Dispose()
    {
        Stop();
        _cts.Dispose();
    }
}
