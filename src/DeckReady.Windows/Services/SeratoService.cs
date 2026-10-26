using System.Diagnostics;
using System.Text;
using DeckReady.Models;

namespace DeckReady.Services;

public sealed class SeratoService
{
    private readonly LogService _log;
    private string? _lastKnownProExecutable;
    private string? _lastKnownLiteExecutable;

    public bool IsInstalled { get; private set; }
    public bool IsRunning { get; private set; }
    public bool IsProInstalled { get; private set; }
    public bool IsLiteInstalled { get; private set; }
    public bool IsProRunning { get; private set; }
    public bool IsLiteRunning { get; private set; }
    public string? ProExecutablePath { get; private set; }
    public string? LiteExecutablePath { get; private set; }
    public string StatusText { get; private set; } = "Checking for Serato...";

    public SeratoService(LogService log)
    {
        _log = log;
        RefreshStatus();
    }

    public void RefreshStatus()
    {
        var processes = RunningSeratoProcesses();
        IsRunning = processes.Count > 0;
        IsProRunning = false;
        IsLiteRunning = false;

        foreach (var process in processes)
        {
            try
            {
                var runningPath = process.MainModule?.FileName;
                var descriptor = $"{process.ProcessName} {process.MainWindowTitle} {runningPath}";

                if (descriptor.Contains("Lite", StringComparison.OrdinalIgnoreCase))
                {
                    IsLiteRunning = true;
                    if (!string.IsNullOrWhiteSpace(runningPath) && File.Exists(runningPath))
                        _lastKnownLiteExecutable = runningPath;
                }
                else if (descriptor.Contains("Pro", StringComparison.OrdinalIgnoreCase))
                {
                    IsProRunning = true;
                    if (!string.IsNullOrWhiteSpace(runningPath) && File.Exists(runningPath))
                        _lastKnownProExecutable = runningPath;
                }
            }
            catch { }
        }

        var (pro, lite) = FindExecutables();
        ProExecutablePath = pro ?? _lastKnownProExecutable;
        LiteExecutablePath = lite ?? _lastKnownLiteExecutable;

        if (ProExecutablePath is not null) _lastKnownProExecutable = ProExecutablePath;
        if (LiteExecutablePath is not null) _lastKnownLiteExecutable = LiteExecutablePath;

        IsProInstalled = ProExecutablePath is not null || IsProRunning;
        IsLiteInstalled = LiteExecutablePath is not null || IsLiteRunning;
        IsInstalled = IsProInstalled || IsLiteInstalled || IsRunning;

        if (IsProRunning && IsLiteRunning)
            StatusText = "Serato DJ Pro + Lite are running";
        else if (IsProRunning)
            StatusText = "Serato DJ Pro is running";
        else if (IsLiteRunning)
            StatusText = "Serato DJ Lite is running";
        else if (IsRunning)
            StatusText = "Serato DJ is running";
        else if (IsProInstalled && IsLiteInstalled)
            StatusText = "Serato DJ Pro + Lite installed";
        else if (IsProInstalled)
            StatusText = "Serato DJ Pro installed";
        else if (IsLiteInstalled)
            StatusText = "Serato DJ Lite installed";
        else
            StatusText = "Serato DJ Pro/Lite not found";
    }

    public SeratoAppPreference EffectivePreference(SeratoAppPreference preferred)
    {
        RefreshStatus();
        if (IsProInstalled && IsLiteInstalled) return preferred;
        if (IsLiteInstalled) return SeratoAppPreference.Lite;
        return SeratoAppPreference.Pro;
    }

