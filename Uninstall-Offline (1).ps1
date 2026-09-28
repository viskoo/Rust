#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Desinstalle ce qu'Install-Offline.ps1 a installe : Rust (MSI), rust-analyzer,
  variable CARGO_NET_OFFLINE. Les elements sensibles sont en option.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Uninstall-Offline.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Uninstall-Offline.ps1 -RemoveBuildTools -RemoveCargoHome -ProjectDest C:\dev\monappli -Force
#>
param(
    [switch]$RemoveBuildTools,   # desinstalle aussi VS Build Tools (peut servir a d'autres outils !)
    [switch]$RemoveCargoHome,    # supprime %USERPROFILE%\.cargo (cache des crates, binaires installes)
    [string]$ProjectDest,        # supprime ce dossier projet (ex: C:\dev\monappli)
    [switch]$Force               # pas de confirmation
)

$ErrorActionPreference = "Stop"

function Confirm-Step($msg) {
    if ($Force) { return $true }
    return ((Read-Host "$msg [o/N]") -match '^(o|oui|y|yes)$')
}

function Remove-FromMachinePath($dir) {
    $paths = [Environment]::GetEnvironmentVariable("Path", "Machine") -split ';' |
             Where-Object { $_ -and ($_.TrimEnd('\') -ne $dir.TrimEnd('\')) }
    [Environment]::SetEnvironmentVariable("Path", ($paths -join ';'), "Machine")
}

# ------------------------------------------------------------------ 1. Rust
Write-Host "[1/5] Rust" -ForegroundColor Cyan
$keys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
$rust = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "Rust *" -and $_.PSChildName -match '^\{[0-9A-Fa-f-]+\}$' }
if ($rust) {
    foreach ($r in $rust) {
        Write-Host "  desinstallation : $($r.DisplayName)"
        # WaitForExit() n'attend que msiexec lui-meme (Start-Process -Wait peut rester bloque).
        $p = Start-Process msiexec.exe -PassThru -ArgumentList "/x $($r.PSChildName) /qn /norestart"
        $p.WaitForExit()
        if ($p.ExitCode -notin 0, 3010) { Write-Warning "Code de sortie msiexec : $($p.ExitCode)" }
        else { Write-Host "  desinstalle." }
    }
} else {
    Write-Host "  aucune installation Rust (MSI) trouvee."
}

# ----------------------------------------------------------- 2. rust-analyzer
Write-Host "[2/5] rust-analyzer" -ForegroundColor Cyan
$raDir = Join-Path $env:ProgramFiles "rust-analyzer"
if (Test-Path $raDir) {
    Remove-Item $raDir -Recurse -Force
    Remove-FromMachinePath $raDir
    Write-Host "  supprime."
} else {
    Write-Host "  non installe."
}

# ------------------------------------------------------------ 3. Variables
Write-Host "[3/5] Variables d'environnement" -ForegroundColor Cyan
if ([Environment]::GetEnvironmentVariable("CARGO_NET_OFFLINE", "Machine")) {
    [Environment]::SetEnvironmentVariable("CARGO_NET_OFFLINE", $null, "Machine")
    Write-Host "  CARGO_NET_OFFLINE supprimee."
} else {
    Write-Host "  rien a supprimer."
}

# ---------------------------------------------------------- 4. Build Tools
if ($RemoveBuildTools) {
    Write-Host "[4/5] Visual Studio Build Tools" -ForegroundColor Cyan
    if (Confirm-Step "Desinstaller les Build Tools ? D'autres logiciels peuvent en dependre") {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
        $setup   = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\setup.exe"
        if ((Test-Path $vswhere) -and (Test-Path $setup)) {
            $path = & $vswhere -products Microsoft.VisualStudio.Product.BuildTools -property installationPath | Select-Object -First 1
            if ($path) {
                $p = Start-Process $setup -PassThru `
                        -ArgumentList "uninstall --installPath `"$path`" --quiet --norestart"
                $p.WaitForExit()
                if ($p.ExitCode -notin 0, 3010) { Write-Warning "Code de sortie VS : $($p.ExitCode)" }
                else { Write-Host "  desinstalle." }
            } else { Write-Host "  Build Tools non trouves." }
        } else { Write-Host "  installeur Visual Studio introuvable." }
    }
} else {
    Write-Host "[4/5] Build Tools conserves (utilise -RemoveBuildTools pour les retirer)." -ForegroundColor Yellow
}

# ------------------------------------------------------------- 5. Donnees
Write-Host "[5/5] Donnees utilisateur / projet" -ForegroundColor Cyan
if ($RemoveCargoHome) {
    $cargoHome = Join-Path $env:USERPROFILE ".cargo"
    if ((Test-Path $cargoHome) -and (Confirm-Step "Supprimer $cargoHome ?")) {
        Remove-Item $cargoHome -Recurse -Force
        Write-Host "  $cargoHome supprime."
    }
}
if ($ProjectDest) {
    if ((Test-Path $ProjectDest) -and (Confirm-Step "Supprimer le projet $ProjectDest ? (irreversible)")) {
        Remove-Item $ProjectDest -Recurse -Force
        Write-Host "  $ProjectDest supprime."
    }
}
if (-not $RemoveCargoHome -and -not $ProjectDest) { Write-Host "  rien a supprimer (voir -RemoveCargoHome / -ProjectDest)." }

Write-Host "`nDesinstallation terminee. Ouvre un nouveau terminal pour rafraichir le PATH." -ForegroundColor Green
