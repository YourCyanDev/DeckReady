using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using DeckReady;
using DeckReady.Models;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        var app = new App();
        app.InitializeComponent();
        app.StartupUri = null;
        var window = new MainWindow();
        object? Call(string name, params object[] args) => typeof(MainWindow).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(window,args);
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
            Call("EditLibraryTrack",incomplete);
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
            Check(new FileInfo(path).Length == 0, "Opening/reviewing must not change audio");
            Console.WriteLine("WPF library-open and tag review smoke checks passed.");
        }
        finally { window.Close(); File.Delete(path); app.Shutdown(); }
    }
}
