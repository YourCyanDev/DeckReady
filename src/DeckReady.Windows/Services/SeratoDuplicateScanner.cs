using System.Text;
using DeckReady.Models;

namespace DeckReady.Services;

public sealed class SeratoDuplicateScanner
{
    private readonly MetadataService _metadata;
    private readonly LogService _log;

    public SeratoDuplicateScanner(MetadataService metadata, LogService log)
    {
        _metadata = metadata;
        _log = log;
    }

    public async Task<List<SeratoDuplicateTrack>> ScanAsync(IProgress<string>? progress = null)
    {
        var references = ReadCrateReferences(progress);
        var distinctPaths = references.Keys
            .Where(File.Exists)
            .Where(ImportService.IsSupportedAudio)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        progress?.Report($"Hashing {distinctPaths.Count} Serato-referenced tracks...");

        var byHash = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var completed = 0;
        foreach (var path in distinctPaths)
        {
            try
            {
                var hash = await HashService.Sha256Async(path);
                if (!byHash.TryGetValue(hash, out var list))
                {
                    list = [];
                    byHash[hash] = list;
                }
                list.Add(path);
            }
            catch (Exception ex)
            {
                _log.Warning($"Serato duplicate scan skipped '{path}': {ex.Message}");
            }

            completed++;
            if (completed % 20 == 0 || completed == distinctPaths.Count)
                progress?.Report($"Hashed {completed} of {distinctPaths.Count} tracks...");
        }

        var results = new List<SeratoDuplicateTrack>();
        foreach (var group in byHash.Where(x => x.Value.Distinct(StringComparer.OrdinalIgnoreCase).Count() > 1))
        {
            var paths = group.Value.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
            foreach (var path in paths)
            {
                TrackMetadata metadata;
                try { metadata = _metadata.Read(path); }
                catch { metadata = new TrackMetadata { Title = Path.GetFileNameWithoutExtension(path) }; }

                references.TryGetValue(path, out var crates);
                results.Add(new SeratoDuplicateTrack
                {
                    Hash = group.Key,
                    FilePath = path,
                    Metadata = metadata,
                    DuplicateCount = paths.Count,
                    Crates = crates is null ? "" : string.Join(", ", crates.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
                });
            }
        }

        return results
            .OrderBy(x => x.DisplayArtist, StringComparer.OrdinalIgnoreCase)
            .ThenBy(x => x.DisplayTitle, StringComparer.OrdinalIgnoreCase)
            .ThenBy(x => x.FilePath, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private Dictionary<string, HashSet<string>> ReadCrateReferences(IProgress<string>? progress)
    {
        var references = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        var crateFiles = new List<(string crate, string driveRoot)>();

        foreach (var (seratoRoot, driveRoot) in GetSeratoRoots())
        {
            var subcrates = Path.Combine(seratoRoot, "Subcrates");
            if (!Directory.Exists(subcrates)) continue;

            try
            {
                foreach (var crate in Directory.EnumerateFiles(subcrates, "*.crate", SearchOption.AllDirectories))
                    crateFiles.Add((crate, driveRoot));
            }
            catch (Exception ex)
            {
                _log.Warning($"Could not scan Serato crates under '{subcrates}': {ex.Message}");
            }
        }

        progress?.Report($"Reading {crateFiles.Count} Serato crates...");

        foreach (var (cratePath, driveRoot) in crateFiles)
        {
            try
            {
                var crateName = Path.GetFileNameWithoutExtension(cratePath).Replace("%%", " / ");
                foreach (var storedPath in ReadTrackPaths(cratePath))
                {
                    var resolved = ResolveTrackPath(storedPath, driveRoot);
                    if (resolved is null) continue;

                    if (!references.TryGetValue(resolved, out var crates))
                    {
                        crates = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        references[resolved] = crates;
                    }
                    crates.Add(crateName);
                }
            }
            catch (Exception ex)
            {
                _log.Warning($"Could not read Serato crate '{cratePath}': {ex.Message}");
            }
        }

        return references;
    }

    private static IEnumerable<(string seratoRoot, string driveRoot)> GetSeratoRoots()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var systemDrive = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)) ?? "";
        var musicRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyMusic), "_Serato_");
        if (Directory.Exists(musicRoot) && seen.Add(musicRoot))
            yield return (musicRoot, systemDrive);

        foreach (var drive in DriveInfo.GetDrives())
        {
            string? root = null;
            string? seratoRoot = null;

            try
            {
                if (!drive.IsReady) continue;
                root = drive.RootDirectory.FullName;
                seratoRoot = Path.Combine(root, "_Serato_");
            }
            catch
            {
                continue;
            }

            if (root is not null && seratoRoot is not null && Directory.Exists(seratoRoot) && seen.Add(seratoRoot))
                yield return (seratoRoot, root);
        }
    }

    private static string? ResolveTrackPath(string storedPath, string driveRoot)
    {
        if (string.IsNullOrWhiteSpace(storedPath)) return null;

        var normalized = storedPath.Replace('/', Path.DirectorySeparatorChar).Replace('\\', Path.DirectorySeparatorChar);
        try
        {
            if (Path.IsPathRooted(normalized))
                return Path.GetFullPath(normalized);

            return Path.GetFullPath(Path.Combine(driveRoot, normalized.TrimStart(Path.DirectorySeparatorChar)));
        }
        catch
        {
            return null;
        }
    }

    private static IEnumerable<string> ReadTrackPaths(string cratePath)
    {
        var data = File.ReadAllBytes(cratePath);
        foreach (var record in ReadRecords(data))
        {
            if (record.Tag != "otrk") continue;
            foreach (var nested in ReadRecords(record.Payload))
            {
                if (nested.Tag != "ptrk") continue;
                var path = Encoding.BigEndianUnicode.GetString(nested.Payload).TrimEnd('\0');
                if (!string.IsNullOrWhiteSpace(path))
                    yield return path;
            }
        }
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

    private static uint ReadUInt32BigEndian(byte[] data, int offset) =>
        ((uint)data[offset] << 24) |
        ((uint)data[offset + 1] << 16) |
        ((uint)data[offset + 2] << 8) |
        data[offset + 3];

    private sealed record TlvRecord(string Tag, byte[] Payload);
}
