# Installation silencieuse de Zed (aucune fenêtre).
# Utilise Zed-x86_64.exe placé à côté de ce script ; le télécharge s'il est absent.
# Journal : install-zed.log (script) et zed-setup.log (installeur Inno Setup), à côté du script.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$dir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $dir 'Zed-x86_64.exe'
$url       = 'https://github.com/zed-industries/zed/releases/download/v1.28.1/Zed-x86_64.exe'
$log       = Join-Path $dir 'install-zed.log'
$setupLog  = Join-Path $dir 'zed-setup.log'

function Log($msg) { "$(Get-Date -Format s)  $msg" | Out-File -FilePath $log -Append -Encoding utf8 }

try {
    Log 'Début de l''installation de Zed'

    if (-not (Test-Path $installer)) {
        Log "Installeur absent, téléchargement depuis $url"
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    }

    $sig = Get-AuthenticodeSignature $installer
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Zed Industries') {
        throw "Signature invalide ($($sig.Status)) : installation annulée"
    }
    Log 'Signature Zed Industries valide'

    # Options Inno Setup : aucune interface, aucun message, pas de redémarrage.
    $setupArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
                   '/CLOSEAPPLICATIONS', "/LOG=`"$setupLog`"")

    $p = Start-Process -FilePath $installer -ArgumentList $setupArgs -WindowStyle Hidden -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "L'installeur a renvoyé le code $($p.ExitCode)" }

    Log 'Zed installé avec succès'
    exit 0
}
catch {
    Log "ERREUR : $($_.Exception.Message)"
    exit 1
}
