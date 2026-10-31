param(
    [Parameter(Mandatory=$true)][string]$ReleaseLabel,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$logo = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot '..\src\DeckReady.Windows\Assets\DeckReady.png'))
function New-InstallerImage([int]$height, [bool]$dialog) {
    $bitmap = New-Object System.Drawing.Bitmap(493, $height)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.Clear([System.Drawing.Color]::White)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $resources = New-Object System.Collections.Generic.List[System.IDisposable]
    try {
        if ($dialog) {
            $panel = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(23,25,28))
            $accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(32,224,190))
            $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(182,195,202))
            $titleFont = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $bodyFont = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
            $smallFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
            foreach ($item in @($panel,$accent,$muted,$titleFont,$bodyFont,$smallFont)) { $resources.Add($item) }
            $g.FillRectangle($panel,0,0,165,$height)
            $g.FillRectangle($accent,163,0,2,$height)
            $g.DrawImage($logo,30,40,104,104)
            $g.DrawString('DeckReady',$titleFont,[System.Drawing.Brushes]::White,20,172)
            $g.DrawString('Your music.',$bodyFont,$muted,20,207)
            $g.DrawString('Ready for the decks.',$bodyFont,$muted,20,224)
            $g.DrawString("Alpha $ReleaseLabel",$smallFont,$muted,20,282)
        } else {
            # Leave the standard wizard's title and description area clear.
            $g.DrawImage($logo,435,5,48,48)
        }
        $name = if ($dialog) { 'InstallerDialog.png' } else { 'InstallerBanner.png' }
        $bitmap.Save((Join-Path $OutputDirectory $name),[System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        foreach ($item in $resources) { $item.Dispose() }
        $g.Dispose(); $bitmap.Dispose()
    }
}
try {
    New-InstallerImage 312 $true
    New-InstallerImage 58 $false
    @{ release_label=$ReleaseLabel; dialog_size=@(493,312); banner_size=@(493,58) } | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'branding.json')
} finally { $logo.Dispose() }
