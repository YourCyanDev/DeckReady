using System.Collections.ObjectModel;
using System.Text.Json;
using DeckReady.Models;

namespace DeckReady.Services;

public sealed class HistoryStore
{
    private readonly JsonSerializerOptions _options = new() { WriteIndented = true };

    public ObservableCollection<HistoryRecord> Records { get; } = new();

    public HistoryStore()
    {
        AppPaths.Ensure();
        Load();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(AppPaths.HistoryPath)) return;
            var list = JsonSerializer.Deserialize<List<HistoryRecord>>(File.ReadAllText(AppPaths.HistoryPath), _options) ?? [];
            foreach (var record in list.OrderByDescending(x => x.ImportedAt))
                Records.Add(record);
        }
        catch
        {
        }
    }

    public void Add(HistoryRecord record)
    {
        Records.Insert(0, record);
        Save();
    }

    public void UpdateSeratoSynced(IEnumerable<string> paths)
    {
        var set = new HashSet<string>(paths, StringComparer.OrdinalIgnoreCase);
        foreach (var record in Records.Where(r => set.Contains(r.FilePath)))
            record.SeratoSynced = true;
        Save();
    }

    public void Save()
    {
        AppPaths.Ensure();
        File.WriteAllText(AppPaths.HistoryPath, JsonSerializer.Serialize(Records.ToList(), _options));
    }
}
