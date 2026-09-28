#Requires -RunAsAdministrator
<#
.SYNOPSIS
  A lancer sur la machine OFFLINE, depuis le dossier RustOfflineKit.
  Installe VS Build Tools (linker MSVC + SDK), Rust, rust-analyzer,
  puis deploie le projet (optionnel). Les crates sont telechargees par Cargo apres l'installation.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-Offline.ps1 -ProjectDest C:\dev\monappli
#>
param(
    [string]$ProjectDest = "C:\dev\app",
    [switch]$SkipBuildTools,
    [switch]$SkipRust,           # si Rust est deja installe
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
    Write-Host "[1/4] Visual Studio Build Tools" -ForegroundColor Cyan
    $layout = Join-Path $Kit "vslayout"
    $vsExe  = Join-Path $layout "vs_BuildTools.exe"
    if (-not (Test-Path $vsExe)) { throw "Layout introuvable : $vsExe" }

    # Certificats du layout (necessaires hors ligne pour valider les paquets)
    $certDir = Join-Path $layout "certificates"
    if (Test-Path $certDir) {
        Get-ChildItem $certDir -Include *.p12, *.pfx -Recurse | ForEach-Object {
            try {
                Import-PfxCertificate -FilePath $_.FullName -CertStoreLocation Cert:\LocalMachine\Root `
                    -Password (New-Object System.Security.SecureString) | Out-Null
                Write-Host "  certificat importe : $($_.Name)"
            } catch { Write-Warning "Import du certificat $($_.Name) impossible : $_" }
        }
    }

    $vsArgs = "--noweb --quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    $p = Start-Process -FilePath $vsExe -ArgumentList $vsArgs -Wait -PassThru
    Assert-Exit $p "Installation des Build Tools"
}

# ------------------------------------------------------------------ 2. Rust
Write-Host "[2/4] Rust" -ForegroundColor Cyan
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

# ------------------------------------------------------------ 3. rust-analyzer
$raZip = Join-Path $Kit "rust\rust-analyzer.zip"
if (Test-Path $raZip) {
    Write-Host "[3/4] rust-analyzer" -ForegroundColor Cyan
    $raDir = Join-Path $env:ProgramFiles "rust-analyzer"
    New-Item -ItemType Directory -Force -Path $raDir | Out-Null
    Expand-Archive -Path $raZip -DestinationPath $raDir -Force
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$raDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$raDir", "Machine")
    }
}

# --------------------------------------------------------------- 4. Projet
Write-Host "[4/4] Projet" -ForegroundColor Cyan
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
