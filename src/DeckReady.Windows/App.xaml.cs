using System.Windows;
using DeckReady.Services;

namespace DeckReady;

public partial class App : Application
{
    public App()
    {
        DispatcherUnhandledException += (_, e) => CrashReporter.Record("UI dispatcher", e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception exception) CrashReporter.Record("Unhandled exception", exception);
        };
        TaskScheduler.UnobservedTaskException += (_, e) => CrashReporter.Record("Unobserved task", e.Exception);
    }
}
