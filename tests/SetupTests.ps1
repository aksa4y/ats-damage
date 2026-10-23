$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/run.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
# Load only pure helper declarations, never the installation entry point.
foreach ($name in @('Find-Game', 'Run')) {
    $fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (!$fn) { throw "Missing helper $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ats-setup-test-' + [guid]::NewGuid().ToString('N'))
try {
    $steam = Join-Path $temp 'Steam Client'
    $library = Join-Path $temp 'Second Library'
    $game = Join-Path $library 'steamapps/common/American Truck Simulator'
    New-Item -ItemType Directory -Path (Join-Path $steam 'steamapps'), (Join-Path $game 'bin/win_x64') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'bin/win_x64/amtrucks.exe') -Value ''
    Set-Content -LiteralPath (Join-Path $steam 'steamapps/libraryfolders.vdf') -Value ('"libraryfolders" { "1" { "path" "' + $library.Replace('\','\\') + '" } }')
    Set-Content -LiteralPath (Join-Path $library 'steamapps/appmanifest_270880.acf') -Value '"AppState" { "appid" "270880" "installdir" "American Truck Simulator" }'
    $found = Find-Game $steam
    if (!$found -or (Resolve-Path $found).Path -ne (Resolve-Path $game).Path) { throw 'Secondary Steam library detection failed' }
    Remove-Item -LiteralPath (Join-Path $game 'bin/win_x64/amtrucks.exe')
    if (Find-Game $steam) { throw 'Incomplete installation accepted' }
    Remove-Item -LiteralPath (Join-Path $steam 'steamapps/libraryfolders.vdf')
    if (Find-Game $steam) { throw 'Missing library should return no game' }
    $shell = Join-Path $PSHOME 'powershell.exe'
    if (!(Test-Path $shell)) { $shell = Join-Path $PSHOME 'pwsh' }
    Run $shell @('-NoProfile', '-Command', 'exit 0')
    $failed = $false
    try { Run $shell @('-NoProfile', '-Command', 'exit 7') } catch { $failed = $true }
    if (!$failed) { throw 'Nonzero native exit code was ignored' }
    Write-Host 'PASS: PowerShell syntax, Steam libraries with spaces, incomplete game, missing library, native exit codes.'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
