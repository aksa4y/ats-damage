#Requires -Version 5.1
[CmdletBinding()]
param([string]$GamePath = '', [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path $PSScriptRoot -Parent
$Cache = Join-Path $Root '.setup'
$HeadersCommit = '1243098a897c625e5ddcab1fd4de4327bd0c8bb8'
$SpfHash = '92b98aacb6cf1099b7cc218438c680ef92d32dbaba09d2b474e640ebb25eb1d6'
$Transcript = $false
function Say([string]$Text) { Write-Host "`n[ATS Damage] $Text" -ForegroundColor Cyan }
function Download([string]$Url, [string]$Path) {
    Say "Загрузка: $Url"
    $part = "$Path.partial"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $part -TimeoutSec 300
        Move-Item -LiteralPath $part -Destination $Path -Force
    } finally { if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force } }
}
function Run([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Ошибка команды $Exe (код $LASTEXITCODE)." }
}
function Install-Signed([string]$Exe, [string]$Publisher, [string]$Arguments) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Exe
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $Publisher) {
        throw "Не удалось подтвердить цифровую подпись установщика: $Exe"
    }
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -Wait -PassThru
    if ($p.ExitCode -in @(3010, 1641)) {
        throw 'Установщик требует перезагрузки Windows. Перезагрузите ПК и повторно запустите run.bat.'
    }
    if ($p.ExitCode -ne 0) { throw "Установщик завершился с кодом $($p.ExitCode)." }
}
function Find-Steam {
    foreach ($entry in @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam', 'InstallPath'))) {
        $value = Get-ItemProperty -Path $entry[0] -Name $entry[1] -ErrorAction SilentlyContinue
        if ($value) {
            $path = $value.($entry[1])
            if (Test-Path -LiteralPath (Join-Path $path 'steam.exe')) { return $path }
        }
    }
    return $null
}
function Find-Game([string]$SteamPath) {
    $libraries = @($SteamPath)
    $vdf = Join-Path $SteamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $text = Get-Content -LiteralPath $vdf -Raw
        foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
            $libraries += $m.Groups[1].Value.Replace('\\', '\')
        }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $lib 'steamapps\appmanifest_270880.acf'
        if (!(Test-Path -LiteralPath $manifest)) { continue }
        $text = Get-Content -LiteralPath $manifest -Raw
        $match = [regex]::Match($text, '"installdir"\s+"([^"]+)"')
        if ($match.Success) {
            $candidate = Join-Path $lib ('steamapps\common\' + $match.Groups[1].Value)
            if (Test-Path -LiteralPath (Join-Path $candidate 'bin\win_x64\amtrucks.exe')) { return $candidate }
        }
    }
    return $null
}
function Find-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (!(Test-Path -LiteralPath $vswhere)) { return $null }
    $instances = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -eq 0 -and $instances) { return [string](@($instances)[0]) }
    return $null
}
function Find-Sdk {
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Lib'
    if (!(Test-Path -LiteralPath $kits)) { return $false }
    foreach ($version in Get-ChildItem -LiteralPath $kits -Directory) {
        $include = Join-Path (Split-Path $kits -Parent) ('Include\' + $version.Name)
        if ((Test-Path (Join-Path $version.FullName 'um\x64\kernel32.lib')) -and
            (Test-Path (Join-Path $version.FullName 'ucrt\x64\ucrt.lib')) -and
            (Test-Path (Join-Path $include 'um\Windows.h'))) { return $true }
    }
    return $false
}
try {
    if (![Environment]::Is64BitOperatingSystem -or ![Environment]::Is64BitProcess) { throw 'Требуется Windows x64 и 64-битный PowerShell.' }
    if ([Environment]::OSVersion.Version.Major -lt 10) { throw 'Требуется Windows 10 или 11.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Say 'Windows запросит права администратора для установки зависимостей и записи в папку игры.'
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        if ($GamePath) { $arguments += ' -GamePath "' + $GamePath.TrimEnd('\') + '"' }
        if ($NoLaunch) { $arguments += ' -NoLaunch' }
        $child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $child.ExitCode
    }
    New-Item -ItemType Directory -Path "$Cache\logs" -Force | Out-Null
    Start-Transcript -Path (Join-Path $Cache ('logs\setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')) | Out-Null
    $Transcript = $true
    if (Get-Process -Name amtrucks -ErrorAction SilentlyContinue) { throw 'Закройте ATS и запустите run.bat ещё раз. Работающая игра не будет остановлена автоматически.' }
    Say 'Проверка Steam и установленной ATS.'
    $steam = Find-Steam
    if (!$steam) {
        Download 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe' "$Cache\SteamSetup.exe"
        Install-Signed "$Cache\SteamSetup.exe" 'Valve' '/S'
        $steam = Find-Steam
        if (!$steam) { throw 'Steam установлен, но путь пока не найден. Запустите Steam, войдите в аккаунт и повторите запуск.' }
    }
    if (!$GamePath) { $GamePath = Find-Game $steam }
    if (!$GamePath) {
        Start-Process 'explorer.exe' -ArgumentList 'steam://install/270880'
        throw 'ATS не найдена. Установите приобретённую игру в Steam, дождитесь завершения загрузки и повторно запустите run.bat. Для нестандартного пути: run.bat -GamePath "D:\Games\American Truck Simulator"'
    }
    $GamePath = (Resolve-Path -LiteralPath $GamePath).Path
    if (!(Test-Path -LiteralPath (Join-Path $GamePath 'bin\win_x64\amtrucks.exe'))) { throw 'Указанная папка не содержит ATS x64.' }
    Say "Игра: $GamePath"
    # Prefer an existing supported CMake installation. Portable fallback needs no PATH changes.
    $cmake = $null
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) {
        $output = & $command.Source --version
        if ($LASTEXITCODE -eq 0 -and ($output[0] -match '([0-9]+\.[0-9]+\.[0-9]+)') -and [version]$Matches[1] -ge [version]'3.24.0') { $cmake = $command.Source }
    }
    if (!$cmake) {
        $cmake = "$Cache\cmake-3.31.8-windows-x86_64\bin\cmake.exe"
        if (!(Test-Path -LiteralPath $cmake)) {
            $base = 'https://github.com/Kitware/CMake/releases/download/v3.31.8'
            Download "$base/cmake-3.31.8-windows-x86_64.zip" "$Cache\cmake.zip"
            Download "$base/cmake-3.31.8-SHA-256.txt" "$Cache\cmake-sha256.txt"
            $line = @(Get-Content "$Cache\cmake-sha256.txt" | Where-Object { $_ -match '^[a-fA-F0-9]{64}\s+\*?cmake-3\.31\.8-windows-x86_64\.zip$' })
            if ($line.Count -ne 1 -or (Get-FileHash "$Cache\cmake.zip" -Algorithm SHA256).Hash -ne ($line[0] -split '\s+')[0]) { throw 'Контрольная сумма CMake не совпала.' }
            Expand-Archive -LiteralPath "$Cache\cmake.zip" -DestinationPath $Cache -Force
        }
    }
    Say 'Проверка Visual Studio C++ 2022 и Windows SDK (первая установка может занять длительное время).'
    $vs = Find-VisualStudio
    if (!$vs -or !(Find-Sdk)) {
        Download 'https://aka.ms/vs/17/release/vs_buildtools.exe' "$Cache\vs_buildtools.exe"
        $installArgs = '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        # Modify an existing Build Tools installation to add a missing SDK.
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $vswhere) {
            $bt = & $vswhere -latest -products Microsoft.VisualStudio.Product.BuildTools -version '[17.0,18.0)' -property installationPath
            if ($bt) { $installArgs = 'modify --installPath "' + [string](@($bt)[0]) + '" ' + $installArgs }
        }
        Install-Signed "$Cache\vs_buildtools.exe" 'Microsoft Corporation' $installArgs
        $vs = Find-VisualStudio
        if (!$vs -or !(Find-Sdk)) { throw 'C++ или Windows SDK не обнаружены после установки. Проверьте Visual Studio Installer.' }
    }
    Say 'Загрузка зафиксированных SPF headers.'
    $headers = Join-Path $Cache "SPF-Framework-$HeadersCommit"
    if (!(Test-Path "$headers\include\SPF\SPF_API\SPF_Plugin.h")) {
        Download "https://github.com/TrackAndTruckDevs/SPF-Framework/archive/$HeadersCommit.zip" "$Cache\spf-source.zip"
        Expand-Archive -LiteralPath "$Cache\spf-source.zip" -DestinationPath $Cache -Force
    }
    $build = Join-Path $Root 'build-windows-run'
    Say 'Сборка плагина и тестирование.'
    Run $cmake @('-S', $Root, '-B', $build, '-G', 'Visual Studio 17 2022', '-A', 'x64', "-DCMAKE_GENERATOR_INSTANCE=$vs", "-DSPF_ROOT=$headers")
    Run $cmake @('--build', $build, '--config', 'Release')
    Run (Join-Path (Split-Path $cmake -Parent) 'ctest.exe') @('--test-dir', $build, '-C', 'Release', '--output-on-failure')
    $dll = Join-Path $build 'Release\ATSDamage.dll'
    if (!(Test-Path -LiteralPath $dll)) { throw 'Сборка не создала ATSDamage.dll.' }
    $plugins = Join-Path $GamePath 'bin\win_x64\plugins'
    $runtime = Join-Path $plugins 'spf-framework.dll'
    $installRuntime = $true
    if (Test-Path -LiteralPath $runtime) {
        $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($runtime)
        $version = [version]::new($v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart)
        if ($version -gt [version]'1.2.5') {
            if (!(Test-Path "$plugins\spfAssets")) { throw 'У нового SPF отсутствует spfAssets. Восстановите его из соответствующего релиза SPF.' }
            $installRuntime = $false
            Say "Сохранён установленный SPF $version (новее 1.2.5)."
        } elseif ((Get-FileHash $runtime -Algorithm SHA256).Hash -eq $SpfHash -and (Test-Path "$plugins\spfAssets")) { $installRuntime = $false }
    }
    $runtimeFiles = @()
    if ($installRuntime) {
        Say 'Установка официального SPF Framework 1.2.5.'
        Download 'https://github.com/TrackAndTruckDevs/SPF-Framework/releases/download/v1.2.5/spf-framework_v1.2.5.zip' "$Cache\spf-runtime.zip"
        $unpack = Join-Path $Cache ('spf-runtime-' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -LiteralPath "$Cache\spf-runtime.zip" -DestinationPath $unpack
        $candidates = @(Get-ChildItem $unpack -Filter spf-framework.dll -Recurse -File)
        if ($candidates.Count -ne 1) { throw 'Неожиданная структура архива SPF.' }
        $sourceDll = $candidates[0]
        if ((Get-FileHash $sourceDll.FullName -Algorithm SHA256).Hash -ne $SpfHash) { throw 'SHA-256 библиотеки SPF не совпадает с официальным релизом 1.2.5.' }
        $sourceAssets = Join-Path $sourceDll.DirectoryName 'spfAssets'
        if (!(Test-Path $sourceAssets)) { throw 'Архив SPF не содержит spfAssets рядом с DLL.' }
        $runtimeFiles += @{ Source = $sourceDll.FullName; Relative = 'spf-framework.dll' }
        foreach ($f in Get-ChildItem $sourceAssets -File -Recurse) {
            $relative = $f.FullName.Substring($sourceAssets.Length).TrimStart('\')
            $runtimeFiles += @{ Source = $f.FullName; Relative = "spfAssets\$relative" }
        }
    }
    # Never copy bundled example plugins or touch profile/save files.
    $runtimeFiles += @{ Source = $dll; Relative = 'spfPlugins\ATSDamage\ATSDamage.dll' }
    if (Get-Process -Name amtrucks -ErrorAction SilentlyContinue) { throw 'ATS была запущена во время сборки. Закройте игру и повторите запуск.' }
    $backup = Join-Path $Cache ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $changed = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($file in $runtimeFiles) {
            $dest = Join-Path $plugins $file.Relative
            $old = Join-Path $backup $file.Relative
            $existed = Test-Path -LiteralPath $dest
            if ($existed) {
                New-Item -ItemType Directory -Path (Split-Path $old -Parent) -Force | Out-Null
                Copy-Item -LiteralPath $dest -Destination $old
            }
            $changed.Add(@{ Destination = $dest; Backup = $old; Existed = $existed })
            New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $file.Source -Destination $dest -Force
            if ((Get-FileHash $dest).Hash -ne (Get-FileHash $file.Source).Hash) { throw "Ошибка проверки скопированного файла: $dest" }
        }
    } catch {
        $failure = $_
        for ($i = $changed.Count - 1; $i -ge 0; $i--) {
            $item = $changed[$i]
            try {
                if ($item.Existed) { Copy-Item -LiteralPath $item.Backup -Destination $item.Destination -Force }
                elseif (Test-Path -LiteralPath $item.Destination) { Remove-Item -LiteralPath $item.Destination -Force }
            } catch { Write-Warning "Не удалось восстановить $($item.Destination). Резервная копия: $backup" }
        }
        throw $failure
    }
    Say 'Готово. Левый Ctrl + левый Shift + D — панель (новая установка); Delete — интерфейс SPF. Визуальная подмена материалов пока не реализована.'
    Say 'Если раньше использовалась F7: откройте SPF клавишей Delete и переназначьте ATSDamage / Panel.toggle. Сохранённые привязки автоматически не меняются.'
    if (!$NoLaunch) {
        # Explorer delegates the Steam URI to the interactive desktop session.
        Start-Process 'explorer.exe' -ArgumentList 'steam://rungameid/270880'
        Say 'Команда запуска отправлена Steam. Успешная загрузка плагина проверяется уже в игре.'
    }
    if ($Transcript) { Stop-Transcript | Out-Null; $Transcript = $false }
    exit 0
} catch {
    Write-Host "`nОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
    if ($Transcript) { Stop-Transcript | Out-Null }
    # Keep elevated error windows visible; parent batch also preserves exit code.
    Read-Host 'Нажмите Enter для закрытия' | Out-Null
    exit 1
}
