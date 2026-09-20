using System.Text.Json;

namespace DeckReady.Services;

public sealed class AutoImportStateStore
{
    private readonly string _path;
    private readonly Dictionary<string, string> _processed = new(StringComparer.OrdinalIgnoreCase);

    public AutoImportStateStore()
    {
        AppPaths.Ensure();
        _path = Path.Combine(Path.GetDirectoryName(AppPaths.SettingsPath)!, "auto-import-state.json");
        try
        {
            if (File.Exists(_path))
            {
                var loaded = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_path));
                if (loaded is not null)
                {
                    foreach (var pair in loaded)
                        _processed[pair.Key] = pair.Value;
                }
            }
        }
        catch { }
    }

    public bool IsAlreadyProcessed(string path)
    {
        var fingerprint = TryFingerprint(path);
        if (fingerprint is null) return false;
        var full = Path.GetFullPath(path);
        return _processed.TryGetValue(full, out var previous) && previous == fingerprint;
    }

    public void MarkProcessed(string path)
    {
        var fingerprint = TryFingerprint(path);
        if (fingerprint is null) return;
        _processed[Path.GetFullPath(path)] = fingerprint;
        Save();
    }

    private void Save()
    {
        try
        {
            File.WriteAllText(_path, JsonSerializer.Serialize(_processed, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    private static string? TryFingerprint(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                var info = new FileInfo(path);
                return $"F|{info.Length}|{info.LastWriteTimeUtc.Ticks}";
            }

            if (Directory.Exists(path))
            {
                var infos = Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)
                    .Select(f => new FileInfo(f))
                    .ToList();
                var total = infos.Sum(f => f.Exists ? f.Length : 0L);
                var latest = infos.Count == 0 ? Directory.GetLastWriteTimeUtc(path).Ticks : infos.Max(f => f.LastWriteTimeUtc.Ticks);
                return $"D|{infos.Count}|{total}|{latest}";
            }
        }
        catch { }
        return null;
    }
}
