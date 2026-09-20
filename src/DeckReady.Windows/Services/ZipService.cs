using System.IO.Compression;

namespace DeckReady.Services;

public sealed class ZipService
{
    public string ExtractSafely(string zipPath)
    {
        var destination = Path.Combine(Path.GetTempPath(), "DeckReady", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(destination);

        try
        {
            var destinationRoot = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
            using var archive = ZipFile.OpenRead(zipPath);

            foreach (var entry in archive.Entries)
            {
                if (string.IsNullOrEmpty(entry.Name) && entry.FullName.EndsWith('/'))
                    continue;

                var target = Path.GetFullPath(Path.Combine(destination, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                if (!target.StartsWith(destinationRoot, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException($"Unsafe ZIP entry blocked: {entry.FullName}");

                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                if (!string.IsNullOrEmpty(entry.Name))
                    entry.ExtractToFile(target, overwrite: true);
            }

            return destination;
        }
        catch
        {
            try { Directory.Delete(destination, recursive: true); } catch { }
            throw;
        }
    }
}
