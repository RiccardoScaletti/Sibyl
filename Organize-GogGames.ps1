<#
.SYNOPSIS
    Sibyl :: Disc Prep - organizza i download GOG in una libreria standard, pronta da masterizzare.

.DESCRIPTION
    Analizza una cartella di download GOG (installer offline, file .bin, patch, extra, DLC),
    raggruppa i file per gioco e crea per ognuno una cartella standard:

        <Libreria>\<Titolo> (<versione>)\
            sibyl.json        manifest letto da Sibyl
            LEGGIMI.txt
            Installer\        setup_*.exe + setup_*.bin
            Patch\            patch_*.exe
            DLC\<nome>\       installer dei DLC (da una sottocartella "dlc")
            Extra\            manuali, colonne sonore, artwork...
            Other\            installer per Linux/macOS

    Il CONTENUTO di ogni cartella gioco va masterizzato nella radice del disco.
    Si puo' rilanciare quante volte si vuole: i file gia' presenti vengono saltati e le
    modifiche fatte a mano a title/mode/launch in sibyl.json vengono conservate (anche da un vecchio timerunner.json).

    Normalmente mostra i giochi trovati e ne fa scegliere uno: lo prepara, lo masterizza
    (rilevando il masterizzatore), verifica il disco e propone di avviarlo con Sibyl.

.PARAMETER Source
    Cartella in cui scarichi i giochi da GOG.
.PARAMETER Destination
    Cartella della libreria. Predefinita: <Source>\Sibyl-Library
.PARAMETER Select
    Numero del gioco da preparare (come nel menu): salta la scelta.
.PARAMETER All
    Prepara tutti i giochi senza menu e senza masterizzare.
.PARAMETER NoBurn
    Prepara il gioco scelto ma non lo masterizza.
.PARAMETER Move
    Sposta i file invece di copiarli.
.PARAMETER DryRun
    Mostra cosa farebbe senza toccare niente.
.PARAMETER NoHash
    Salta il calcolo degli SHA-256 (piu' veloce, ma Sibyl non potra' verificare il disco).

.EXAMPLE
    .\Organize-GogGames.ps1 D:\Download\GOG
.EXAMPLE
    .\Organize-GogGames.ps1 D:\Download\GOG -All -Move
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Source,
    [Parameter(Position = 1)][string]$Destination,
    [int]$Select,
    [switch]$All,
    [switch]$NoBurn,
    [switch]$Move,
    [switch]$DryRun,
    [switch]$NoHash,
    [switch]$FromMenu   # aperto dal menu di Sibyl: [M] ci torna invece di riaprirlo
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Sibyl.Common.ps1')
. (Join-Path $PSScriptRoot 'Sibyl.Burn.ps1')

# Errori imprevisti: messaggio nello stile di Sibyl invece dell'errore PowerShell grezzo
trap { Write-Host ''; Write-Alert $_.Exception.Message; exit 1 }

$ManifestVersion = 1

# Capacita' reali dei supporti, dalla piu' piccola alla piu' grande
$Media = @(
    @{ Name = 'DVD-R 4.7 GB';     Bytes = 4700372992 },
    @{ Name = 'DVD-R DL 8.5 GB';  Bytes = 8543666176 },
    @{ Name = 'BD-R 25 GB';       Bytes = 25025314816 },
    @{ Name = 'BD-R DL 50 GB';    Bytes = 50050629632 },
    @{ Name = 'BDXL 100 GB';      Bytes = 100103356416 },
    @{ Name = 'BDXL QL 128 GB';   Bytes = 128001769472 }
)
$MediaMargin = 0.99   # spazio lasciato al file system UDF

$PartialExtensions = '.part', '.crdownload', '.tmp', '.download', '.partial'
$OtherPlatformExtensions = '.sh', '.pkg', '.dmg', '.deb', '.rpm'

# ---------------------------------------------------------------- parsing nomi GOG

function ConvertTo-Title([string]$Slug) {
    $words = (Get-Culture).TextInfo.ToTitleCase(($Slug -replace '_', ' ')) -split ' '
    $words = $words | ForEach-Object {
        if ($_ -match '^(i|ii|iii|iv|v|vi|vii|viii|ix|x|xi|xii)$') { $_.ToUpper() } else { $_ }
    }
    return ($words -join ' ')
}

