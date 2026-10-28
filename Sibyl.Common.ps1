# Sibyl :: funzioni condivise tra il menu (Sibyl.ps1), Disc Prep (Organize-GogGames.ps1)
# e il launcher (SibylLauncher.ps1)

# Versione di Sibyl: compare nel menu principale e nelle proprieta' di Sibyl.exe (Build-SibylExe.ps1)
$SibylVersion = '1.2.2'

$ManifestName = 'sibyl.json'
$LegacyManifestName = 'timerunner.json'   # dischi preparati quando il programma si chiamava TimeRunner
$ConfigPath = Join-Path $env:APPDATA 'Sibyl\config.json'
$LegacyConfigPath = Join-Path $env:APPDATA 'TimeRunner\config.json'

# Manifest di un disco o di una cartella della libreria: sibyl.json, oppure il vecchio timerunner.json.
# Se non c'e' nessuno dei due restituisce il percorso di sibyl.json (quello da creare).
function Get-ManifestPath([string]$Root) {
    $path = Join-Path $Root $ManifestName
    $legacy = Join-Path $Root $LegacyManifestName
    if (-not (Test-Path -LiteralPath $path) -and (Test-Path -LiteralPath $legacy)) { return $legacy }
    return $path
}

# Palette: azzurro per struttura, titoli e testi, viola per motti, accenti e tasti
$Theme = @{
    Title  = 'Cyan'
    Frame  = 'DarkCyan'
    Accent = 'Magenta'
    Soft   = 'DarkMagenta'
    Text   = 'White'
    Muted  = 'Gray'
    Faint  = 'DarkGray'
    Warn   = 'Yellow'
}

$Spinner = '|', '/', '-', '\'
$BarFull = [string][char]0x2588    # caratteri a blocchi, costruiti qui per non dipendere dalla codifica del file
$BarEmpty = [string][char]0x2591

# ---------------------------------------------------------------- lingua

# Le scritte nel codice sono in italiano; in inglese passano dal dizionario di Sibyl.Lang.ps1.
# Le funzioni di output (Write-Info, Write-Box, Write-Keys, ...) traducono da sole: basta passare
# loro il testo italiano. I testi composti si traducono con i modelli {0}, {1} del dizionario.
. (Join-Path $PSScriptRoot 'Sibyl.Lang.ps1')
$UiLanguage = $null
$TextExact = $null
$TextRules = $null

function Get-Language {
    if (-not $script:UiLanguage) {
        $script:UiLanguage = if ((Get-Prop (Read-Config) 'language') -eq 'en') { 'en' } else { 'it' }
    }
    return $script:UiLanguage
}

function Set-Language([string]$Language) {
    $script:UiLanguage = $Language
    Set-ConfigValue 'language' $Language
}

function Initialize-Translations {
    $script:TextExact = @{}   # senza distinzione di maiuscole: una voce vale per "OPZIONI" e "opzioni"
    $rules = foreach ($key in $TranslationsEn.Keys) {
        if ($key -notmatch '\{\d\}') { $script:TextExact[$key] = @{ Key = $key; English = $TranslationsEn[$key] }; continue }
        $pattern = '^' + ([regex]::Escape($key) -replace '\\\{(\d)\}', '(.*?)') + '$'
        [pscustomobject]@{ Regex = (New-Object regex $pattern, 'Singleline'); English = $TranslationsEn[$key]; Length = $key.Length }
    }
    $script:TextRules = @($rules | Sort-Object Length -Descending)
}

function T([string]$Text) {
    if (-not $Text -or (Get-Language) -ne 'en') { return $Text }
    if ($null -eq $script:TextRules) { Initialize-Translations }
    $m = [regex]::Match($Text, '^(\s*)(.*?)(\s*)$', 'Singleline')
    $core = $m.Groups[2].Value
    $out = $null
    if ($script:TextExact.ContainsKey($core)) {
        $entry = $script:TextExact[$core]
        $out = $entry.English
        # Stessa voce scritta con maiuscole diverse: la traduzione segue il testo originale
        if ($entry.Key -cne $core) {
            if ($core -cmatch '[a-z]') {
                $first = [regex]::Match($core, '\p{L}').Value
                $i = [regex]::Match($out, '\p{L}').Index
                $out = $out.Substring(0, $i) + $(if ($first -cmatch '[a-z]') { $out.Substring($i, 1).ToLower() } else { $out.Substring($i, 1).ToUpper() }) + $out.Substring($i + 1)
            } else {
                $out = $out.ToUpper()
            }
        }
    } else {
        foreach ($rule in $script:TextRules) {
            $hit = $rule.Regex.Match($core)
            if (-not $hit.Success) { continue }
            $values = @(for ($g = 1; $g -lt $hit.Groups.Count; $g++) { T $hit.Groups[$g].Value })
            $out = $rule.English -f $values
            break
        }
    }
    if ($null -eq $out) { return $Text }
    return $m.Groups[1].Value + $out + $m.Groups[3].Value
}

# ---------------------------------------------------------------- logo e intestazioni

