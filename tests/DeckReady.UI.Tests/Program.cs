using System.IO;
using System.Reflection;
using System.Windows.Input;
using System.Windows.Threading;
using System.Windows.Media;
using System.Windows;
using System.Windows.Controls;
using DeckReady;
using DeckReady.Models;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        using var watchdog = new System.Threading.Timer(_ =>
        {
            Console.Error.WriteLine("UI smoke test timed out.");
            try { Console.Error.WriteLine(File.ReadAllText(DeckReady.Services.AppPaths.LogPath)); } catch { }
            Environment.FailFast("UI smoke test timed out");
        }, null, TimeSpan.FromSeconds(60), System.Threading.Timeout.InfiniteTimeSpan);
        Console.WriteLine("Creating app resources");
        var app = new App();
        app.InitializeComponent();
        Console.WriteLine("Creating MainWindow");
        var window = new MainWindow();
        Console.WriteLine("MainWindow initialized");
        object? Call(string name, params object[] args) { Console.WriteLine("Calling " + name); return typeof(MainWindow).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(window,args); }
        T Control<T>(string name) => (T)window.FindName(name);
        void Check(bool value, string message) { if (!value) throw new Exception(message); }
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".wav");
        File.WriteAllBytes(path, []); // Opening the editor must not parse or modify audio.
        try
        {
            var incomplete = new LibraryTrack { FilePath = path, Metadata = new TrackMetadata() };
            var complete = new LibraryTrack { FilePath = path + "other", Metadata = new TrackMetadata { Title="Song", Artist="Artist", Album="Album", Genre="Pop", Year="2026" } };
            window.LibraryItems.Add(incomplete);
            window.LibraryItems.Add(complete);
            // Render a real grid and enter its cell-edit path. The previous test only
            // called the navigation helper, bypassing the DataGrid's edit machinery.
            var settings = (AppSettings)typeof(MainWindow).GetField("_settings", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(window)!;
            settings.AutoImportEnabled = false;
            void Pump()
            {
                var frame = new DispatcherFrame();
                window.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => frame.Continue = false));
                Dispatcher.PushFrame(frame);
            }
            Call("ShowLibraryPage");
            Call("ApplyLibraryFilters");
            window.Show();
            window.UpdateLayout();
            Pump();
            var grid = Control<DataGrid>("LibraryGrid");
            grid.SelectedItem = incomplete;
            var titleColumn = grid.Columns.OfType<DataGridTextColumn>().First();
            grid.ScrollIntoView(incomplete, titleColumn);
            grid.CurrentCell = new DataGridCellInfo(incomplete, titleColumn);
            grid.Focus();
            window.UpdateLayout();
            Pump();
            Check(grid.ItemContainerGenerator.ContainerFromItem(incomplete) is DataGridRow, "Track row must be rendered");
            if (args.Contains("--reproduce-legacy-inline-edit"))
            {
                try
                {
                    var began = grid.BeginEdit();
                    Pump();
                    throw new Exception("Legacy grid did not reproduce the expected read-only binding exception; BeginEdit=" + began);
                }
                catch (InvalidOperationException ex) when (ex.ToString().Contains("read-only", StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine("REPRODUCED previous-build crash: " + ex.Message);
                }
                return;
            }
            foreach (var column in grid.Columns.OfType<DataGridTextColumn>())
            {
                grid.CurrentCell = new DataGridCellInfo(incomplete, column);
                Check(column.IsReadOnly, "Track text column must be read-only: " + column.Header);
                Check(!grid.BeginEdit(), "Grid must not start an editor on display-only properties");
            }
            Check(grid.Columns.OfType<DataGridTemplateColumn>().Any(c => !c.IsReadOnly), "Selection checkbox column must remain interactive");
            var row = (DataGridRow)grid.ItemContainerGenerator.ContainerFromItem(incomplete);
            grid.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice, Environment.TickCount, MouseButton.Left)
            {
                RoutedEvent = System.Windows.Controls.Control.MouseDoubleClickEvent,
                Source = row
            });
            Pump();
            window.UpdateLayout();
            Check(Control<Grid>("TagEditorPage").Visibility == Visibility.Visible, "Library open must use embedded editor");
            Check(ReferenceEquals(Control<DataGrid>("TagEditorGrid").SelectedItem,incomplete), "Clicked song must be selected");
            Check(Control<TextBox>("TagTitleBox").IsEnabled, "Tag fields must be usable");
            Check(Application.Current.Windows.OfType<DeckReady.Views.MetadataEditorWindow>().Count() == 0, "Library open must not create the modal editor");
            Call("ShowTagEditorPage",true);
            Check(Control<DataGrid>("TagEditorGrid").Items.Count == 1, "Review list excludes complete tracks");
            Check(Control<TextBlock>("PageTitleText").Text == "Needs Tag Editing", "Review page title");
            incomplete.Metadata = complete.Metadata.Clone();
            Call("RefreshTagReview");
            Check(Control<DataGrid>("TagEditorGrid").Items.Count == 0, "Completed track leaves review list");
            Check(!Control<Button>("TagEditorSaveButton").IsEnabled, "Empty review cannot save a stale selection");
            Call("ShowTagEditorPage",false);
            Check(Control<DataGrid>("TagEditorGrid").Items.Count == 2, "Normal tag editor still shows all tracks");
            DeckReady.Services.CrashReporter.Record("UI regression check", new InvalidOperationException("diagnostic probe"));
            var report = File.ReadAllText(DeckReady.Services.CrashReporter.ReportPath);
            Check(report.Contains("diagnostic probe") && report.Contains("a1.10.0+windows.2"), "Crash report must include exception and build identity");
            Check(new FileInfo(path).Length == 0, "Opening/reviewing must not change audio");
            Console.WriteLine("Rendered-grid editing, double-click navigation, tag review and crash logging checks passed.");
        }
        finally { window.Close(); File.Delete(path); app.Shutdown(); }
    }
}