    public bool Launch(SeratoAppPreference preferred)
    {
        RefreshStatus();
        if (IsRunning) return true;

        var effective = EffectivePreference(preferred);
        var executable = effective == SeratoAppPreference.Lite ? LiteExecutablePath : ProExecutablePath;
        executable ??= ProExecutablePath ?? LiteExecutablePath;
        if (executable is null) return false;

        try
        {
            Process.Start(new ProcessStartInfo(executable) { UseShellExecute = true });
            return true;
        }
        catch (Exception ex)
        {
            _log.Error($"Could not launch Serato: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> QuitAndWaitAsync(TimeSpan? timeout = null)
    {
        var processes = RunningSeratoProcesses();
        if (processes.Count == 0) return true;

        foreach (var process in processes)
        {
            try { process.CloseMainWindow(); } catch { }
        }

        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(15));
        while (DateTime.UtcNow < deadline)
        {
            await Task.Delay(250);
            RefreshStatus();
            if (!IsRunning) return true;
        }

        return false;
    }

    public SeratoSyncResult SyncOrganizedCrates(
        IEnumerable<(string Path, TrackMetadata Metadata)> tracks, OrganizationMode mode, string crateName)
    {
        var plan = CrateOrganization.Plan(tracks, mode, crateName);
        var added = 0;
        var total = 0;
        foreach (var crate in plan)
        {
            var result = SyncCrate(crate.Value, crate.Key);
            added += result.AddedTracks;
            total += result.TotalTracks;
        }
        return new SeratoSyncResult(added, total);
    }

    public SeratoSyncResult SyncCrate(IEnumerable<string> trackPaths, string crateName)
    {
        RefreshStatus();
        if (IsRunning)
            throw new InvalidOperationException("Serato is open. Quit Serato before DeckReady updates its crate.");

        var paths = trackPaths.Select(Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (paths.Count == 0)
            return new SeratoSyncResult(0, 0);

        var groups = paths.GroupBy(path => Path.GetPathRoot(path) ?? "");
        var added = 0;
        var total = 0;

        foreach (var group in groups)
        {
            var driveRoot = group.Key;
            if (string.IsNullOrWhiteSpace(driveRoot))
                continue;

            var seratoRoot = GetSeratoRoot(driveRoot);
            var subcrates = Path.Combine(seratoRoot, "Subcrates");
            Directory.CreateDirectory(subcrates);

            var safeCrate = SanitizeCrateName(crateName);
            var cratePath = Path.Combine(subcrates, safeCrate + ".crate");

            var existing = File.Exists(cratePath) ? ReadExistingPaths(cratePath) : new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var before = existing.Count;

            foreach (var trackPath in group)
            {
                var relative = Path.GetRelativePath(driveRoot, trackPath).Replace('\\', '/');
                existing.Add(relative);
            }

            added += existing.Count - before;
            total += existing.Count;

            BackupCrate(cratePath, safeCrate);
            File.WriteAllBytes(cratePath, BuildCrate(existing.OrderBy(x => x, StringComparer.OrdinalIgnoreCase)));
            _log.Info($"Updated Serato crate '{safeCrate}' at {cratePath}.");
        }

        return new SeratoSyncResult(added, total);
    }

    private string GetSeratoRoot(string driveRoot)
    {
        var systemRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)) ?? "";
        if (driveRoot.Equals(systemRoot, StringComparison.OrdinalIgnoreCase))
        {
            var music = Environment.GetFolderPath(Environment.SpecialFolder.MyMusic);
            return Path.Combine(music, "_Serato_");
        }

        return Path.Combine(driveRoot, "_Serato_");
    }

    private List<Process> RunningSeratoProcesses()
    {
        var result = new List<Process>();
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                var name = process.ProcessName;
                var title = process.MainWindowTitle ?? "";
                if (name.Contains("Serato", StringComparison.OrdinalIgnoreCase) ||
                    title.Contains("Serato DJ", StringComparison.OrdinalIgnoreCase))
                {
                    result.Add(process);
                }
            }
            catch { }
        }
        return result;
    }

    private (string? Pro, string? Lite) FindExecutables()
    {
        string? pro = null;
        string? lite = null;

        var roots = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)
        }
        .Where(x => !string.IsNullOrWhiteSpace(x))
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToList();

        foreach (var root in roots)
        {
            var proCandidate = Path.Combine(root, "Serato", "Serato DJ Pro", "Serato DJ Pro.exe");
            var liteCandidate = Path.Combine(root, "Serato", "Serato DJ Lite", "Serato DJ Lite.exe");
            if (pro is null && File.Exists(proCandidate)) pro = proCandidate;
            if (lite is null && File.Exists(liteCandidate)) lite = liteCandidate;
        }

        if (pro is not null && lite is not null)
            return (pro, lite);

        // Fallback for non-standard installs under a normal Serato Program Files folder.
        foreach (var root in roots)
        {
            var seratoRoot = Path.Combine(root, "Serato");
            if (!Directory.Exists(seratoRoot)) continue;

            try
            {
                foreach (var exe in Directory.EnumerateFiles(seratoRoot, "*.exe", SearchOption.AllDirectories))
                {
                    var name = Path.GetFileNameWithoutExtension(exe);
                    if (pro is null && name.Contains("Serato DJ Pro", StringComparison.OrdinalIgnoreCase))
                        pro = exe;
                    else if (lite is null && name.Contains("Serato DJ Lite", StringComparison.OrdinalIgnoreCase))
                        lite = exe;

                    if (pro is not null && lite is not null)
                        return (pro, lite);
                }
            }
            catch { }
        }

        return (pro, lite);
    }

    private static string SanitizeCrateName(string value)
    {
        var baseName = string.IsNullOrWhiteSpace(value) ? "DeckReady Imports" : value.Trim();
        foreach (var c in Path.GetInvalidFileNameChars())
            baseName = baseName.Replace(c, '-');
        return string.IsNullOrWhiteSpace(baseName) ? "DeckReady Imports" : baseName;
    }

    private static void BackupCrate(string cratePath, string crateName)
    {
        if (!File.Exists(cratePath)) return;
        AppPaths.Ensure();
        var backup = Path.Combine(AppPaths.SeratoBackupRoot, $"{crateName}-{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.crate");
        File.Copy(cratePath, backup, overwrite: false);
    }

    private static byte[] BuildCrate(IEnumerable<string> trackPaths)
    {
        using var output = new MemoryStream();
        WriteTlvText(output, "vrsn", "1.0/Serato ScratchLive Crate");

        var columns = new (string name, string width)[]
        {
            ("song","250"), ("artist","250"), ("bpm","30"), ("key","30"),
            ("album","250"), ("length","250"), ("comment","250")
        };

        foreach (var (name, width) in columns)
        {
            using var nested = new MemoryStream();
            WriteTlvText(nested, "tvcn", name);
            WriteTlvText(nested, "tvcw", width);
            WriteTlv(output, "ovct", nested.ToArray());
        }

        foreach (var path in trackPaths)
        {
            using var nested = new MemoryStream();
            WriteTlvText(nested, "ptrk", path);
            WriteTlv(output, "otrk", nested.ToArray());
        }

        return output.ToArray();
    }

    private static HashSet<string> ReadExistingPaths(string cratePath)
    {
        var data = File.ReadAllBytes(cratePath);
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var record in ReadRecords(data))
        {
            if (record.Tag != "otrk") continue;
            foreach (var nested in ReadRecords(record.Payload))
            {
                if (nested.Tag == "ptrk")
                {
                    var path = Encoding.BigEndianUnicode.GetString(nested.Payload).TrimEnd('\0');
                    if (!string.IsNullOrWhiteSpace(path))
                        result.Add(path);
                }
            }
        }

        return result;
    }

    private static IEnumerable<TlvRecord> ReadRecords(byte[] data)
    {
        var offset = 0;
        while (offset + 8 <= data.Length)
        {
            var tag = Encoding.ASCII.GetString(data, offset, 4);
            var length = ReadUInt32BigEndian(data, offset + 4);
            offset += 8;

            if (length > int.MaxValue || offset + (int)length > data.Length)
                yield break;

            var payload = new byte[(int)length];
            Buffer.BlockCopy(data, offset, payload, 0, (int)length);
            offset += (int)length;
            yield return new TlvRecord(tag, payload);
        }
    }

    private static void WriteTlvText(Stream stream, string tag, string text) =>
        WriteTlv(stream, tag, Encoding.BigEndianUnicode.GetBytes(text));

    private static void WriteTlv(Stream stream, string tag, byte[] payload)
    {
        var tagBytes = Encoding.ASCII.GetBytes(tag.PadRight(4).Substring(0, 4));
        stream.Write(tagBytes, 0, 4);

        var length = (uint)payload.Length;
        stream.WriteByte((byte)(length >> 24));
        stream.WriteByte((byte)(length >> 16));
        stream.WriteByte((byte)(length >> 8));
        stream.WriteByte((byte)length);

        stream.Write(payload, 0, payload.Length);
    }

    private static uint ReadUInt32BigEndian(byte[] data, int offset) =>
        ((uint)data[offset] << 24) |
        ((uint)data[offset + 1] << 16) |
        ((uint)data[offset + 2] << 8) |
        data[offset + 3];

    private sealed record TlvRecord(string Tag, byte[] Payload);
}

public sealed record SeratoSyncResult(int AddedTracks, int TotalTracks);