# Le intestazioni, tutte nello stesso font (slant): scritta, motto e titolo della finestra
$Logos = @{
    Sibyl = @{
        Window  = 'Sibyl - preserve memories'
        Tagline = '~  p r e s e r v e   m e m o r i e s  ~'
        Art     = @'
   _____ _ __          __
  / ___/(_) /_  __  __/ /
  \__ \/ / __ \/ / / / /
 ___/ / / /_/ / /_/ / /
/____/_/_.___/\__, /_/
             /____/
'@
    }
    Launcher = @{
        Window  = 'Sibyl - Launcher'
        Tagline = '~  s i b y l   ::   l a u n c h e r  ~'
        Art     = @'
    __                           __
   / /   ____ ___  ______  _____/ /_  ___  _____
  / /   / __ `/ / / / __ \/ ___/ __ \/ _ \/ ___/
 / /___/ /_/ / /_/ / / / / /__/ / / /  __/ /
/_____/\__,_/\__,_/_/ /_/\___/_/ /_/\___/_/
'@
    }
    Organizer = @{
        Window  = 'Sibyl - Organizer'
        Tagline = '~  s i b y l   ::   o r g a n i z e r  ~'
        Art     = @'
   ____                        _
  / __ \_________ _____ _____  (_)___  ___  _____
 / / / / ___/ __ `/ __ `/ __ \/ /_  / / _ \/ ___/
/ /_/ / /  / /_/ / /_/ / / / / / / /_/  __/ /
\____/_/   \__, /\__,_/_/ /_/_/ /___/\___/_/
          /____/
'@
    }
}

# ---------------------------------------------------------------- ritorno al menu principale

# Codici di uscita con cui Launcher e Organizzatore dicono al menu principale cosa fare
$ExitToMenu = 98    # [M] torna al menu
$ExitQuitAll = 99   # [Q] chiudi Sibyl

# [M]: se aperti dal menu si torna li', se aperti dal loro .bat si apre il menu
function Exit-ToMenu([bool]$FromMenu) {
    if ($FromMenu) { exit $ExitToMenu }
    & (Join-Path $PSScriptRoot 'Sibyl.ps1')
    exit 0
}

# [Q]: chiude anche il menu principale, se e' stato lui ad aprirci
function Exit-QuitAll([bool]$FromMenu) {
    if ($FromMenu) { exit $ExitQuitAll }
    exit 0
}

# ---------------------------------------------------------------- icone (gamepad)

# Le icone sono scritte in ASCII e diventano caratteri a blocchi solo a schermo, come $BarFull,
# per non dipendere dalla codifica del file:  . chiaro   : medio   % scuro   # pieno   @ riflesso
$IconShades = @{ [char]'.' = [char]0x2591; [char]':' = [char]0x2592; [char]'%' = [char]0x2593; [char]'#' = [char]0x2588; [char]'@' = [char]0x2588 }
$IconColors = @{ [char]'.' = $Theme.Soft; [char]':' = $Theme.Accent; [char]'%' = $Theme.Frame; [char]'#' = $Theme.Title; [char]'@' = $Theme.Text }

# Icona piccola, ferma accanto alle scritte delle intestazioni
$SmallIcon = @'
          .:::::.
      .:%#########::.
    ..%##########%%%:..
   .%#%::#######%%::%#%.
  .%####%:%#%%%%%:%##%#%.
 .:#%.::##::%%%::#%%%%%%:.
 .%:::::.%:#...%:%:::%::%.
 .%#%:::##::%%%:.%%%::%%:.
  .#####%:%#%%%%:::%%%%%.
   .%#%:%######%%%:::%%.
    .:%#########%%%%:..
      .:%#######%%%:.
        ..:::::::..
'@

# Icona grande, animata nelle schermate del launcher: gira solo il riflesso sulla scocca
$PadArt = @'
                     .............
               .....:::%%%%%%%%:::.....
              ..::%################%:...
           ..::%####################%%%::..
         ...%######################%%%%%%:...
       .....::%###################%%%%%::......
      ..:##%::.:%################%%%%:..:%###:..
     ..:#######:..%#############%%%:..:#######%..
    ..:#########%:.:###########%%%:.:%########%:..
    ..%###%%%%####:::%%%::...::%::::####%%%%%%%%...
   ..%###%....:#####:..::%%%%::..:#####%:%%::%##%..
  ..:##%::.:::.:%%##%.%#%%::%%#%.:#%%::::%%::::%%:..
  ..:#%.::::::::..%#:%#%:....:%#%.%%:::::%%:::::%:..
  ..:#%.::::::::..%%:%#%:.....%#%.%%::::::%:.:::%:..
  ..:##%%:.:::.:%%##:.%#%::::%#%..%%%:%:::::::%%%:..
   ..%####:::::####%:.::%%%%%%:..:%%%%%%::::%%##%..
    .:############:.:%%%%::::::%::.:%%%%%::%%##%:..
    ..:#########%.:%#########%%%%%%:.:%%%%%%%%%:..
     ..%######%:.:%###########%%%%%%:..:%%%%%%:..
      ..:##%::::##############%%%%%%%%:..::%%:..
       ....::%#################%%%%%%%%::::....
         ..:%##################%%%%%%%%%%%...
          ...:%#################%%%%%%%::...
            ...::%%#############%%%%::...
               .....:%%%%%%%%%%%%:.....
                    ..............
'@

# Una riga di icona in pezzi dello stesso carattere e colore (meno scritture per riga)
function ConvertTo-IconRow([string]$Codes) {
    $segments = foreach ($run in [regex]::Matches($Codes, ' +|\.+|:+|%+|#+|@+|[^ .:%#@]+')) {
        $c = $run.Value[0]
        $ch = if ($IconShades.ContainsKey($c)) { $IconShades[$c] } else { [char]' ' }
        $color = if ($IconColors.ContainsKey($c)) { $IconColors[$c] } else { $Theme.Faint }
        @{ Text = "$ch" * $run.Length; Color = [ConsoleColor]$color }
    }
    return , @($segments)
}

# In una console vera si scrive direttamente (molto piu' veloce di Write-Host: serve all'animazione)
function Write-IconRow($Segments) {
    if ([Console]::IsOutputRedirected) {
        foreach ($segment in $Segments) { Write-Host $segment.Text -ForegroundColor $segment.Color -NoNewline }
        return
    }
    $old = [Console]::ForegroundColor
    foreach ($segment in $Segments) { [Console]::ForegroundColor = $segment.Color; [Console]::Write($segment.Text) }
    [Console]::ForegroundColor = $old
}

# Icona piccola a sinistra; a destra scritta, riga vuota e motto, centrati tra loro e
# all'altezza dell'icona. Il tutto parte dal margine dell'interfaccia (2 colonne).
function Write-Logo([string]$Name = 'Sibyl') {
    $logo = $Logos[$Name]
    $art = @($logo.Art -split "`r?`n")
    $artWidth = ($art | Measure-Object -Property Length -Maximum).Maximum
    $width = [math]::Max($artWidth, $logo.Tagline.Length)
    $text = @($art | ForEach-Object { @{ Text = (' ' * [math]::Floor(($width - $artWidth) / 2)) + $_; Color = $Theme.Title } })
    $text += @{ Text = ''; Color = $Theme.Title }
    $text += @{ Text = (' ' * [math]::Floor(($width - $logo.Tagline.Length) / 2)) + $logo.Tagline; Color = $Theme.Accent }
    $icon = @($SmallIcon -split "`r?`n")
    $iconWidth = ($icon | Measure-Object -Property Length -Maximum).Maximum
    $first = [math]::Floor(($icon.Count - $text.Count) / 2)
    for ($i = 0; $i -lt $icon.Count; $i++) {
        Write-Host '  ' -NoNewline
        Write-IconRow (ConvertTo-IconRow $icon[$i].PadRight($iconWidth))
        $j = $i - $first
        if ($j -ge 0 -and $j -lt $text.Count) { Write-Host ('   ' + $text[$j].Text) -ForegroundColor $text[$j].Color -NoNewline }
        Write-Host ''
    }
}

function Write-Banner([string]$Subtitle, [string]$Logo = 'Sibyl') {
    try { $Host.UI.RawUI.WindowTitle = $Logos[$Logo].Window } catch { }
    Write-Logo $Logo   # niente riga vuota sopra: la prima riga dell'icona fa gia' da margine
    Write-Host ''
    if ($Subtitle) {
        $label = " $((T $Subtitle).ToUpper()) "
        $pad = [math]::Max(0, 74 - $label.Length)
        $left = [math]::Floor($pad / 2)
        Write-Host ('  ' + ('=' * $left) + '[') -ForegroundColor $Theme.Frame -NoNewline
        Write-Host $label -ForegroundColor $Theme.Accent -NoNewline
        Write-Host (']' + ('=' * ($pad - $left))) -ForegroundColor $Theme.Frame
        Write-Host ''
    }
}

# ---------------------------------------------------------------- messaggi

function Write-Step([string]$Text) {
    Write-Host '  >> ' -ForegroundColor $Theme.Accent -NoNewline
    Write-Host (T $Text) -ForegroundColor $Theme.Title
}
function Write-Info([string]$Text) { Write-Host "     $(T $Text)" -ForegroundColor $Theme.Muted }
function Write-Ok([string]$Text) {
    Write-Host '  [OK] ' -ForegroundColor $Theme.Title -NoNewline
    Write-Host (T $Text) -ForegroundColor $Theme.Text
}
function Write-Alert([string]$Text) { Write-Host "  [!!] $(T $Text)" -ForegroundColor $Theme.Warn }

# Testo con i tasti tra parentesi quadre evidenziati: "[INVIO] gioca   [Q] esci"
function Write-Keys([string]$Text, [switch]$NoNewline) {
    $Text = T $Text
    Write-Host '  ' -NoNewline
    foreach ($part in [regex]::Split($Text, '(\[[^\]]+\])')) {
        if (-not $part) { continue }
        $color = if ($part.StartsWith('[')) { $Theme.Accent } else { $Theme.Muted }
        Write-Host $part -ForegroundColor $color -NoNewline
    }
    if (-not $NoNewline) { Write-Host '' }
}

# Domanda con risposta libera (percorsi: toglie le virgolette di un trascinamento)
function Read-Text([string]$Prompt) {
    Write-Keys "$Prompt " -NoNewline
    Write-Host '> ' -ForegroundColor $Theme.Accent -NoNewline
    return "$(Read-Host)".Trim().Trim('"')
}

function Read-Answer([string]$Prompt) { return (Read-Text $Prompt).ToUpper() }

# Risposta affermativa in italiano o in inglese
function Test-Yes([string]$Answer) { return $Answer -in 'S', 'SI', 'Y', 'YES' }

# Un tasto tra quelli ammessi, senza INVIO ('ENTER' per INVIO). Se l'input non e' una console
# (rediretto) si legge una riga; una riga vuota o la fine dell'input valgono $Default.
function Read-KeyChoice([string[]]$Allowed, [string]$Default) {
    while ($true) {
        try {
            $key = [Console]::ReadKey($true)
            $choice = if ($key.Key -eq 'Enter') { 'ENTER' } else { "$($key.KeyChar)".ToUpper() }
        } catch {
            $choice = Read-Answer ''
            if (-not $choice) { return $Default }
        }
        if ($choice -eq 'Y') { $choice = 'S' }   # "yes" vale come "si"
        if ($Allowed -contains $choice) { return $choice }
    }
}

# Scelta con domanda, senza INVIO: una lettera tra $Letters oppure un numero da 1 a $Count.
# Un numero parte appena non puo' piu' diventare un numero valido piu' lungo: con 12 voci "3"
# parte subito, "1" aspetta la seconda cifra (o INVIO). Restituisce la lettera, il numero come
# testo oppure '' per INVIO. Con l'input rediretto si legge una riga intera, come Read-Answer.
function Read-Pick([string]$Prompt, [int]$Count = 0, [string[]]$Letters = @()) {
    Write-Keys "$Prompt " -NoNewline
    Write-Host '> ' -ForegroundColor $Theme.Accent -NoNewline
    if ([Console]::IsInputRedirected) { return "$(Read-Host)".Trim().ToUpper() }
    $typed = ''
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { Write-Host ''; return $typed }
        if ($key.Key -eq 'Backspace') {
            if ($typed) { $typed = $typed.Substring(0, $typed.Length - 1); Write-Host "`b `b" -NoNewline }
            continue
        }
        $ch = "$($key.KeyChar)".ToUpper()
        if ($ch -eq 'Y' -and $Letters -contains 'S' -and $Letters -notcontains 'Y') { $ch = 'S' }   # "yes" vale come "si"
        if ($Count -and $ch -match '^\d$') {
            $n = [int]($typed + $ch)
            if ($n -lt 1 -or $n -gt $Count) { continue }
            $typed += $ch
            Write-Host $ch -ForegroundColor $Theme.Title -NoNewline
            if ($n * 10 -gt $Count) { Write-Host ''; return $typed }
            continue
        }
        if (-not $typed -and $Letters -contains $ch) { Write-Host $ch -ForegroundColor $Theme.Title; return $ch }
    }
}

function Confirm-Action([string]$Question) {
    Write-Keys "$Question   [S] si   [N] no"
    return (Read-KeyChoice @('S', 'N') 'N') -eq 'S'
}

# Riga di stato che si sovrascrive (spinner, conti alla rovescia)
function Write-Status([string]$Text, [string]$Color = $Theme.Title) {
    $Text = T $Text
    if ($Text.Length -gt 76) { $Text = $Text.Substring(0, 73) + '...' }
    Write-Host -NoNewline ("`r  {0,-76}" -f $Text) -ForegroundColor $Color
}

# Barra che si sovrascrive. Percentuale negativa = durata sconosciuta (blocco che scorre)
function Write-ProgressBar([string]$Label, [double]$Percent, [string]$Suffix = '', [int]$Tick = 0) {
    $width = 32
    if ($Percent -ge 0) {
        $fill = [int][math]::Round($width * [math]::Min($Percent, 100) / 100)
        $bar = ($BarFull * $fill) + ($BarEmpty * ($width - $fill))
        $pct = '{0,3:0}%' -f [math]::Min($Percent, 100)
    } else {
        $pos = $Tick % ($width - 3)
        $bar = ($BarEmpty * $pos) + ($BarFull * 3) + ($BarEmpty * ($width - 3 - $pos))
        $pct = ' ...'
    }
    $Label = T $Label
    if ($Label.Length -gt 24) { $Label = $Label.Substring(0, 21) + '...' }
    Write-Host -NoNewline ("`r  {0,-24} " -f $Label) -ForegroundColor $Theme.Text
    Write-Host -NoNewline $bar -ForegroundColor $Theme.Accent
    Write-Host -NoNewline (" {0}  {1,-11}" -f $pct, $Suffix) -ForegroundColor $Theme.Title
}

# ---------------------------------------------------------------- disco animato

# Il disco e' calcolato, non disegnato a mano: per ogni carattere si guarda la distanza dal
# centro (bordo, tracce, anello trasparente, mozzo, foro) e l'angolo rispetto ai due riflessi
# di luce opposti. Spostando i riflessi a ogni fotogramma il disco sembra girare.
$DiscWidth = 37
$DiscHeight = 15
$DiscIndent = 20
$DiscFrameCount = 12
$DiscSpin = @{ Top = -1; Bottom = -1; Frame = 0; Next = [datetime]::MinValue; Kind = 'disc' }

function Get-DiscFrames {
    if (Get-Variable -Name DiscFrames -Scope Script -ErrorAction SilentlyContinue) { return $script:DiscFrames }
    $cx = ($DiscWidth - 1) / 2
    $cy = ($DiscHeight - 1) / 2
    $frames = for ($f = 0; $f -lt $DiscFrameCount; $f++) {
        $theta = [math]::PI * $f / $DiscFrameCount   # due riflessi opposti: mezzo giro chiude il ciclo
        $rows = for ($y = 0; $y -lt $DiscHeight; $y++) {
            if ([math]::Abs(($y - $cy) / $cy) -ge 0.99) { continue }   # righe vuote sopra e sotto
            $segments = New-Object System.Collections.Generic.List[object]
            for ($x = 0; $x -lt $DiscWidth; $x++) {
                $dx = ($x - $cx) / $cx
                $dy = ($y - $cy) / $cy
                $r = [math]::Sqrt($dx * $dx + $dy * $dy)
                $angle = [math]::Atan2($dy, $dx)
                $shine = [math]::Abs((($angle - $theta) % [math]::PI + 1.5 * [math]::PI) % [math]::PI - 0.5 * [math]::PI)
                $ch = ' '; $color = $Theme.Faint
                if ($r -lt 0.99) {
                    if ($r -gt 0.88) { $ch = '#'; $color = $Theme.Frame }
                    elseif ($r -gt 0.38) {
                        if ($shine -lt 0.16) { $ch = '@'; $color = $Theme.Text }
                        elseif ($shine -lt 0.34) { $ch = '*'; $color = $Theme.Accent }
                        elseif ($shine -lt 0.55) { $ch = '+'; $color = $Theme.Soft }
                        else { $ch = ('.', ':')[[int][math]::Floor($r * 16) % 2]; $color = $Theme.Title }
                    }
                    elseif ($r -gt 0.28) { $ch = '='; $color = $Theme.Frame }
                    elseif ($r -gt 0.14) { $ch = 'O'; $color = $Theme.Accent }
                }
                # caratteri vicini dello stesso colore in un solo pezzo: meno Write-Host per fotogramma
                if ($segments.Count -and $segments[$segments.Count - 1].Color -eq $color) { $segments[$segments.Count - 1].Text += $ch }
                else { $segments.Add(@{ Text = $ch; Color = $color }) }
            }
            , $segments.ToArray()
        }
        , $rows
    }
    $script:DiscFrames = $frames
    return $frames
}

# Il gamepad del launcher: croce direzionale, tasti e anello centrale restano fermi (le tre ellissi),
# sul resto della scocca i blocchi pieni e scuri seguono una luce che gira, con un riflesso bianco
# nella sua direzione
$PadFrameCount = 16
$PadIndent = 13   # 52 colonne centrate sulle 78 dell'interfaccia
$PadStill = @(
    @{ X = 10.9; Y = 12.5; RX = 9.4; RY = 7.5 },
    @{ X = 26.5; Y = 12.5; RX = 7.6; RY = 4.2 },
    @{ X = 42.5; Y = 12.5; RX = 9.4; RY = 7.5 }
)

function Get-PadFrames {
    if (Get-Variable -Name PadFrames -Scope Script -ErrorAction SilentlyContinue) { return $script:PadFrames }
    $rows = @($PadArt -split "`r?`n")
    # Le celle della scocca che cambiano, con la loro posizione rispetto al centro (calcolate una volta)
    $cells = for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt $rows[$y].Length; $x++) {
            if ($rows[$y][$x] -ne '#' -and $rows[$y][$x] -ne '%') { continue }
            $still = $false
            foreach ($z in $PadStill) {
                $ex = ($x - $z.X) / $z.RX; $ey = ($y - $z.Y) / $z.RY
                if ($ex * $ex + $ey * $ey -le 1) { $still = $true; break }
            }
            if ($still) { continue }
            $nx = ($x - 26) / 26; $ny = ($y - 12.5) / 13
            @{ X = $x; Y = $y; NX = $nx; NY = $ny; Angle = [math]::Atan2($ny, $nx) }
        }
    }
    $script:PadCodes = for ($f = 0; $f -lt $PadFrameCount; $f++) {
        $theta = 2 * [math]::PI * $f / $PadFrameCount
        $cos = [math]::Cos($theta); $sin = [math]::Sin($theta)
        $grid = @($rows | ForEach-Object { , $_.ToCharArray() })
        foreach ($c in $cells) {
            $light = $c.NX * $cos + $c.NY * $sin
            $off = [math]::Abs((($c.Angle - $theta) % (2 * [math]::PI) + 3 * [math]::PI) % (2 * [math]::PI) - [math]::PI)
            $grid[$c.Y][$c.X] = if ($light -lt -0.17) { '%' } elseif ($off -lt 0.3) { '@' } else { '#' }
        }
        , @($grid | ForEach-Object { -join $_ })
    }
    $frames = foreach ($codes in $script:PadCodes) { , @($codes | ForEach-Object { , (ConvertTo-IconRow $_) }) }
    $script:PadFrames = $frames
    return $frames
}

