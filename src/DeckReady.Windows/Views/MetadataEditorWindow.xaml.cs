using System.Windows;
using DeckReady.Models;
using DeckReady.Services;

namespace DeckReady.Views;

public partial class MetadataEditorWindow : Window
{
    private readonly string _path;
    private readonly MetadataService _metadataService;
    private readonly TrackMetadata _working;

    public TrackMetadata Result => _working;

    public MetadataEditorWindow(string path, TrackMetadata metadata, MetadataService metadataService)
    {
        InitializeComponent();
        _path = path;
        _metadataService = metadataService;
        _working = metadata.Clone();

        TitleBox.Text = _working.Title;
        ArtistBox.Text = _working.Artist;
        AlbumBox.Text = _working.Album;
        GenreBox.Text = _working.Genre;
        YearBox.Text = _working.Year;
        PathText.Text = path;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        _working.Title = TitleBox.Text.Trim();
        _working.Artist = ArtistBox.Text.Trim();
        _working.Album = AlbumBox.Text.Trim();
        _working.Genre = GenreBox.Text.Trim();
        _working.Year = YearBox.Text.Trim();

        try
        {
            _metadataService.WriteWithSafetyBackup(_path, _working);
            DialogResult = true;
            Close();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"DeckReady could not save those tags.\n\n{ex.Message}", "Metadata Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