# setup_the_witcher_3_wild_hunt_4.04_a_(64bit)_(50253)-1.bin
#   -> Kind=Installer  Slug=the_witcher_3_wild_hunt  Version=4.04_a_64bit  Build=50253
function Get-GogFileInfo([IO.FileInfo]$File) {
    $base = [IO.Path]::GetFileNameWithoutExtension($File.Name).ToLower()
    $ext = $File.Extension.ToLower()
    if ($ext -notin '.exe', '.bin') { return $null }
    if ($base -like 'setup_*') { $kind = 'Installer' }
    elseif ($base -like 'patch_*') { $kind = 'Patch' }
    else { return $null }

    $base = $base.Substring(6) -replace '-\d+$', ''    # "-1", "-2" dei file .bin
    $build = ''
    if ($base -match '_\((\d+)\)$') {
        $build = $Matches[1]
        $base = $base -replace '_\(\d+\)$', ''
    }

    # Lo slug finisce al primo token che sembra una versione puntata (1.0, v2.3.1, 4.04a)
    $tokens = @($base -split '_')
    $cut = $tokens.Count
    for ($i = 1; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -match '^v?\d+(\.\d+)+') { $cut = $i; break }
    }
    $version = ''
    if ($cut -lt $tokens.Count) {
        $version = ($tokens[$cut..($tokens.Count - 1)] -join '_') -replace '[()]', '' -replace '_?(32|64)bit', ''
    }
    [pscustomobject]@{
        Kind    = $kind
        Slug    = $tokens[0..($cut - 1)] -join '_'
        Version = $version
        Build   = $build
    }
}

function Get-SuggestedMedia([long]$Bytes) {
    foreach ($m in $Media) {
        if ($Bytes -le $m.Bytes * $MediaMargin) { return $m.Name }
    }
    $largest = $Media[-1]
    $discs = [math]::Ceiling($Bytes / ($largest.Bytes * $MediaMargin))
    return "$discs x $($largest.Name) (multi-disco)"
}

# ---------------------------------------------------------------- abbinamento file -> gioco

function Find-Game($Entry) {
    $all = @($script:games.Values)

    # 1) stessa sottocartella di un installer (struttura di lgogdownloader)
    if ($Entry.TopDir) {
        $byDir = @($all | Where-Object { $_.TopDirs -contains $Entry.TopDir })
        if ($byDir.Count) { return $byDir | Sort-Object Newest -Descending | Select-Object -First 1 }
    }

    # 2) il nome del file inizia con lo slug del gioco (patch_<slug>_..., <slug>_manual.zip)
    $probe = [IO.Path]::GetFileNameWithoutExtension($Entry.File.Name).ToLower() -replace '^(setup|patch)_', ''
    $bySlug = @($all | Where-Object { $probe -eq $_.Slug -or $probe.StartsWith($_.Slug + '_') })
    if ($bySlug.Count) {
        return $bySlug | Sort-Object @{ e = { $_.Slug.Length }; Descending = $true }, @{ e = 'Newest'; Descending = $true } |
            Select-Object -First 1
    }

    # 3) c'e' un solo gioco nella cartella: tutto il resto e' suo
    if ($all.Count -eq 1) { return $all[0] }
    return $null
}

function Get-Category($Entry) {
    if ($Entry.InDlc -and $Entry.Info -and $Entry.Info.Kind -eq 'Installer') { return 'DLC' }
    if ($Entry.Info -and $Entry.Info.Kind -eq 'Patch') { return 'Patch' }
    if ($Entry.File.Extension.ToLower() -in $OtherPlatformExtensions) { return 'Other' }
    return 'Extra'
}

function Add-ToGame($Game, $Entry, [string]$Category) {
    $target = if ($Category -eq 'DLC' -and $Entry.DlcName) {
        Join-Path (Join-Path 'DLC' $Entry.DlcName) $Entry.File.Name
    } else {
        Join-Path $Category $Entry.File.Name
    }
    # Due extra con lo stesso nome da cartelle diverse: prefisso con la cartella d'origine
    if ($Game.Targets -contains $target) {
        $parent = Split-Path -Leaf (Split-Path $Entry.File.FullName)
        $target = Join-Path $Category ("{0}_{1}" -f $parent, $Entry.File.Name)
    }
    $Game.Targets += $target
    $Entry.Game = $Game
    $Entry.Category = $Category
    $Entry.Target = $target
    $Game.Entries.Add($Entry)
}