# Fotogrammi e rientro dell'animazione: 'disc' (disco che gira) o 'pad' (gamepad del launcher)
function Get-SpinFrames([string]$Kind) { if ($Kind -eq 'pad') { Get-PadFrames } else { Get-DiscFrames } }

# Il gamepad e' grande: tra un fotogramma e l'altro si riscrivono solo i tratti che cambiano
function Write-PadChanges([int]$From, [int]$To) {
    $a = $script:PadCodes[$From % $PadFrameCount]
    $b = $script:PadCodes[$To % $PadFrameCount]
    for ($y = 0; $y -lt $b.Count; $y++) {
        if ($a[$y] -ceq $b[$y]) { continue }
        $x = 0
        while ($x -lt $b[$y].Length) {
            if ($a[$y][$x] -eq $b[$y][$x]) { $x++; continue }
            $start = $x
            while ($x -lt $b[$y].Length -and $a[$y][$x] -ne $b[$y][$x]) { $x++ }
            [Console]::SetCursorPosition($PadIndent + $start, $DiscSpin.Top + $y)
            Write-IconRow (ConvertTo-IconRow $b[$y].Substring($start, $x - $start))
        }
    }
}

function Write-DiscFrame([int]$Index, [string]$Kind = 'disc') {
    $frames = Get-SpinFrames $Kind
    $indent = ' ' * $(if ($Kind -eq 'pad') { $PadIndent } else { $DiscIndent })
    foreach ($row in $frames[$Index % $frames.Count]) {
        Write-Host $indent -NoNewline
        Write-IconRow $row
        Write-Host ''
    }
}

