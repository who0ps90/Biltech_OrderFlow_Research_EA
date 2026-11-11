[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MetaEditor,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SourceRelativePath = 'Biltech_OrderFlow_Research_EA.mq5',
    [ValidateRange(10, 600)][int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$compilerPath = (Resolve-Path -LiteralPath $MetaEditor).Path
$sourcePath = [IO.Path]::GetFullPath((Join-Path $projectPath $SourceRelativePath))
if (-not $sourcePath.StartsWith(($projectPath.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetExtension($sourcePath) -ine '.mq5') {
    throw 'SourceRelativePath must name an MQ5 source inside ProjectRoot.'
}
$binaryPath = [IO.Path]::ChangeExtension($sourcePath, '.ex5')
$buildPath = Join-Path $projectPath 'build'
$logName = if ($SourceRelativePath -eq 'Biltech_OrderFlow_Research_EA.mq5') { 'compile.log' } else { [IO.Path]::GetFileNameWithoutExtension($sourcePath) + '.compile.log' }
$logPath = Join-Path $buildPath $logName
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Missing source: $sourcePath" }
if ([IO.Path]::GetFileName($compilerPath) -notmatch '^metaeditor(64)?\.exe$') {
    throw 'MetaEditor must point to the locally installed metaeditor.exe or metaeditor64.exe.'
}
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
$startedUtc = [DateTime]::UtcNow
$arguments = @('/compile:"{0}"' -f $sourcePath; '/log:"{0}"' -f $logPath)
$process = Start-Process -FilePath $compilerPath -ArgumentList $arguments -WorkingDirectory $projectPath -WindowStyle Hidden -PassThru
$deadlineUtc = $startedUtc.AddSeconds($TimeoutSeconds)
$resultMatch = $null
do {
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        $logText = Get-Content -LiteralPath $logPath -Raw
        $matches = [regex]::Matches($logText, '(?im)(\d+)\s+errors?,\s*(\d+)\s+warnings?')
        if ($matches.Count -gt 0) { $resultMatch = $matches[$matches.Count - 1]; break }
    }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $deadlineUtc)
if ($null -eq $resultMatch) {
    throw "No completed compiler result within $TimeoutSeconds seconds. Inspect $logPath and MetaEditor. No compilation success is assumed."
}
$errors = [int]$resultMatch.Groups[1].Value
$warnings = [int]$resultMatch.Groups[2].Value
Get-Content -LiteralPath $logPath | Select-Object -Last 30
if ($errors -ne 0) { throw "MQL5 compilation failed with $errors error(s), $warnings warning(s). Log: $logPath" }
if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) { throw 'Compiler reported zero errors but no EX5 was produced.' }
if ((Get-Item -LiteralPath $binaryPath).LastWriteTimeUtc -lt $startedUtc.AddSeconds(-2)) {
    throw 'The EX5 predates this build. Inspect MetaEditor rather than using a stale binary.'
}
Write-Output "MQL5 compilation completed: $errors errors, $warnings warnings. Binary: $binaryPath"
