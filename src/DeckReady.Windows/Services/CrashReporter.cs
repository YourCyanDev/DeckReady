using System.Reflection;

namespace DeckReady.Services;

public static class CrashReporter
{
    public static string ReportPath => Path.Combine(AppPaths.AppDataRoot, "CrashReports", "crash-latest.txt");

    // Exception reporting must never mask the original exception or throw on shutdown.
    public static void Record(string source, Exception exception)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(ReportPath)!);
            var build = typeof(CrashReporter).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            var report = $"DeckReady {build}\nUTC: {DateTime.UtcNow:O}\nSource: {source}\nOS: {Environment.OSVersion}\nRuntime: {Environment.Version}\nProcess: {Environment.ProcessPath}\n\n{exception}\n";
            File.WriteAllText(ReportPath, report);
        }
        catch { /* Disk/permission failures cannot trigger a second crash. */ }
    }
}