# Start-DiscSpin disegna il disco e ricorda in che riga; Update-DiscSpin lo ridisegna al
# fotogramma successivo e rimette il cursore dov'era (sulla barra di avanzamento).
# Senza una console vera (output rediretto) il disco resta fermo.
#
# Se la finestra scorresse durante l'animazione, la riga memorizzata non indicherebbe piu' il
# disco e i fotogrammi si accumulerebbero uno sotto l'altro. Per questo Start-DiscSpin fa
# scorrere subito la finestra di tutto lo spazio che serve (disco + $ExtraLines righe per barre
# e messaggi), e Update-DiscSpin si ferma se il testo esce comunque da quello spazio.
function Start-DiscSpin([int]$ExtraLines = 8, [string]$Kind = 'disc') {
    $DiscSpin.Top = -1
    $DiscSpin.Frame = 0
    $DiscSpin.Kind = $Kind
    try {
        $need = (Get-SpinFrames $Kind)[0].Count + $ExtraLines
        [void][Console]::CursorTop   # output rediretto: lancia e si salta la preparazione
        Write-Host ("`n" * $need) -NoNewline
        $top = [Console]::CursorTop - $need
        [Console]::SetCursorPosition(0, $top)
        $DiscSpin.Top = $top
        $DiscSpin.Bottom = $top + $need
    } catch {
        $DiscSpin.Top = -1
    }
    Write-DiscFrame 0 $Kind
}