# ---------------------------------------------------------------- file system

function Copy-GameFile([string]$From, [string]$To) {
    [void][IO.Directory]::CreateDirectory((Split-Path $To))
    if (Test-Path -LiteralPath $To) {
        if ((Get-Item -LiteralPath $To).Length -eq (Get-Item -LiteralPath $From).Length) { return 'skip' }
        throw "Esiste gia' un file diverso con lo stesso nome: $To"
    }
    if ($Move) { Move-Item -LiteralPath $From -Destination $To }
    else { Copy-Item -LiteralPath $From -Destination $To }
    return 'done'
}

function Test-BinSequence($Game) {
    $numbers = @($Game.Entries | Where-Object { $_.Category -eq 'Installer' -and $_.File.Name -match '-(\d+)\.bin$' } |
        ForEach-Object { [int]($_.File.Name -replace '^.*-(\d+)\.bin$', '$1') } | Sort-Object)
    if (-not $numbers.Count) { return @() }
    return @(1..$numbers[-1] | Where-Object { $numbers -notcontains $_ })
}

# ---------------------------------------------------------------- interazione

# Chiede una cartella finche' non ne viene data una esistente
function Read-Folder([string]$Prompt) {
    while ($true) {
        $path = Read-Text $Prompt
        if ($path -and (Test-Path -LiteralPath $path -PathType Container)) { return (Resolve-Path -LiteralPath $path).ProviderPath }
        Write-Alert "Cartella non trovata: $path"
    }
}

# Restituisce il numero del gioco (1..N), 'all' oppure $null per uscire
function Show-GameMenu($List) {
    Write-Host ''
    Write-Box @('*GIOCHI TROVATI')
    for ($i = 0; $i -lt $List.Count; $i++) {
        $g = $List[$i]
        $name = $g.FolderName
        if ($name.Length -gt 32) { $name = $name.Substring(0, 29) + '...' }
        $mark = if (Test-Path -LiteralPath (Get-ManifestPath $g.Folder)) { 'in libreria' } else { '' }
        Write-Host ('   [{0,2}]  ' -f ($i + 1)) -ForegroundColor $Theme.Accent -NoNewline
        Write-Host ('{0,-32} ' -f $name) -ForegroundColor $Theme.Text -NoNewline
        Write-Host ('{0,10}  {1,-15} ' -f (Format-Size $g.TotalBytes), $g.MediaName) -ForegroundColor $Theme.Muted -NoNewline
        Write-Host $mark -ForegroundColor $Theme.Title
    }
    Write-Host ''
    Write-Keys ' [ T]  prepara tutti (senza masterizzare)'
    Write-Keys ' [ D]  disinstalla un gioco installato'
    Write-Keys ' [ M]  menu principale'
    Write-Keys ' [ Q]  esci'
    Write-Host ''
    while ($true) {
        $answer = Read-Answer 'Scegli il gioco'
        if ($answer -eq 'Q') { return $null }
        if ($answer -eq 'M') { return 'menu' }
        if ($answer -eq 'D') { return 'uninstall' }
        if ($answer -eq 'T') { return 'all' }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $List.Count) { return $n }
        Write-Alert "Scrivi un numero da 1 a $($List.Count), T, D, M oppure Q"
    }
}

# [D]: elenco dei giochi installati dal launcher, scelta e disinstallazione
function Invoke-UninstallMenu {
    $library = Get-LibraryPath
    $installed = @(Get-InstalledGames $library | Sort-Object Title)
    Write-Host ''
    if (-not $installed.Count) { Write-Info "Nessun gioco installato in $library"; return }
    Write-Box @('*GIOCHI INSTALLATI')
    for ($i = 0; $i -lt $installed.Count; $i++) {
        Write-Host ('   [{0,2}]  ' -f ($i + 1)) -ForegroundColor $Theme.Accent -NoNewline
        Write-Host ('{0,-40} ' -f $installed[$i].Title) -ForegroundColor $Theme.Text -NoNewline
        Write-Host $installed[$i].Version -ForegroundColor $Theme.Muted
    }
    Write-Host ''
    while ($true) {
        $answer = Read-Answer 'Quale gioco disinstallare? (numero, INVIO per annullare)'
        if (-not $answer) { return }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $installed.Count) { break }
        Write-Alert "Scrivi un numero da 1 a $($installed.Count)"
    }
    $game = $installed[$n - 1]
    Write-Host ''
    [void](Invoke-UninstallScreen $game.Title $game.Home $game.State $library)
}

