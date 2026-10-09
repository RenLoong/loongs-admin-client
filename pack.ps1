# Windows pack for LOONGS Admin PC (run in PowerShell from admin/client).
# Builds: web + windows only. Uses Windows `fvm` + .fvmrc (no auto-install).
# Linux/WSL → ./pack.sh   |   macOS → ./pack.command
#
#   .\pack.ps1
#   .\pack.ps1 -SkipWeb
#   .\pack.ps1 -SkipWindows

[CmdletBinding()]
param(
    [switch]$SkipWeb,
    [switch]$SkipWindows,
    [string]$ApiBaseUrl = 'http://{host}:21000',
    [string]$BaseHref = '/admin/web/',
    [string]$Iscc = ''
)

$ErrorActionPreference = 'Stop'
$ClientRoot = $PSScriptRoot
$PublicWeb = Join-Path $ClientRoot '..\server\apps\Admin\public\web'
$DistDir = Join-Path $ClientRoot 'dist'
$ZipPath = Join-Path $DistDir 'admin-pc-windows.zip'

if (-not $env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn' }
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn' }

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Resolve-Fvm {
    $cmd = Get-Command fvm -ErrorAction SilentlyContinue
    if ($cmd) {
        $src = $cmd.Source
        if ($src -match '\\wsl|\\\\wsl') {
            throw "当前 fvm 指向 WSL，请用 Windows 本机 fvm（例如 D:\fvm\fvm.exe）。Linux 构建请用 ./pack.sh"
        }
        return $src
    }
    foreach ($c in @('D:\fvm\fvm.exe', (Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin\fvm.exe'))) {
        if (Test-Path $c) { return $c }
    }
    throw "未找到 Windows fvm（尝试了 PATH、D:\fvm\fvm.exe）"
}

function Resolve-Iscc([string]$hint) {
    if ($hint -and (Test-Path $hint)) { return (Resolve-Path $hint).Path }
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Test-UncPath([string]$p) {
    return $p -match '^\\\\' -or $p -match '^//'
}

function Read-FvmrcVersion([string]$projectRoot) {
    $fvmrc = Join-Path $projectRoot '.fvmrc'
    if (-not (Test-Path $fvmrc)) {
        throw "缺少 .fvmrc，请先固定 Flutter 版本"
    }
    $json = Get-Content $fvmrc -Raw | ConvertFrom-Json
    $ver = [string]$json.flutter
    if (-not $ver) { throw ".fvmrc 没有 flutter 字段" }
    return $ver
}

function Test-FlutterSdk([string]$version) {
    $dirs = @(
        (Join-Path 'D:\fvm\versions' $version),
        (Join-Path $env:USERPROFILE (Join-Path 'fvm\versions' $version))
    )
    if ($env:FVM_CACHE_PATH) {
        $dirs = @((Join-Path $env:FVM_CACHE_PATH (Join-Path 'versions' $version))) + $dirs
    }
    foreach ($d in $dirs) {
        $flutterBat = Join-Path $d 'bin\flutter.bat'
        if (Test-Path $flutterBat) { return $d }
    }
    return $null
}

$fvm = Resolve-Fvm
Write-Host "fvm=$fvm"

$buildRoot = $ClientRoot
if (Test-UncPath $ClientRoot) {
    $stage = if ($env:ADMIN_PC_WIN_STAGE) { $env:ADMIN_PC_WIN_STAGE } else { Join-Path $env:USERPROFILE 'p1\admin-pc-winbuild' }
    Write-Step "Stage UNC -> $stage"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    robocopy $ClientRoot $stage /E /XJ /XD build .dart_tool .idea .git dist linux macos ios android ephemeral .plugin_symlinks /NFL /NDL /NJH /NJS /nc /ns /np /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    $buildRoot = $stage
}

$pinned = Read-FvmrcVersion $buildRoot
Write-Step "fvm use .fvmrc ($pinned) — no auto-install"
$sdk = Test-FlutterSdk $pinned
if (-not $sdk) {
    throw "Flutter $pinned 未安装，打包已中断。`n请先手动安装: fvm install $pinned`n查看已安装版本: fvm list`nLinux/WSL 请用 ./pack.sh；macOS 请用 ./pack.command"
}
Write-Host "SDK=$sdk"

Push-Location $buildRoot
try {
    & $fvm use $pinned --force
    if ($LASTEXITCODE -ne 0) { throw "fvm use failed ($LASTEXITCODE)" }
    & $fvm flutter --version

    if (-not $SkipWeb) {
        Write-Step "fvm flutter build web"
        & $fvm flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get failed" }
        & $fvm flutter build web --release --base-href $BaseHref --dart-define="API_BASE_URL=$ApiBaseUrl"
        if ($LASTEXITCODE -ne 0) { throw "fvm flutter build web failed" }
        $buildWeb = Join-Path $buildRoot 'build\web'
        if (-not (Test-Path (Join-Path $buildWeb 'index.html'))) { throw "missing build/web/index.html" }
        Write-Step "Copy build/web -> $PublicWeb"
        New-Item -ItemType Directory -Force -Path $PublicWeb | Out-Null
        Get-ChildItem -Force $PublicWeb -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        Copy-Item (Join-Path $buildWeb '*') $PublicWeb -Recurse -Force
        $fixer = Join-Path $ClientRoot 'tools\fix_geist_font_names.py'
        if (Test-Path $fixer) {
            $py = Get-Command python -ErrorAction SilentlyContinue
            if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
            if ($py) {
                & $py.Source $fixer (Join-Path $buildWeb 'assets') (Join-Path $PublicWeb 'assets')
            }
        }
        Write-Host "OK public/web"
    } else {
        Write-Host "Skip web"
    }

    if (-not $SkipWindows) {
        Write-Step "fvm flutter build windows"
        & $fvm flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get failed" }
        & $fvm flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "fvm flutter build windows failed" }

        $release = Join-Path $buildRoot 'build\windows\x64\runner\Release'
        if (-not (Test-Path $release)) {
            $alt = Join-Path $buildRoot 'build\windows\runner\Release'
            if (Test-Path $alt) { $release = $alt }
        }
        if (-not (Test-Path $release)) { throw "Release folder not found" }

        $realRelease = Join-Path $ClientRoot 'build\windows\x64\runner\Release'
        New-Item -ItemType Directory -Force -Path (Split-Path $realRelease) | Out-Null
        if (Test-Path $realRelease) { Remove-Item $realRelease -Recurse -Force }
        Copy-Item $release $realRelease -Recurse -Force

        if ($buildRoot -ne $ClientRoot) {
            foreach ($pin in @('.fvmrc', '.fvm')) {
                $from = Join-Path $buildRoot $pin
                $to = Join-Path $ClientRoot $pin
                if (Test-Path $from) {
                    if (Test-Path $to) { Remove-Item $to -Recurse -Force -ErrorAction SilentlyContinue }
                    Copy-Item $from $to -Recurse -Force
                }
            }
        }

        New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
        if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
        Write-Step "Zip -> $ZipPath"
        Compress-Archive -Path (Join-Path $realRelease '*') -DestinationPath $ZipPath -Force
        Write-Host "OK $ZipPath"

        $isccExe = Resolve-Iscc $Iscc
        $iss = Join-Path $ClientRoot 'installer\loongs-admin.iss'
        if (-not (Test-Path $iss)) { $iss = Join-Path $buildRoot 'installer\loongs-admin.iss' }
        if ($isccExe -and (Test-Path $iss)) {
            Write-Step "Inno Setup"
            $issDir = Join-Path $buildRoot 'installer'
            New-Item -ItemType Directory -Force -Path $issDir | Out-Null
            $issRelease = Join-Path $issDir 'Release'
            if (Test-Path $issRelease) { Remove-Item $issRelease -Recurse -Force }
            Copy-Item $realRelease $issRelease -Recurse -Force
            $outDir = Join-Path $buildRoot 'dist'
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            $issText = (Get-Content $iss -Raw) -replace '(?m)^OutputDir=.*$', "OutputDir=$outDir"
            $issWork = Join-Path $issDir '_build.iss'
            [System.IO.File]::WriteAllText($issWork, $issText)
            & $isccExe $issWork
            if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
            $setup = Get-ChildItem $outDir -Filter 'LOONGS-Admin-Setup-*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($setup) {
                Copy-Item $setup.FullName $DistDir -Force
                Write-Host "OK $($setup.Name)"
            }
        } else {
            Write-Warning "Skip installer (ISCC=$isccExe iss=$iss)"
        }
    } else {
        Write-Host "Skip Windows"
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Done (Windows pack.ps1, .fvmrc=$pinned)." -ForegroundColor Green