function Update-DiscSpin {
    if ($DiscSpin.Top -lt 0 -or (Get-Date) -lt $DiscSpin.Next) { return }
    $DiscSpin.Next = (Get-Date).AddMilliseconds(90)
    try {
        $left = [Console]::CursorLeft
        $top = [Console]::CursorTop
        if ($top -ge $DiscSpin.Bottom) { $DiscSpin.Top = -1; return }   # uscito dallo spazio riservato
        $DiscSpin.Frame++
        if ($DiscSpin.Kind -eq 'pad') { Write-PadChanges ($DiscSpin.Frame - 1) $DiscSpin.Frame }
        else {
            [Console]::SetCursorPosition(0, $DiscSpin.Top)
            Write-DiscFrame $DiscSpin.Frame $DiscSpin.Kind
        }
        [Console]::SetCursorPosition($left, $top)
    } catch {
        $DiscSpin.Top = -1
    }
}

function Stop-DiscSpin { $DiscSpin.Top = -1 }

function Write-Box([string[]]$Lines, [string]$Color = $Theme.Frame) {
    # Le righe che iniziano con '*' sono titoli, in viola
    $width = 64
    Write-Host ('  +' + ('-' * $width) + '+') -ForegroundColor $Color
    foreach ($l in $Lines) {
        $textColor = $Theme.Text
        if ($l.StartsWith('*')) { $l = $l.Substring(1); $textColor = $Theme.Accent }
        $l = T $l
        if ($l.Length -gt $width - 2) { $l = $l.Substring(0, $width - 5) + '...' }
        Write-Host '  | ' -ForegroundColor $Color -NoNewline
        Write-Host ("{0,-$($width - 2)}" -f $l) -ForegroundColor $textColor -NoNewline
        Write-Host ' |' -ForegroundColor $Color
    }
    Write-Host ('  +' + ('-' * $width) + '+') -ForegroundColor $Color
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# ---------------------------------------------------------------- file

function Get-SafeName([string]$Name) {
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $clean = -join ($Name.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
    return $clean.Trim().TrimEnd('.')
}

function Write-TextFile([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

# Legge un file JSON (manifest, stato, configurazione): $null se manca o non e' valido
function Read-Manifest([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch { return $null }
}

# Niente finestre di Windows "Inserire un disco" quando Sibyl controlla un lettore vuoto
# (o un disco che il masterizzatore sta scrivendo): il controllo fallisce in silenzio
if (-not ('Sibyl.Native' -as [type])) {
    Add-Type -Namespace Sibyl -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool CreateHardLink(string newFile, string existingFile, IntPtr security);
'@
}
[void][Sibyl.Native]::SetErrorMode(0x8001)   # SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX

# Finestra della console classica di circa 800x700 pixel, con il testo largo quanto la finestra
# (niente barra di scorrimento orizzontale). Windows Terminal non lascia ridimensionare la propria
# finestra: li' non si fa niente. Per questo Sibyl.exe apre sempre la console classica.
function Set-SibylWindowSize {
    if ($env:WT_SESSION -or [Console]::IsOutputRedirected) { return }
    try {
        $hwnd = [Sibyl.Native]::GetConsoleWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return }
        [void][Sibyl.Native]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 800, 700, 0x0006)   # SWP_NOMOVE | SWP_NOZORDER
        $raw = $Host.UI.RawUI
        $raw.BufferSize = New-Object Management.Automation.Host.Size $raw.WindowSize.Width, ([math]::Max($raw.BufferSize.Height, 3000))
    } catch { }
}
if (-not (Get-Variable -Name SibylWindowSized -Scope Global -ErrorAction SilentlyContinue)) {
    $global:SibylWindowSized = $true   # una volta sola, anche se il modulo viene caricato da piu' script
    Set-SibylWindowSize
}

# Lettore in masterizzazione: l'Organizer lo segna qui e il Launcher non lo tocca finche' non e' libero
$BurnMarkerPath = Join-Path $env:LOCALAPPDATA 'Sibyl\burning.json'

function Set-BurnMarker([string]$Root) {
    [void][IO.Directory]::CreateDirectory((Split-Path $BurnMarkerPath))
    Write-TextFile $BurnMarkerPath (@{ root = $Root; pid = $PID } | ConvertTo-Json)
}

function Clear-BurnMarker { Remove-Item -LiteralPath $BurnMarkerPath -ErrorAction SilentlyContinue }

# Il lettore che si sta masterizzando, o $null. Un segno lasciato da un Organizer chiuso male non conta.
function Get-BurningRoot {
    $marker = Read-Manifest $BurnMarkerPath
    if (-not $marker) { return $null }
    if (-not (Get-Process -Id ([int]$marker.pid) -ErrorAction SilentlyContinue)) { return $null }
    return [string]$marker.root
}

# Preferenze ricordate tra un avvio e l'altro (cartelle usate l'ultima volta), comuni ai due programmi
function Read-Config {
    # Primo avvio con il nome nuovo: si riparte dalla configurazione di quando si chiamava TimeRunner
    if (-not (Test-Path -LiteralPath $ConfigPath) -and (Test-Path -LiteralPath $LegacyConfigPath)) {
        [void][IO.Directory]::CreateDirectory((Split-Path $ConfigPath))
        Copy-Item -LiteralPath $LegacyConfigPath -Destination $ConfigPath
    }
    return Read-Manifest $ConfigPath
}

function Set-ConfigValue([string]$Name, $Value) {
    $config = [ordered]@{}
    $old = Read-Config
    if ($old) { foreach ($p in $old.PSObject.Properties) { $config[$p.Name] = $p.Value } }
    $config[$Name] = $Value
    [void][IO.Directory]::CreateDirectory((Split-Path $ConfigPath))
    Write-TextFile $ConfigPath ($config | ConvertTo-Json)
}

# ---------------------------------------------------------------- avvio automatico del launcher

$AutostartLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Sibyl.lnk'
$LegacyAutostartLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'TimeRunner.lnk'

function Test-Autostart { return (Test-Path -LiteralPath $AutostartLink) -or (Test-Path -LiteralPath $LegacyAutostartLink) }

function Set-Autostart([bool]$On) {
    # Il collegamento di TimeRunner punterebbe a un programma che non c'e' piu': si toglie sempre
    Remove-Item -LiteralPath $LegacyAutostartLink -ErrorAction SilentlyContinue
    if (-not $On) { Remove-Item -LiteralPath $AutostartLink -ErrorAction SilentlyContinue; return }
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($AutostartLink)
    if ($env:SIBYL_EXE) {
        # Avviato da Sibyl.exe: gli script stanno in una cartella temporanea, si punta all'exe
        $shortcut.TargetPath = $env:SIBYL_EXE
        $shortcut.Arguments = 'launcher'
        $shortcut.WorkingDirectory = Split-Path $env:SIBYL_EXE
    } else {
        $shortcut.TargetPath = Join-Path $PSScriptRoot 'SibylLauncher.bat'
        $shortcut.WorkingDirectory = $PSScriptRoot
    }
    $shortcut.WindowStyle = 1   # finestra normale: la dimensione la sceglie Sibyl (800x700)
    $shortcut.Save()
}

# ---------------------------------------------------------------- giochi installati

# Cartella in cui il launcher installa i giochi (scelta all'avvio del launcher). Senza una scelta
# salvata si usa %LOCALAPPDATA%\Sibyl\Games, o quella di TimeRunner se ci sono gia' giochi li'.
function Get-LibraryPath {
    $library = Get-Prop (Read-Config) 'library'
    if ($library) { return $library }
    $default = Join-Path $env:LOCALAPPDATA 'Sibyl\Games'
    $legacy = Join-Path $env:LOCALAPPDATA 'TimeRunner\Games'
    if (-not (Test-Path -LiteralPath $default) -and (Test-Path -LiteralPath $legacy)) { return $legacy }
    return $default
}

# Stato di un gioco installato (state.json nella sua cartella della libreria). Se la libreria e' stata
# spostata o rinominata, installDir punta ancora al posto vecchio: se il gioco e' nella sua cartella
# "game" accanto allo stato, si corregge il percorso e lo si salva.
function Read-GameState([string]$GameHome) {
    $path = Join-Path $GameHome 'state.json'
    $state = Read-Manifest $path
    if (-not $state) { return $null }
    $dir = Get-Prop $State 'installDir'
    $local = Join-Path $GameHome 'game'
    if ((-not $dir -or -not (Test-Path -LiteralPath $dir)) -and (Test-Path -LiteralPath $local)) {
        $old = $dir
        $state.installDir = $local
        foreach ($name in 'launchExe', 'displayIcon') {
            $value = Get-Prop $state $name
            if ($old -and $value -and $value.StartsWith($old, [StringComparison]::OrdinalIgnoreCase)) {
                $state.$name = $local + $value.Substring($old.Length)
            }
        }
        Write-TextFile $path ($state | ConvertTo-Json)
    }
    return $state
}

function Get-InstalledGames([string]$Library) {
    if (-not (Test-Path -LiteralPath $Library)) { return @() }
    return @(foreach ($dir in Get-ChildItem -LiteralPath $Library -Directory) {
        $state = Read-GameState $dir.FullName
        if (-not $state) { continue }
        [pscustomobject]@{ Home = $dir.FullName; State = $state; Title = $state.title; Version = $state.version }
    })
}

# ---------------------------------------------------------------- installer di ogni tipo

# Tipo di installer, riconosciuto dalle firme che lasciano dentro l'exe (primi 16 MB):
# inno (GOG e molti altri), nsis, installshield, wix, msi; 'unknown' se non si riconosce.
# Inno, NSIS e MSI si installano in silenzio in una cartella scelta da Sibyl; gli altri con le loro finestre.
function Get-InstallerType([string]$Path) {
    if ([IO.Path]::GetExtension($Path) -ieq '.msi') { return 'msi' }
    $signatures = [ordered]@{
        inno          = 'Inno Setup Setup Data'
        nsis          = 'NullsoftInst'
        installshield = 'InstallShield'
        wix           = '.wixburn'
    }
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            $buffer = New-Object byte[] ([math]::Min($stream.Length, 16MB))
            [void]$stream.Read($buffer, 0, $buffer.Length)
        } finally { $stream.Dispose() }
        $text = [Text.Encoding]::ASCII.GetString($buffer)
        foreach ($type in $signatures.Keys) { if ($text.Contains($signatures[$type])) { return $type } }
    } catch { }
    return 'unknown'
}

# Le voci di "App installate" di Windows. Confrontando l'elenco prima e dopo un'installazione si
# scopre dove e' finito il gioco, qual e' il suo exe (l'icona) e come si disinstalla.
function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    return @(foreach ($p in $paths) {
        foreach ($item in Get-ItemProperty -Path $p -ErrorAction SilentlyContinue) {
            [pscustomobject]@{
                Key             = $item.PSPath
                Name            = Get-Prop $item 'DisplayName'
                InstallLocation = Get-Prop $item 'InstallLocation'
                DisplayIcon     = Get-Prop $item 'DisplayIcon'
                Uninstall       = Get-Prop $item 'UninstallString'
                QuietUninstall  = Get-Prop $item 'QuietUninstallString'
            }
        }
    })
}