function Select-Burner {
    while ($true) {
        $burners = @(Get-Burners | Where-Object { $_.Root -and $_.CanWrite })
        if ($burners.Count -eq 1) {
            Write-Info "Masterizzatore: $($burners[0].Root)  $($burners[0].Name)"
            return $burners[0]
        }
        if ($burners.Count -gt 1) {
            for ($i = 0; $i -lt $burners.Count; $i++) { Write-Info ('[{0}] {1}  {2}' -f ($i + 1), $burners[$i].Root, $burners[$i].Name) }
            $answer = Read-Answer 'Quale masterizzatore? (numero, Q per saltare)'
            if ($answer -eq 'Q') { return $null }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $burners.Count) { return $burners[$n - 1] }
            continue
        }

        Write-Alert 'Nessun masterizzatore rilevato.'
        $answer = Read-Answer "Lettera dell'unita' (es. E), INVIO per cercare di nuovo, Q per saltare"
        if ($answer -eq 'Q') { return $null }
        if ($answer -match '^([A-Z]):?\\?$') {
            $letter = $Matches[1]
            $match = @(Get-Burners | Where-Object { $_.Root -like "$($letter):*" })
            if ($match.Count -and $match[0].CanWrite) { return $match[0] }
            if ($match.Count) { Write-Alert "$($letter): e' un lettore, ma non puo' scrivere dischi" }
            else { Write-Alert "$($letter): non risulta un'unita' ottica (il lettore USB e' collegato?)" }
        }
    }
}

# Masterizza la cartella del gioco e verifica il disco. Restituisce la radice del disco, o $null.
function Invoke-BurnFlow($Game) {
    $manifest = Read-Manifest (Get-ManifestPath $Game.Folder)
    Write-Host ''
    Write-Step "Masterizzazione di $($manifest.title)"
    $burner = Select-Burner
    if (-not $burner) { Write-Info 'Masterizzazione saltata.'; return $null }

    $erase = $false
    while ($true) {
        $media = Get-MediaState $burner
        $problem = switch ($media.State) {
            'empty'       { "Nessun disco in $($burner.Root)" }
            'unsupported' { "Il disco in $($burner.Root) ($($media.Name)) non e' scrivibile" }
            'used'        { "Il disco $($media.Name) in $($burner.Root) contiene gia' dati e non e' riscrivibile" }
            default       { $null }
        }
        if (-not $problem -and $Game.TotalBytes -gt $media.Capacity * $MediaMargin) {
            $problem = "Il gioco ($(Format-Size $Game.TotalBytes)) non entra in un $($media.Name) ($(Format-Size $media.Capacity)): serve $($Game.MediaName)"
        }
        if (-not $problem -and $media.State -eq 'erasable') {
            Write-Alert "Il disco $($media.Name) in $($burner.Root) contiene gia' dati."
            if (Test-Yes (Read-Answer 'Cancellarlo e riscriverlo? [S/N]')) { $erase = $true; break }
            $problem = 'Disco da cambiare'
        }
        if (-not $problem) { break }
        Write-Alert $problem
        if ((Read-Answer "Inserisci un disco vuoto in $($burner.Root) e premi INVIO (Q per saltare)") -eq 'Q') {
            Write-Info 'Masterizzazione saltata.'
            return $null
        }
        Start-Sleep -Seconds 2   # il lettore impiega un attimo a leggere il disco appena inserito
    }

    $label = Get-VolumeLabel $manifest.title
    Write-Host ''
    Write-Info "Gioco     : $($manifest.title)  ($(Format-Size $Game.TotalBytes))"
    Write-Info "Disco     : $($media.Name) in $($burner.Root)  [$($burner.Name)]"
    Write-Info "Etichetta : $label"
    if ($erase) { Write-Alert "Il contenuto attuale del disco verra' cancellato." }
    if (-not (Test-Yes (Read-Answer 'Avvio la masterizzazione? [S/N]'))) { Write-Info 'Masterizzazione annullata.'; return $null }

    try { Invoke-Burn $burner $Game.Folder $label $erase }
    catch { Write-Alert "Masterizzazione fallita: $($_.Exception.Message)"; return $null }
    Write-Ok 'Scrittura completata'

    # Dopo la chiusura del disco Windows impiega qualche secondo a rileggerlo
    $root = $burner.Root
    $deadline = (Get-Date).AddSeconds(60)
    $i = 0
    while (-not (Test-Path -LiteralPath (Join-Path $root $ManifestName))) {
        if ((Get-Date) -gt $deadline) {
            Write-Host ''
            if ((Read-Answer "Windows non vede ancora il disco: estrailo, reinseriscilo e premi INVIO (Q salta la verifica)") -eq 'Q') {
                return $root
            }
            $deadline = (Get-Date).AddSeconds(60)
        }
        Write-Status ('[{0}] Attendo che Windows rilegga il disco...' -f $Spinner[$i++ % 4])
        Start-Sleep -Seconds 1
    }
    # Appena visibile il disco puo' essere rimontato ancora una volta: qualche secondo di calma
    # prima di leggere, altrimenti la verifica rischia di essere interrotta a meta' file
    $until = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $until) {
        Write-Status ('[{0}] Attendo che il lettore si stabilizzi...' -f $Spinner[$i++ % 4])
        Start-Sleep -Milliseconds 250
    }
    Write-Host ''

    while ($true) {
        $problems = @(Test-DiscWithProgress $root $manifest)
        if (-not $problems.Count) { break }
        Write-Alert "Verifica fallita, $($problems.Count) file con problemi:"
        $problems | ForEach-Object { Write-Info $_ }
        if ((Read-Answer '[V] verifica di nuovo   [INVIO] continua senza disco verificato') -ne 'V') {
            Write-Info 'Se la verifica continua a fallire sullo stesso file, meglio rimasterizzare il disco.'
            return $null
        }
        Write-Host ''
    }
    Write-Ok "Disco verificato: $(@($manifest.files).Count) file integri"
    return $root
}

