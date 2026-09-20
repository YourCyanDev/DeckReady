param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) {
    throw "MSI not found: $MsiPath"
}

$resolvedMsi = (Resolve-Path -LiteralPath $MsiPath).Path
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.GetType().InvokeMember(
    'OpenDatabase',
    'InvokeMethod',
    $null,
    $installer,
    @($resolvedMsi, 0)
)

$query = 'SELECT Cabinet FROM Media'
$view = $database.GetType().InvokeMember(
    'OpenView',
    'InvokeMethod',
    $null,
    $database,
    @($query)
)

$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null

$foundCabinet = $false
$externalCabinets = New-Object System.Collections.Generic.List[string]

try {
    while ($true) {
        $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if ($null -eq $record) {
            break
        }

        $cabinet = $record.GetType().InvokeMember(
            'StringData',
            'GetProperty',
            $null,
            $record,
            @(1)
        )

        if (-not [string]::IsNullOrWhiteSpace($cabinet)) {
            $foundCabinet = $true
            Write-Host "  Media cabinet: $cabinet"

            if (-not $cabinet.StartsWith('#')) {
                $externalCabinets.Add($cabinet)
            }
        }
    }
}
finally {
    $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null) | Out-Null
}

if (-not $foundCabinet) {
    throw 'The MSI Media table contains no cabinet entry.'
}

if ($externalCabinets.Count -gt 0) {
    throw "External cabinet reference(s) found in MSI Media table: $($externalCabinets -join ', ')"
}

Write-Host '  Embedded cabinet verification passed.'
exit 0