# Il percorso di un exe dentro un campo come DisplayIcon: "C:\Giochi\game.exe",0
function Get-ExeFromIcon([string]$Icon) {
    if (-not $Icon) { return $null }
    $path = ($Icon -replace ',\s*-?\d+$', '').Trim().Trim('"')
    if ($path -like '*.exe') { return $path }
    return $null
}

# "C:\Program Files\Gioco\uninst.exe" /S  ->  FilePath + Arguments per Start-Process
function Split-CommandLine([string]$Command) {
    $Command = $Command.Trim()
    if ($Command.StartsWith('"')) {
        $end = $Command.IndexOf('"', 1)
        return @{ FilePath = $Command.Substring(1, $end - 1); Arguments = $Command.Substring($end + 1).Trim() }
    }
    $i = $Command.ToLower().IndexOf('.exe')
    if ($i -ge 0) { return @{ FilePath = $Command.Substring(0, $i + 4); Arguments = $Command.Substring($i + 4).Trim() } }
    $parts = $Command -split '\s+', 2
    return @{ FilePath = $parts[0]; Arguments = $(if ($parts.Count -gt 1) { $parts[1] } else { '' }) }
}

# Disinstalla un gioco e cancella la sua cartella nella libreria (stato, log e file rimasti).
# Disinstallatore, nell'ordine: unins*.exe di Inno Setup (GOG, silenzioso), quello silenzioso registrato
# in Windows, quello normale (MSI in silenzio, gli altri con le loro finestre). Restituisce $true se e' sparita.
function Uninstall-Game([string]$GameHome, $State, [string]$Library) {
    # Si cancella solo una cartella che sta davvero dentro la libreria
    $root = [IO.Path]::GetFullPath($Library).TrimEnd('\') + '\'
    if (-not [IO.Path]::GetFullPath($GameHome).StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "La cartella del gioco non e' dentro la libreria: $GameHome"
    }
    $dir = Get-Prop $State 'installDir'
    $command = $null
    $inno = $null
    if ($dir -and (Test-Path -LiteralPath $dir)) {
        $inno = Get-ChildItem -LiteralPath $dir -Filter 'unins*.exe' -File | Sort-Object Name | Select-Object -First 1
    }
    if ($inno) {
        $command = @{ FilePath = $inno.FullName; Arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
    } elseif (Get-Prop $State 'quietUninstall') {
        $command = Split-CommandLine $State.quietUninstall
    } elseif (Get-Prop $State 'uninstallString') {
        $command = Split-CommandLine $State.uninstallString
        if ($command.FilePath -match 'msiexec') {
            $command.Arguments = ($command.Arguments -replace '/I', '/X') + ' /qn /norestart'
        } else {
            Write-Info 'Segui la disinstallazione nella finestra del disinstallatore.'
        }
    }

    if ($command) {
        $params = @{ FilePath = $command.FilePath; PassThru = $true }
        if ($command.Arguments) { $params.ArgumentList = $command.Arguments }
        try { $process = Start-Process @params }
        catch { Write-Alert 'Disinstallazione annullata: servono i permessi di Windows'; return $false }
        # Molti disinstallatori (Inno Setup, NSIS) si copiano altrove e chiudono l'originale: hanno
        # finito quando il loro .exe sparisce dalla cartella del gioco. Si aspetta al massimo 3 minuti.
        $exe = $command.FilePath
        $watchExe = $dir -and $exe.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase)
        $start = Get-Date
        $tick = 0
        $until = $null
        while ($true) {
            if ($process.HasExited) {
                if (-not $until) { $until = (Get-Date).AddMinutes(3) }
                if (-not $watchExe -or -not (Test-Path -LiteralPath $exe) -or (Get-Date) -gt $until) { break }
            }
            Write-ProgressBar 'Disinstallazione' -1 ((Get-Date) - $start).ToString('mm\:ss') ($tick++)
            Start-Sleep -Milliseconds 200
        }
        Write-ProgressBar 'Disinstallazione' 100 ((Get-Date) - $start).ToString('mm\:ss')
        Write-Host ''
    }
    Remove-Item -LiteralPath $GameHome -Recurse -Force -ErrorAction SilentlyContinue
    return -not (Test-Path -LiteralPath $GameHome)
}

# ---------------------------------------------------------------- dischi multipli

# Un gioco piu' grande di un disco viene diviso su piu' dischi: ogni disco ha lo stesso manifest con
# "disc" (questo disco) e "discs" (quanti sono), e ogni file del manifest dice su quale disco sta.
function Get-DiscNumber($Manifest) { $n = Get-Prop $Manifest 'disc'; if ($n) { return [int]$n }; return 1 }
function Get-DiscCount($Manifest) { $n = Get-Prop $Manifest 'discs'; if ($n) { return [int]$n }; return 1 }
function Get-FileDisc($File) { $n = Get-Prop $File 'disc'; if ($n) { return [int]$n }; return 1 }

# Due dischi fanno parte della stessa serie se vengono dalla stessa preparazione dello stesso gioco
function Test-SameSet($A, $B) {
    return $A -and $B -and $A.id -eq $B.id -and (Get-Prop $A 'version') -eq (Get-Prop $B 'version') -and
        (Get-Prop $A 'prepared') -eq (Get-Prop $B 'prepared')
}

# Espelle il disco di un'unita' (es. F:\) per far inserire il successivo
function Invoke-DriveEject([string]$Root) {
    try {
        $item = (New-Object -ComObject Shell.Application).Namespace(17).ParseName($Root)
        if ($item) { $item.InvokeVerb('Eject') }
    } catch { }
}

# Tasto premuto adesso, senza aspettare; $null se nessuno (o se l'input non e' una console)
function Read-KeyNow {
    try { if ([Console]::KeyAvailable) { return [Console]::ReadKey($true) } } catch { }
    return $null
}

# Schermata comune a Launcher e Organizer: riepilogo, avviso sui salvataggi, conferma, disinstallazione
function Invoke-UninstallScreen([string]$Title, [string]$GameHome, $State, [string]$Library) {
    # Un installer non GOG puo' aver messo il gioco fuori dalla libreria: si misura la cartella vera
    $measured = $GameHome
    $installDir = Get-Prop $State 'installDir'
    if ($installDir -and (Test-Path -LiteralPath $installDir)) { $measured = $installDir }
    $bytes = [long](Get-ChildItem -LiteralPath $measured -File -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    Write-Box @(
        ''
        "*  $($Title.ToUpper())"
        ''
        ('  {0,-16}{1}' -f (T 'Cartella'), (Get-Prop $State 'installDir'))
        ('  {0,-16}{1}' -f (T 'Spazio occupato'), (Format-Size $bytes))
        ''
    )
    Write-Host ''
    Write-Alert 'I salvataggi tenuti nella cartella del gioco verranno cancellati.'
    Write-Info 'Quelli in Documenti o in Saved Games restano dove sono.'
    Write-Host ''
    if (-not (Confirm-Action "Disinstallare $($Title)?")) {
        Write-Info 'Disinstallazione annullata.'
        Start-Sleep -Seconds 1
        return $false
    }
    Write-Host ''
    $done = Uninstall-Game $GameHome $State $Library
    if ($done) { Write-Ok "$Title disinstallato: $(Format-Size $bytes) liberati" }
    else { Write-Alert "Alcuni file non sono stati cancellati: $GameHome" }
    Start-Sleep -Seconds 2
    return $done
}

function Get-FreeSpace([string]$Path) {
    try { return Format-Size (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)))).AvailableFreeSpace }
    catch { return '?' }
}

