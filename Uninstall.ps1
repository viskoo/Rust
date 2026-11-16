# Désinstallation silencieuse de Zed (aucune fenêtre).
# Retrouve le désinstalleur Inno Setup via le registre (installation utilisateur ou machine).
# Journal : uninstall-zed.log, à côté du script.

$ErrorActionPreference = 'Stop'

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $dir 'uninstall-zed.log'

function Log($msg) { "$(Get-Date -Format s)  $msg" | Out-File -FilePath $log -Append -Encoding utf8 }

try {
    Log 'Début de la désinstallation de Zed'

    $keys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entries = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^Zed( |$)' -and $_.DisplayName -notmatch 'Preview' -and $_.UninstallString }

    if (-not $entries) { Log 'Zed n''est pas installé : rien à faire'; exit 0 }

    # Fermer Zed s'il est ouvert, sinon certains fichiers ne peuvent pas être supprimés.
    Get-Process -Name 'Zed', 'zed' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2

    foreach ($e in $entries) {
        # UninstallString ressemble à : "C:\...\Zed\unins000.exe"
        $exe = ($e.UninstallString -replace '^\s*"([^"]+)".*$', '$1').Trim()
        if (-not (Test-Path $exe)) { Log "Désinstalleur introuvable : $exe"; continue }

        Log "Désinstallation de $($e.DisplayName) $($e.DisplayVersion) via $exe"
        $p = Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' `
                           -WindowStyle Hidden -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Le désinstalleur a renvoyé le code $($p.ExitCode)" }
    }

    Log 'Zed désinstallé avec succès'
    exit 0
}
catch {
    Log "ERREUR : $($_.Exception.Message)"
    exit 1
}
