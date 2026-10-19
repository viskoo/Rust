#Requires -RunAsAdministrator
<#
.SYNOPSIS
  A lancer sur la machine OFFLINE, depuis le dossier RustOfflineKit.
  Installe VS Build Tools (linker MSVC + SDK), Rust, rust-src, rust-analyzer,
  puis deploie le projet (optionnel). Les crates sont telechargees par Cargo apres l'installation.
  Build Tools : layout hors ligne dans vslayout\ s'il existe, sinon buildtools\vs_BuildTools.exe
  (installation en ligne).
  rust-src : deposer rust-src-<version>.tar.gz (ou .tar.xz) dans le dossier rust\ du kit,
  meme version que le MSI (https://static.rust-lang.org/dist/rust-src-<version>.tar.gz).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-Offline.ps1 -ProjectDest C:\dev\monappli
#>
param(
    [string]$ProjectDest = "C:\dev\app",
    [switch]$SkipBuildTools,
    [switch]$SkipRust,           # si Rust est deja installe
    [switch]$SkipRustSrc,
    [switch]$SkipBuildTest
)

$ErrorActionPreference = "Stop"
$Kit = $PSScriptRoot
$LogDir = Join-Path $Kit "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Update-SessionPath {
    $m = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $u = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$m;$u"
}

function Assert-Exit($proc, $what) {
    if ($proc.ExitCode -notin 0, 3010) { throw "$what a echoue (code $($proc.ExitCode)). Voir $LogDir." }
    if ($proc.ExitCode -eq 3010) { Write-Warning "$what : un redemarrage est recommande." }
}