# SHA-256 letto a blocchi da 1 MB: $OnChunk riceve i byte di ogni blocco (per le barre di avanzamento)
function Get-FileSha256([string]$Path, [scriptblock]$OnChunk) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] (1MB)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void]$sha.TransformBlock($buffer, 0, $read, $null, 0)
            if ($OnChunk) { & $OnChunk $read }
        }
        [void]$sha.TransformFinalBlock($buffer, 0, 0)
        return ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLower()
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

# Confronta i file di un disco (o di una cartella) con il manifest: presenza, dimensione, SHA-256.
# $OnProgress riceve (byte controllati, byte totali, percorso). Restituisce i problemi trovati.
function Test-DiscFiles([string]$Root, $Manifest, [scriptblock]$OnProgress) {
    # Solo i file di questo disco (in un gioco su piu' dischi gli altri stanno altrove)
    $disc = Get-DiscNumber $Manifest
    $files = @($Manifest.files | Where-Object { (Get-FileDisc $_) -eq $disc })
    $problems = New-Object System.Collections.Generic.List[string]
    $progress = @{ Done = 0L; Total = [long]($files | ForEach-Object { $_.size } | Measure-Object -Sum).Sum; Path = '' }
    $report = { param($bytes) $progress.Done += $bytes; if ($OnProgress) { & $OnProgress $progress.Done $progress.Total $progress.Path } }
    foreach ($f in $files) {
        $progress.Path = $f.path
        $path = Join-Path $Root ($f.path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path)) { $problems.Add("mancante  : $($f.path)"); & $report $f.size; continue }
        if ((Get-Item -LiteralPath $path).Length -ne $f.size) { $problems.Add("dimensione: $($f.path)"); & $report $f.size; continue }
        if (-not $f.sha256) { & $report $f.size; continue }
        $before = $progress.Done
        $attempt = 0
        while ($true) {
            try {
                if ((Get-FileSha256 $path $report) -ne $f.sha256) { $problems.Add("corrotto  : $($f.path)") }
                break
            } catch {
                # Subito dopo la masterizzazione Windows rimonta il disco e le letture in corso si
                # interrompono: si aspetta e si riprova prima di dare il file per illeggibile (CRC)
                $progress.Done = $before
                if (++$attempt -lt 3) { Start-Sleep -Seconds 5; continue }
                $problems.Add("illeggibile: $($f.path)  ($($_.Exception.GetBaseException().Message.Trim()))")
                & $report $f.size
                break
            }
        }
    }
    return $problems.ToArray()
}