# ================================================================ MAIN

Write-Banner 'disc prep :: libreria GOG' 'Organizer'

# ---- cartelle: quelle passate, quelle dell'ultima volta oppure nuove
if ($Source) {
    $Source = $Source.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Alert "Cartella non trovata: $Source"
        exit 1
    }
    $Source = (Resolve-Path -LiteralPath $Source).ProviderPath
} else {
    $config = Read-Config
    $lastSource = Get-Prop $config 'source'
    $lastDestination = Get-Prop $config 'destination'
    if ($lastSource -and (Test-Path -LiteralPath $lastSource -PathType Container)) {
        Write-Box @(
            '*CARTELLE DELL''ULTIMA VOLTA'
            "Download : $lastSource"
            "Libreria : $(if ($lastDestination) { $lastDestination } else { Join-Path $lastSource 'Sibyl-Library' })"
        )
        Write-Host ''
        $answer = Read-Answer '[INVIO] usa queste   [C] cambia   [M] menu principale'
        if ($answer -eq 'M') { Exit-ToMenu $FromMenu }
        if ($answer -eq 'C') {
            $Source = Read-Folder 'Cartella dei download GOG (puoi trascinarla qui)'
            $Destination = Read-Text "Cartella della libreria   [INVIO] = $(Join-Path $Source 'Sibyl-Library')"
        } else {
            $Source = $lastSource
            if (-not $Destination) { $Destination = $lastDestination }
        }
    } else {
        $Source = Read-Folder 'Cartella dei download GOG (puoi trascinarla qui)'
    }
    Write-Host ''
}
$sourcePrefix = $Source.TrimEnd('\') + '\'
if (-not $Destination) { $Destination = Join-Path $Source 'Sibyl-Library' }
$Destination = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$destPrefix = $Destination + '\'
if (-not $DryRun) {
    Set-ConfigValue 'source' $Source
    Set-ConfigValue 'destination' $Destination
}

Write-Info "Sorgente : $Source"
Write-Info "Libreria : $Destination"
Write-Info ("Modalita': {0}{1}" -f $(if ($Move) { 'SPOSTA' } else { 'COPIA' }), $(if ($DryRun) { '  [prova, nessuna modifica]' } else { '' }))
Write-Host ''

# ---- scansione
Write-Step 'Scansione dei file...'
$partial = New-Object System.Collections.Generic.List[string]
$entries = @(foreach ($f in Get-ChildItem -LiteralPath $Source -File -Recurse) {
    if ($f.FullName.StartsWith($destPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
    $rel = $f.FullName.Substring($sourcePrefix.Length)
    if ($f.Extension.ToLower() -in $PartialExtensions) { $partial.Add($rel); continue }

    $parts = $rel.Split('\')
    $dlcName = $null
    $inDlc = $false
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if ($parts[$i] -eq 'dlc') {
            $inDlc = $true
            if ($i + 2 -lt $parts.Count) { $dlcName = $parts[$i + 1] }
            break
        }
    }
    [pscustomobject]@{
        File     = $f
        Rel      = $rel
        TopDir   = $(if ($parts.Count -gt 1) { $parts[0] } else { $null })
        InDlc    = $inDlc
        DlcName  = $dlcName
        Info     = Get-GogFileInfo $f
        Game     = $null
        Category = $null
        Target   = $null
    }
})
Write-Info "$($entries.Count) file trovati"

# ---- giochi = installer principali (setup_*.exe/.bin fuori da una cartella dlc)
$games = [ordered]@{}
foreach ($e in $entries | Where-Object { $_.Info -and $_.Info.Kind -eq 'Installer' -and -not $_.InDlc }) {
    $key = "$($e.Info.Slug)|$($e.Info.Version)"
    if (-not $games.Contains($key)) {
        $games[$key] = [pscustomobject]@{
            Slug    = $e.Info.Slug
            Version = $e.Info.Version
            Build   = $e.Info.Build
            Title   = ConvertTo-Title $e.Info.Slug
            TopDirs = @()
            Targets = @()
            Entries = New-Object System.Collections.Generic.List[object]
            Newest  = [datetime]::MinValue
            FolderName = ''
            Folder     = ''
            TotalBytes = 0L
            MediaName  = ''
        }
    }
    $g = $games[$key]
    if ($e.TopDir -and $g.TopDirs -notcontains $e.TopDir) { $g.TopDirs += $e.TopDir }
    if ($e.File.LastWriteTime -gt $g.Newest) { $g.Newest = $e.File.LastWriteTime }
    if (-not $g.Build -and $e.Info.Build) { $g.Build = $e.Info.Build }
    Add-ToGame $g $e 'Installer'
}

if (-not $games.Count) {
    Write-Alert 'Nessun installer GOG (setup_*.exe) trovato. Niente da fare.'
    exit 1
}

# ---- tutto il resto: patch, DLC, extra
$unmatched = New-Object System.Collections.Generic.List[string]
foreach ($e in $entries | Where-Object { -not $_.Game }) {
    $g = Find-Game $e
    if ($g) { Add-ToGame $g $e (Get-Category $e) } else { $unmatched.Add($e.Rel) }
}

Write-Ok "$($games.Count) giochi riconosciuti"

$gameList = @($games.Values)
foreach ($g in $gameList) {
    $g.FolderName = Get-SafeName $(if ($g.Version) { "$($g.Title) ($($g.Version))" } else { $g.Title })
    $g.Folder = Join-Path $Destination $g.FolderName
    $g.TotalBytes = [long]($g.Entries | ForEach-Object { $_.File.Length } | Measure-Object -Sum).Sum
    $g.MediaName = Get-SuggestedMedia $g.TotalBytes
}

# ---- scelta del gioco
$burn = -not ($DryRun -or $All -or $NoBurn)
if ($DryRun -or $All) {
    $selected = $gameList
} else {
    if ($Select) {
        $choice = $Select
    } else {
        while ($true) {
            $choice = Show-GameMenu $gameList
            if ("$choice" -ne 'uninstall') { break }
            Invoke-UninstallMenu
        }
    }
    if (-not $choice) { Exit-QuitAll $FromMenu }
    if ("$choice" -eq 'menu') { Exit-ToMenu $FromMenu }
    if ("$choice" -eq 'all') {
        $selected = $gameList
        $burn = $false
    } elseif ($choice -lt 1 -or $choice -gt $gameList.Count) {
        Write-Alert "Gioco numero $choice inesistente: ce ne sono $($gameList.Count)"
        exit 1
    } else {
        $selected = @($gameList[$choice - 1])
    }
}

# ---- elaborazione per gioco
$summary = New-Object System.Collections.Generic.List[object]
foreach ($g in $selected) {
    $folderName = $g.FolderName
    $folder = $g.Folder
    $totalBytes = $g.TotalBytes
    $mediaName = $g.MediaName

    Write-Host ''
    Write-Host '  +--[ ' -ForegroundColor $Theme.Frame -NoNewline
    Write-Host $g.Title -ForegroundColor $Theme.Accent -NoNewline
    Write-Host ' ]' -ForegroundColor $Theme.Frame
    Write-Info "| versione $(if ($g.Version) { $g.Version } else { '?' })   build $(if ($g.Build) { $g.Build } else { '?' })"
    Write-Info "| $($g.Entries.Count) file, $(Format-Size $totalBytes)  ->  $mediaName"
    Write-Info "| cartella: $folderName"

    $exes = @($g.Entries | Where-Object { $_.Category -eq 'Installer' -and $_.File.Extension -ieq '.exe' } | Sort-Object { $_.File.Name })
    if (-not $exes.Count) { Write-Alert "Manca il setup .exe: il download sembra incompleto" }
    $missingBins = @(Test-BinSequence $g)
    if ($missingBins.Count) { Write-Alert ("Mancano i file .bin numero: {0}" -f ($missingBins -join ', ')) }

    if ($DryRun) {
        foreach ($e in $g.Entries | Sort-Object Target) { Write-Info "|   $($e.Rel)  ->  $($e.Target)" }
        continue
    }

    $manifestPath = Join-Path $folder $ManifestName
    $oldPath = Get-ManifestPath $folder   # anche il timerunner.json di una cartella preparata con TimeRunner
    $old = Read-Manifest $oldPath
    if (-not $old -and (Test-Path -LiteralPath $oldPath)) { Write-Alert "Manifest illeggibile, verra' rigenerato: $oldPath" }
    $oldHashes = @{}
    if ($old -and $old.PSObject.Properties['files']) {
        foreach ($of in $old.files) { $oldHashes[$of.path] = $of }
    }

    $fileRecords = New-Object System.Collections.Generic.List[object]
    foreach ($e in $g.Entries | Sort-Object Target) {
        $dst = Join-Path $folder $e.Target
        $result = Copy-GameFile $e.File.FullName $dst
        $verb = if ($result -eq 'skip') { 'gia'' presente' } elseif ($Move) { 'spostato' } else { 'copiato' }
        Write-Info "|   [$verb] $($e.Target)"

        $manifestPathKey = $e.Target -replace '\\', '/'
        $sha = ''
        if (-not $NoHash) {
            $prev = $oldHashes[$manifestPathKey]
            if ($result -eq 'skip' -and $prev -and $prev.size -eq $e.File.Length -and $prev.sha256) {
                $sha = $prev.sha256
            } else {
                Write-Host "     |   sha256 $($e.File.Name)..." -ForegroundColor $Theme.Faint
                $sha = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
            }
        }
        $fileRecords.Add([ordered]@{ path = $manifestPathKey; category = $e.Category; size = $e.File.Length; sha256 = $sha })
    }

    # Valori modificabili a mano: se c'e' gia' un manifest, si tengono quelli
    $title = $g.Title
    $mode = 'install'
    $launch = [ordered]@{ exe = ''; args = ''; workingDir = '' }
    if ($old) {
        if ($old.PSObject.Properties['title'] -and $old.title) { $title = $old.title }
        if ($old.PSObject.Properties['mode'] -and $old.mode) { $mode = $old.mode }
        if ($old.PSObject.Properties['launch'] -and $old.launch) { $launch = $old.launch }
    }

    $manifest = [ordered]@{
        sibyl          = $ManifestVersion
        id             = $g.Slug
        title          = $title
        version        = $g.Version
        build          = $g.Build
        store          = 'gog'
        platform       = 'windows'
        mode           = $mode            # install = installa dal disco | portable = avvia da Game\
        installer      = $(if ($exes.Count) { $exes[0].Target -replace '\\', '/' } else { '' })
        launch         = $launch          # vuoto = Sibyl lo ricava dal goggame-*.info dopo l'installazione
        sizeBytes      = $totalBytes
        suggestedMedia = $mediaName
        prepared       = (Get-Date).ToString('s')
        files          = $fileRecords.ToArray()
    }
    Write-TextFile $manifestPath ($manifest | ConvertTo-Json -Depth 6)
    # Un solo manifest per cartella: il vecchio timerunner.json, ormai copiato in sibyl.json, si toglie
    Remove-Item -LiteralPath (Join-Path $folder $LegacyManifestName) -ErrorAction SilentlyContinue

    $lines = @(
        '+==================================================================+'
        '|   S I B Y L    ::    D I S C O   G I O C O                       |'
        '+==================================================================+'
        ''
        "  Titolo     : $title"
        "  Versione   : $($g.Version)"
        "  Build      : $($g.Build)"
        "  Dimensione : $(Format-Size $totalBytes)"
        "  Supporto   : $mediaName"
        "  Preparato  : $((Get-Date).ToString('yyyy-MM-dd'))"
        ''
        '  COME SI USA'
        '  - Con Sibyl: inserisci il disco, il gioco viene riconosciuto'
        "    da $ManifestName e avviato."
        '  - Senza Sibyl: apri la cartella Installer ed esegui'
        "    $(if ($exes.Count) { $exes[0].File.Name } else { 'il setup .exe' })"
        '    (i file .bin devono restare nella stessa cartella dell''exe).'
        ''
        '  CONTENUTO'
    )
    $lines += $fileRecords | ForEach-Object { '    {0,-52} {1,10}' -f $_.path, (Format-Size $_.size) }
    Write-TextFile (Join-Path $folder 'LEGGIMI.txt') (($lines -join "`r`n") + "`r`n")

    Write-Ok "$title pronto"
    $summary.Add($folderName)
}

# ---- catalogo dell'intera libreria (anche dei giochi organizzati in passato)
if (-not $DryRun -and (Test-Path -LiteralPath $Destination)) {
    $rows = foreach ($dir in Get-ChildItem -LiteralPath $Destination -Directory) {
        $m = Read-Manifest (Get-ManifestPath $dir.FullName)
        if (-not $m) { continue }
        [pscustomobject]@{
            Titolo         = $m.title
            Versione       = $m.version
            Build          = $m.build
            'Dimensione GB' = [math]::Round($m.sizeBytes / 1GB, 2)
            Supporto       = $m.suggestedMedia
            Cartella       = $dir.Name
            Preparato      = $m.prepared
        }
    }
    $catalog = Join-Path $Destination 'catalogo.csv'
    @($rows) | Sort-Object Titolo | Export-Csv -LiteralPath $catalog -Delimiter ';' -Encoding UTF8 -NoTypeInformation
    Write-Host ''
    Write-Ok "Catalogo aggiornato: $catalog"
}

# ---- riepilogo
Write-Host ''
if ($partial.Count) {
    Write-Alert 'Download non completati, ignorati:'
    $partial | ForEach-Object { Write-Info "- $_" }
}
if ($unmatched.Count) {
    Write-Alert 'File non abbinati a nessun gioco (lasciati dove sono):'
    $unmatched | ForEach-Object { Write-Info "- $_" }
}
if (-not $burn) {
    Write-Host ''
    if ($DryRun) {
        Write-Box @('*PROVA COMPLETATA', 'Rilancia senza -DryRun per applicare')
    } else {
        Write-Box @(
            "*$($summary.Count) GIOCHI PRONTI DA MASTERIZZARE"
            'Masterizza il CONTENUTO di ogni cartella nella radice del disco'
            '(file system UDF, verifica dopo la scrittura attiva)'
        )
    }
    Write-Host ''
}

# ---- masterizzazione e avvio
if ($DryRun -or $selected.Count -ne 1) { exit 0 }
$game = $selected[0]
$discRoot = if ($burn) { Invoke-BurnFlow $game } else { $null }

Write-Host ''
if ($discRoot) {
    $answer = Read-Answer '[G] gioca ora   [M] menu principale   [Q] esci'
    $playFrom = $discRoot
} else {
    $answer = Read-Answer '[G] gioca ora dalla libreria (senza disco)   [M] menu principale   [Q] esci'
    $playFrom = $game.Folder
}
if ($answer -eq 'M') { Exit-ToMenu $FromMenu }
if ($answer -eq 'Q') { Exit-QuitAll $FromMenu }
if ($answer -eq 'G') {
    # Il launcher torna qui con [M] o [Q], e la scelta si passa a chi ha aperto l'organizzatore
    & (Join-Path $PSScriptRoot 'SibylLauncher.ps1') -Drive $playFrom -Countdown 0 -FromMenu
    if ($LASTEXITCODE -eq $ExitToMenu) { Exit-ToMenu $FromMenu }
    if ($LASTEXITCODE -eq $ExitQuitAll) { Exit-QuitAll $FromMenu }
}