# ------------------------------------------------ 1. Visual Studio Build Tools
if (-not $SkipBuildTools) {
    Write-Host "[1/5] Visual Studio Build Tools" -ForegroundColor Cyan
    # Layout complet (vslayout\, cree avec --layout) : installation sans reseau.
    # Sinon, bootstrapper seul (buildtools\) : les paquets sont telecharges.
    $layout  = Join-Path $Kit "vslayout"
    $offline = Test-Path (Join-Path $layout "Catalog.json")
    if ($offline) {
        $vsExe = Join-Path $layout "vs_BuildTools.exe"
    } else {
        $vsExe = Join-Path $Kit "buildtools\vs_BuildTools.exe"
        Write-Host "  pas de layout hors ligne : telechargement des paquets (reseau requis)..."
    }
    if (-not (Test-Path $vsExe)) { throw "Installeur Build Tools introuvable : $vsExe" }

    # Certificats du layout (necessaires hors ligne pour valider les paquets)
    $certDir = Join-Path $layout "certificates"
    if ($offline -and (Test-Path $certDir)) {
        Get-ChildItem $certDir -Include *.p12, *.pfx -Recurse | ForEach-Object {
            try {
                Import-PfxCertificate -FilePath $_.FullName -CertStoreLocation Cert:\LocalMachine\Root `
                    -Password (New-Object System.Security.SecureString) | Out-Null
                Write-Host "  certificat importe : $($_.Name)"
            } catch { Write-Warning "Import du certificat $($_.Name) impossible : $_" }
        }
    }

    $vsArgs = "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    if ($offline) { $vsArgs = "--noweb $vsArgs" }
    $p = Start-Process -FilePath $vsExe -ArgumentList $vsArgs -Wait -PassThru
    Assert-Exit $p "Installation des Build Tools"
}

# ------------------------------------------------------------------ 2. Rust
Write-Host "[2/5] Rust" -ForegroundColor Cyan
if ($SkipRust) {
    Write-Host "  ignore (-SkipRust)" -ForegroundColor Yellow
} else {
    $msi = Get-ChildItem (Join-Path $Kit "rust") -Filter "rust-*-x86_64-pc-windows-msvc.msi" | Select-Object -First 1
    if (-not $msi) { throw "MSI Rust introuvable dans $Kit\rust" }
    Write-Host "  installation de $($msi.Name) (plusieurs minutes, patience)..."
    # WaitForExit() n'attend que msiexec lui-meme (Start-Process -Wait peut rester bloque).
    $p = Start-Process msiexec.exe -PassThru `
            -ArgumentList "/i `"$($msi.FullName)`" /qn /norestart /l*v `"$LogDir\rust-msi.log`""
    $p.WaitForExit()
    Assert-Exit $p "Installation de Rust"
    Write-Host "  Rust installe."
}

# Le mode offline de Cargo ne doit pas etre force : on ne touche a la variable
# que si elle existe (ecrire une variable Machine diffuse un message a toutes les fenetres).
if ([Environment]::GetEnvironmentVariable("CARGO_NET_OFFLINE", "Machine")) {
    Write-Host "  suppression de CARGO_NET_OFFLINE"
    [Environment]::SetEnvironmentVariable("CARGO_NET_OFFLINE", $null, "Machine")
}
Remove-Item Env:\CARGO_NET_OFFLINE -ErrorAction SilentlyContinue

# ----------------------------------------------------------------- 3. rust-src
# Sources de la bibliotheque standard (necessaires a rust-analyzer). Le MSI ne les
# contient pas : on extrait le tarball officiel dans le sysroot (lib\rustlib\src).
Write-Host "[3/5] rust-src" -ForegroundColor Cyan
if ($SkipRustSrc) {
    Write-Host "  ignore (-SkipRustSrc)" -ForegroundColor Yellow
} else {
    $srcTar = Get-ChildItem (Join-Path $Kit "rust") -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '^rust-src-.+\.tar\.(gz|xz)$' } | Select-Object -First 1
    if (-not $srcTar) {
        Write-Warning "rust-src-*.tar.gz introuvable dans $Kit\rust : rust-analyzer n'aura pas les sources de std."
    } else {
        Update-SessionPath
        if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) { throw "rustc introuvable : impossible d'installer rust-src." }
        $sysroot = (& rustc --print sysroot).Trim()
        $rustVer = ((& rustc --version) -split ' ')[1]
        if ($srcTar.Name -notlike "rust-src-$rustVer.*") {
            Write-Warning "$($srcTar.Name) ne correspond pas a rustc $rustVer."
        }
        Write-Host "  extraction de $($srcTar.Name) dans $sysroot..."
        $tmp = Join-Path $env:TEMP "rust-src-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            # tar.exe de Windows (bsdtar) : pas celui de Git, qui ne comprend pas les chemins C:\
            & "$env:SystemRoot\System32\tar.exe" -xf $srcTar.FullName -C $tmp
            if ($LASTEXITCODE -ne 0) { throw "Extraction de $($srcTar.Name) impossible (code $LASTEXITCODE)." }
            $rustlib = Get-ChildItem $tmp -Directory | ForEach-Object { Join-Path $_.FullName "rust-src\lib\rustlib" } |
                       Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $rustlib) { throw "Structure inattendue dans $($srcTar.Name) (rust-src\lib\rustlib absent)." }
            $dest = Join-Path $sysroot "lib\rustlib"
            Remove-Item (Join-Path $dest "src") -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $rustlib "src") $dest -Recurse -Force
            Write-Host "  rust-src installe dans $dest\src"
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------ 4. rust-analyzer
$raZip = Join-Path $Kit "rust\rust-analyzer.zip"
if (Test-Path $raZip) {
    Write-Host "[4/5] rust-analyzer" -ForegroundColor Cyan
    $raDir = Join-Path $env:ProgramFiles "rust-analyzer"
    New-Item -ItemType Directory -Force -Path $raDir | Out-Null
    Expand-Archive -Path $raZip -DestinationPath $raDir -Force
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$raDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$raDir", "Machine")
    }
}

# --------------------------------------------------------------- 5. Projet
Write-Host "[5/5] Projet" -ForegroundColor Cyan
Update-SessionPath
$src = Join-Path $Kit "project"
if (Test-Path $src) {
    New-Item -ItemType Directory -Force -Path $ProjectDest | Out-Null
    Copy-Item "$src\*" $ProjectDest -Recurse -Force
    Write-Host "  projet copie dans $ProjectDest"
}

# ------------------------------------------------------------- Verification
Write-Host "`nVerification :" -ForegroundColor Cyan
rustc --version
cargo --version
$stdSrc = Join-Path (rustc --print sysroot).Trim() "lib\rustlib\src\rust\library"
if (Test-Path $stdSrc) { Write-Host "rust-src : $stdSrc" } else { Write-Warning "rust-src absent ($stdSrc)." }
if (Get-Command rust-analyzer -ErrorAction SilentlyContinue) { rust-analyzer --version }

if (-not $SkipBuildTest -and (Test-Path (Join-Path $ProjectDest "Cargo.toml"))) {
    Write-Host "`nTest de compilation (Cargo telecharge les crates via le reseau)..." -ForegroundColor Cyan
    Push-Location $ProjectDest
    try {
        cargo build --release
        if ($LASTEXITCODE -ne 0) { throw "La compilation de test a echoue." }
    } finally { Pop-Location }
}

Write-Host "`nInstallation terminee. Ouvre un NOUVEAU terminal pour avoir le PATH a jour." -ForegroundColor Green
