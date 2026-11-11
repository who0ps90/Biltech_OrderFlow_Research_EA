[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$DataFolder,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$terminalPath = (Resolve-Path -LiteralPath $DataFolder).Path
$mqlPath = Join-Path $terminalPath 'MQL5'
if (-not (Test-Path -LiteralPath $mqlPath -PathType Container)) {
    throw 'DataFolder must be the existing MT5 File > Open Data Folder directory, containing MQL5.'
}
$expertPath = [IO.Path]::GetFullPath((Join-Path $mqlPath 'Experts\Biltech_OrderFlow_Research_EA'))
$presetPath = [IO.Path]::GetFullPath((Join-Path $mqlPath 'Profiles\Tester\Biltech_OrderFlow_Research_EA'))
foreach ($destinationRoot in @($expertPath, $presetPath)) {
    if (-not $destinationRoot.StartsWith(($mqlPath.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Destination is outside the requested MT5 MQL5 directory: $destinationRoot"
    }
    if ($destinationRoot.Equals($projectPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ProjectRoot and install destination must differ.'
    }
}
$files = @()
foreach ($name in @('Biltech_OrderFlow_Research_EA.mq5', 'Biltech_OrderFlow_Research_EA.ex5')) {
    $candidate = Join-Path $projectPath $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $files += [pscustomobject]@{ Source = $candidate; Destination = (Join-Path $expertPath $name) }
    } elseif ($name -like '*.mq5') { throw "Missing source: $candidate" }
}
$includeRoot = Join-Path $projectPath 'Include'
if (-not (Test-Path -LiteralPath $includeRoot -PathType Container)) { throw 'Missing Include directory.' }
Get-ChildItem -LiteralPath $includeRoot -Recurse -File -Filter '*.mqh' | ForEach-Object {
    $relativePath = $_.FullName.Substring($includeRoot.Length).TrimStart('\')
    $files += [pscustomobject]@{ Source = $_.FullName; Destination = (Join-Path (Join-Path $expertPath 'Include') $relativePath) }
}
$configRoot = Join-Path $projectPath 'config'
if (Test-Path -LiteralPath $configRoot) {
    Get-ChildItem -LiteralPath $configRoot -File -Filter '*.set' | ForEach-Object {
        $files += [pscustomobject]@{ Source = $_.FullName; Destination = (Join-Path $presetPath $_.Name) }
    }
}
foreach ($file in $files) {
    if ($PSCmdlet.ShouldProcess($file.Destination, "Copy $($file.Source)")) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $file.Destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.Source -Destination $file.Destination -Force
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'Biltech_OrderFlow_Research_EA.ex5'))) {
    Write-Warning 'No EX5 is available. Compile with MetaEditor before testing.'
}
Write-Output "Expert destination: $expertPath"
Write-Output "Preset destination: $presetPath"
Write-Output 'No terminal was started and no CSV data or state was installed. Supply verified tester input files separately.'