# Barra di verifica comune a Disc Prep e Sibyl: avanza per byte letti e mostra la velocita'
function Test-DiscWithProgress([string]$Root, $Manifest) {
    $view = @{ Start = Get-Date; Last = [datetime]::MinValue }
    Start-DiscSpin
    Write-Host ''
    Write-ProgressBar 'Verifica disco' 0 'avvio'
    $problems = @(Test-DiscFiles $Root $Manifest {
        param($done, $total, $path)
        Update-DiscSpin
        $now = Get-Date
        if (($now - $view.Last).TotalMilliseconds -lt 250) { return }
        $view.Last = $now
        $seconds = ($now - $view.Start).TotalSeconds
        $speed = if ($seconds -gt 0) { $done / $seconds } else { 0 }
        $percent = if ($total -gt 0) { 100 * $done / $total } else { 100 }
        Write-ProgressBar 'Verifica disco' $percent ('{0:N1} MB/s' -f ($speed / 1MB))
    })
    Write-ProgressBar 'Verifica disco' 100 ('{0:mm\:ss}' -f ((Get-Date) - $view.Start))
    Write-Host ''
    Stop-DiscSpin
    return $problems
}

# Proprieta' opzionale di un oggetto JSON, senza errori in StrictMode
function Get-Prop($Object, [string]$Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}
