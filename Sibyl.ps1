<#
.SYNOPSIS
    Sibyl - preserve memories. Il menu principale: da qui si apre il launcher o l'organizzatore.

.DESCRIPTION
    [1] Launcher       SibylLauncher.ps1: aspetta un disco, installa e avvia il gioco
    [2] Organizer      Organize-GogGames.ps1: prepara i download GOG, masterizza e verifica il disco
    [3] Opzioni        lingua, avvio automatico del launcher, comandi e opzioni di avvio
    Quando uno dei due si chiude si torna a questo menu.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Sibyl.Common.ps1')

trap { Write-Host ''; Write-Alert $_.Exception.Message; exit 1 }

$Description = 'Sibyl trasforma i tuoi giochi GOG senza DRM in dischi fisici, da usare come le cartucce di una vecchia console: inserisci il disco e il gioco parte. L''Organizer prepara, masterizza e verifica i dischi; il Launcher li riconosce, installa il gioco e lo avvia.'

function Wait-AnyKey([string]$What = 'torna al menu') {
    Write-Host ''
    Write-Keys "[un tasto qualsiasi] $What"
    try { [void][Console]::ReadKey($true) } catch { [void](Read-Host) }
}

# Testo tradotto e mandato a capo alla larghezza del menu
function Write-Paragraph([string]$Text, [int]$Width = 66) {
    $line = ''
    foreach ($word in (T $Text) -split ' ') {
        if ($line -and ($line.Length + 1 + $word.Length) -gt $Width) {
            Write-Host "    $line" -ForegroundColor $Theme.Muted
            $line = $word
        } else {
            $line = if ($line) { "$line $word" } else { $word }
        }
    }
    if ($line) { Write-Host "    $line" -ForegroundColor $Theme.Muted }
}

function Show-Menu {
    Clear-Host
    Write-Banner 'menu principale'
    Write-Box @(
        '*COSA VUOI FARE?'
        ''
        '  [1]  LAUNCHER        inserisci un disco e gioca'
        '  [2]  ORGANIZER       prepara, masterizza e verifica i dischi'
        '  [3]  OPZIONI         lingua, avvio automatico, comandi'
        ''
        '  [Q]  esci'
    )
    Write-Host ''
    Write-Paragraph $Description
    Write-Host ''
    Write-Keys 'Premi [1], [2], [3] oppure [Q]'
    Write-Host ''
    $version = (T 'versione {0}') -f $SibylVersion
    Write-Host ((' ' * (68 - $version.Length)) + $version) -ForegroundColor $Theme.Faint
}

function Show-LaunchOptions {
    Clear-Host
    Write-Banner 'comandi e opzioni di avvio'
    $row = { param($Command, $Text) '{0,-29}{1}' -f (T $Command), (T $Text) }
    Write-Box @(
        '*COME SI AVVIA'
        (& $row 'Sibyl.exe' 'menu principale')
        (& $row 'Sibyl.exe launcher' 'solo il launcher')
        (& $row 'Sibyl.exe organizer' 'solo l''organizer')
        (& $row 'Sibyl.exe <cartella>' 'organizer su quella cartella')
        ''
        '*OPZIONI DEL LAUNCHER'
        (& $row '-Autostart On | Off' 'parte con Windows, o non piu''')
        (& $row '-Drive <lettore|cartella>' 'controlla solo quel lettore')
        (& $row '-Library <cartella>' 'dove installare i giochi')
        (& $row '-Countdown <secondi>' 'attesa prima di giocare (15)')
        (& $row '-ShowInstaller' 'mostra l''installer di GOG')
        (& $row '-Once' 'esce dopo una partita')
        ''
        '*OPZIONI DELL''ORGANIZER'
        (& $row '<download> [libreria]' 'cartelle da usare')
        (& $row '-Select <numero>' 'sceglie il gioco senza menu')
        (& $row '-All' 'tutti, senza masterizzare')
        (& $row '-NoBurn' 'prepara senza masterizzare')
        (& $row '-Move' 'sposta invece di copiare')
        (& $row '-DryRun' 'mostra cosa farebbe')
        (& $row '-NoHash' 'salta gli SHA-256')
    )
    Write-Host ''
    Write-Info 'Esempio: Sibyl.exe launcher -Autostart On'
    Write-Info 'Senza l''exe valgono gli stessi comandi con SibylLauncher.bat e OrganizzaGOG.bat.'
    Wait-AnyKey 'torna alle opzioni'
}

function Show-Options {
    while ($true) {
        Clear-Host
        Write-Banner 'opzioni'
        $language = if ((Get-Language) -eq 'en') { 'English' } else { 'Italiano' }
        $autostart = if (Test-Autostart) { T 'attivo' } else { T 'non attivo' }
        Write-Box @(
            '*OPZIONI'
            ''
            ('  [L]  {0,-28}{1}' -f (T 'Lingua / Language'), $language)
            ('  [A]  {0,-28}{1}' -f (T 'Avvio automatico launcher'), $autostart)
            ('  [C]  {0}' -f (T 'Comandi e opzioni di avvio'))
            ''
            ('  [M]  {0}' -f (T 'torna al menu principale'))
        )
        Write-Host ''
        Write-Keys 'Premi [L], [A], [C] oppure [M]'
        $choice = Read-KeyChoice @('L', 'A', 'C', 'M', 'Q') 'M'
        if ($choice -eq 'L') { Set-Language $(if ((Get-Language) -eq 'en') { 'it' } else { 'en' }) }
        elseif ($choice -eq 'A') { Set-Autostart (-not (Test-Autostart)) }
        elseif ($choice -eq 'C') { Show-LaunchOptions }
        else { return }
    }
}

while ($true) {
    Show-Menu
    $choice = Read-KeyChoice @('1', '2', '3', 'Q') 'Q'
    if ($choice -eq 'Q') { break }
    if ($choice -eq '3') { Show-Options; continue }

    Clear-Host
    $global:LASTEXITCODE = 0
    if ($choice -eq '1') {
        & (Join-Path $PSScriptRoot 'SibylLauncher.ps1') -FromMenu
    } else {
        & (Join-Path $PSScriptRoot 'Organize-GogGames.ps1') -FromMenu
    }
    # [Q] chiude tutto, [M] torna subito al menu; a fine lavoro si lascia leggere il riepilogo
    if ($LASTEXITCODE -eq $ExitQuitAll) { break }
    if ($choice -eq '2' -and $LASTEXITCODE -ne $ExitToMenu) { Wait-AnyKey }
}

Clear-Host
Write-Banner
Write-Host ('                     ' + (T 'Grazie per aver usato Sibyl. A presto!')) -ForegroundColor $Theme.Title
Write-Host ''
