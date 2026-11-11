[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TerminalDirectory,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateRange(10, 300)][int]$TimeoutSeconds = 45,
    [switch]$KeepRuntime
)

$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$installationPath = (Resolve-Path -LiteralPath $TerminalDirectory).Path
$compilerPath = Join-Path $installationPath 'MetaEditor64.exe'
$terminalSource = Join-Path $installationPath 'terminal64.exe'
if (-not (Test-Path -LiteralPath $terminalSource -PathType Leaf)) { throw 'No terminal64.exe in TerminalDirectory.' }
& (Join-Path $PSScriptRoot 'compile.ps1') -MetaEditor $compilerPath -ProjectRoot $projectPath -SourceRelativePath 'scripts\Biltech_AllTests.mq5'
$buildPath = Join-Path $projectPath 'build'
$runtimeParent = Join-Path $buildPath 'mt5-native'
$runName = 'run_' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runtimePath = Join-Path $runtimeParent $runName
New-Item -ItemType Directory -Path $runtimePath -Force | Out-Null
# An explicit allow list: never copy broker Config, accounts, profiles, history,
# saved passwords, certificates, or the ordinary terminal data folder.
Copy-Item -LiteralPath $terminalSource -Destination (Join-Path $runtimePath 'terminal64.exe')
$testerSource = Join-Path $installationPath 'metatester64.exe'
if (Test-Path -LiteralPath $testerSource -PathType Leaf) { Copy-Item -LiteralPath $testerSource -Destination (Join-Path $runtimePath 'metatester64.exe') }
$defaultSymbols = Join-Path $installationPath 'Bases\Default\Symbols'
if (Test-Path -LiteralPath $defaultSymbols -PathType Container) {
    $symbolTarget = Join-Path $runtimePath 'Bases\Default\Symbols'
    New-Item -ItemType Directory -Path $symbolTarget -Force | Out-Null
    Get-ChildItem -LiteralPath $defaultSymbols -File | Where-Object { $_.Name -match '^(symbols|selected)-\d+\.dat$' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $symbolTarget $_.Name)
    }
}
$scriptTarget = Join-Path $runtimePath 'MQL5\Scripts'
$fixtureTarget = Join-Path $runtimePath 'MQL5\Files\Biltech\fixtures'
New-Item -ItemType Directory -Path $scriptTarget,$fixtureTarget -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectPath 'scripts\Biltech_AllTests.ex5') -Destination (Join-Path $scriptTarget 'Biltech_AllTests.ex5')
Get-ChildItem -LiteralPath (Join-Path $projectPath 'tests\fixtures') -Filter '*.csv' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $fixtureTarget $_.Name)
}
$configPath = Join-Path $runtimePath 'offline-tests.ini'
$configText = @'
[Common]
Login=0
KeepPrivate=1
NewsEnable=0
CertInstall=0
ProxyEnable=0
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=0
Account=1
Profile=1
[StartUp]
Script=Biltech_AllTests
Symbol=EURUSD
Period=M5
ShutdownTerminal=1
'@
[IO.File]::WriteAllText($configPath, $configText, (New-Object Text.UTF8Encoding($false)))
$runtimeTerminal = Join-Path $runtimePath 'terminal64.exe'
$process = Start-Process -FilePath $runtimeTerminal -ArgumentList @('/portable', ('/config:"{0}"' -f $configPath)) -WorkingDirectory $runtimePath -WindowStyle Hidden -PassThru
$completed = $process.WaitForExit($TimeoutSeconds * 1000)
if (-not $completed) {
    # Only terminate the exact isolated child created by this invocation.
    $process.Kill()
    $process.WaitForExit()
}
$logPath = Join-Path $buildPath 'native.log'
$logParts = @("Isolated runtime: $runName", "Completed before timeout: $completed")
foreach ($relative in @('Logs', 'MQL5\Logs')) {
    $logDirectory = Join-Path $runtimePath $relative
    if (Test-Path -LiteralPath $logDirectory) {
        Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' -File | Sort-Object Name | ForEach-Object {
            $logParts += "--- $relative/$($_.Name) ---"
            $logParts += Get-Content -LiteralPath $_.FullName
        }
    }
}
[IO.File]::WriteAllLines($logPath, $logParts, (New-Object Text.UTF8Encoding($false)))
$resultSource = Join-Path $runtimePath 'MQL5\Files\Biltech_native_result.csv'
$resultTarget = Join-Path $buildPath 'native_result.csv'
$resultExists = Test-Path -LiteralPath $resultSource -PathType Leaf
if ($resultExists) { Copy-Item -LiteralPath $resultSource -Destination $resultTarget -Force }
if (-not $KeepRuntime) {
    # Verify the resolved absolute target before recursive cleanup.
    $resolvedRuntime = (Resolve-Path -LiteralPath $runtimePath).Path
    $resolvedParent = (Resolve-Path -LiteralPath $runtimeParent).Path
    if (-not $resolvedRuntime.StartsWith(($resolvedParent.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedRuntime) -notmatch '^run_\d{8}_\d{6}_[a-f0-9]{8}$') {
        throw 'Runtime cleanup path verification failed.'
    }
    Remove-Item -LiteralPath $resolvedRuntime -Recurse -Force
}
if (-not $resultExists) {
    throw "Native assertions did not produce a result. No execution success is assumed. Inspect $logPath."
}
$results = Import-Csv -LiteralPath $resultTarget
$summary = @($results | Where-Object suite -eq 'total')
if ($summary.Count -ne 1 -or [int]$summary[0].failed -ne 0 -or [int]$summary[0].passed -lt 1) {
    throw "Native assertions failed. Inspect $resultTarget and $logPath."
}
$results | Format-Table -AutoSize
Write-Output "Native synthetic assertions passed. Results: $resultTarget; log: $logPath. No market backtest or live trading."
