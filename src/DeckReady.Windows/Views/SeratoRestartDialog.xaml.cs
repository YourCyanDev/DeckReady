using System.Windows;

namespace DeckReady.Views;

public partial class SeratoRestartDialog : Window
{
    public bool RestartRequested { get; private set; }

    public SeratoRestartDialog()
    {
        InitializeComponent();
    }

    private void Later_Click(object sender, RoutedEventArgs e)
    {
        RestartRequested = false;
        DialogResult = false;
        Close();
    }

    private void Restart_Click(object sender, RoutedEventArgs e)
    {
        RestartRequested = true;
        DialogResult = true;
        Close();
    }
}
