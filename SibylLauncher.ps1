<#
.SYNOPSIS
    Sibyl Launcher - la console per i tuoi giochi GOG su disco.

.DESCRIPTION
    Resta in attesa di un disco nel lettore. Quando trova un disco preparato con
    Organize-GogGames.ps1 (sibyl.json nella radice, o timerunner.json per i dischi di TimeRunner):
      - al primo inserimento installa il gioco nella libreria locale (come le console
        che installano su hard disk: il disco e' di sola lettura, i salvataggi no);
      - poi lo avvia, e quando chiudi il gioco torna alla schermata del disco.
    Se il disco contiene una versione piu' nuova di quella installata, la aggiorna.

.PARAMETER Drive
    Lettore o cartella da controllare al posto dei lettori ottici (es. E:\, oppure una
    cartella della libreria di Disc Prep per provare senza masterizzare).
.PARAMETER Library
    Dove installare i giochi, senza chiederlo. Altrimenti all'avvio propone quella dell'ultima
    volta (la prima volta %LOCALAPPDATA%\Sibyl\Games) e permette di cambiarla.
.PARAMETER Countdown
    Secondi prima dell'avvio automatico (0 = parte subito).
.PARAMETER ShowInstaller
    Mostra la procedura guidata dell'installer GOG invece di installare in silenzio.
.PARAMETER Once
    Esce dopo la prima partita.
.PARAMETER Autostart
    On = avvia il launcher all'accesso a Windows, Off = toglie l'avvio automatico.

.EXAMPLE
    .\SibylLauncher.ps1
.EXAMPLE
    .\SibylLauncher.ps1 -Drive "D:\Download\GOG\Sibyl-Library\Fallout 2 (2.1.0.18)"
.EXAMPLE
    .\SibylLauncher.ps1 -Autostart On
#>
[CmdletBinding()]
param(
    [string]$Drive,
    [string]$Library,
    [int]$Countdown = 15,
    [switch]$ShowInstaller,
    [switch]$Once,
    [switch]$FromMenu,   # aperto dal menu di Sibyl: [M] ci torna invece di riaprirlo
    [ValidateSet('On', 'Off')][string]$Autostart
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Sibyl.Common.ps1')

$PollMs = 1500

# ---------------------------------------------------------------- console

function Format-Duration([TimeSpan]$Span) {
    if ($Span.TotalHours -ge 1) { return '{0}h {1:00}m' -f [math]::Floor($Span.TotalHours), $Span.Minutes }
    return '{0}m {1:00}s' -f $Span.Minutes, $Span.Seconds
}

function Show-Screen([string]$Subtitle) {
    Clear-Host
    Write-Banner $Subtitle 'Launcher'
}

# ---------------------------------------------------------------- lettori e dischi

function Get-DiscRoots {
    if ($Drive) { return @($Drive) }
    return @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'CDRom' } |
        ForEach-Object { $_.RootDirectory.FullName })
}

# Etichetta e dimensione del disco nel lettore, $null se il lettore e' vuoto. Le chiede al lettore
# stesso: cambiano subito anche quando Windows mostra ancora per un attimo i file del disco precedente.
function Get-VolumeIdentity([string]$Root) {
    if ($Root -notmatch '^[A-Za-z]:\\?$') { return 'cartella' }   # -Drive su una cartella di prova
    $drive = New-Object IO.DriveInfo $Root
    if (-not $drive.IsReady) { return $null }
    return "$($drive.VolumeLabel)|$($drive.TotalSize)"
}

# Cambia quando il disco viene tolto o sostituito con un altro
function Get-DiscSignature([string]$Root) {
    try {
        # Lettore che l'Organizer sta masterizzando: per il launcher e' vuoto, e non lo interroga
        $burning = Get-BurningRoot
        if ($burning -and $burning.TrimEnd('\') -eq $Root.TrimEnd('\')) { return $null }
        $volume = Get-VolumeIdentity $Root
        if (-not $volume -or -not (Test-Path -LiteralPath $Root)) { return $null }
        $mf = Get-ManifestPath $Root
        if (-not (Test-Path -LiteralPath $mf)) { return "$volume|unknown" }
        $item = Get-Item -LiteralPath $mf
        return "$volume|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
    } catch { return $null }
}

function Find-Disc {
    foreach ($root in Get-DiscRoots) {
        $sig = Get-DiscSignature $root
        if (-not $sig) { continue }
        return [pscustomobject]@{
            Root      = $root
            Signature = $sig
            Label     = ($sig -split '\|')[0]
            Manifest  = Read-Manifest (Get-ManifestPath $root)
        }
    }
    return $null
}

# Il disco della sessione e' ancora nel lettore? Va bene anche un altro disco dello stesso gioco
# (giochi su piu' dischi): in quel caso restituisce quello. $null se il disco non c'e' piu'.
function Test-DiscStillHere($Disc) {
    $signature = Get-DiscSignature $Disc.Root
    if ($signature -eq $Disc.Signature) { return $Disc }
    if (-not $signature) { return $null }
    $now = Find-Disc
    if ($now -and $now.Manifest -and (Test-SameSet $now.Manifest $Disc.Manifest)) { return $now }
    return $null
}

# Espelle il disco e aspetta che sparisca davvero (max 15 s): senza questa attesa il launcher
# potrebbe "ritrovare" il disco appena espulso mentre il cassetto si sta ancora aprendo
function Invoke-Eject($Disc) {
    try {
        $item = (New-Object -ComObject Shell.Application).Namespace(17).ParseName($Disc.Root)
        if ($item) { $item.InvokeVerb('Eject') }
    } catch { }
    $until = (Get-Date).AddSeconds(15)
    $tick = 0
    while ((Get-Date) -lt $until -and (Get-DiscSignature $Disc.Root) -eq $Disc.Signature) {
        Write-Status ('[{0}] espulsione del disco...' -f $Spinner[$tick++ % 4]) $Theme.Accent
        Start-Sleep -Milliseconds 300
    }
    Write-Host ''
}

# Aspetta che il disco venga tolto/cambiato. Restituisce: removed | replay | eject | menu | quit
function Wait-DiscChange($Disc, [string]$Prompt, [switch]$AllowReplay) {
    Write-Host ''
    Write-Keys $Prompt
    $next = [datetime]::MinValue
    while ($true) {
        $key = Read-KeyNow
        if ($key) {
            if ($AllowReplay -and $key.Key -eq 'Enter') { return 'replay' }
            switch ("$($key.KeyChar)".ToUpper()) {
                'E' { Invoke-Eject $Disc; return 'eject' }
                'M' { return 'menu' }
                'Q' { return 'quit' }
            }
        }
        if ((Get-Date) -ge $next) {
            if ((Get-DiscSignature $Disc.Root) -ne $Disc.Signature) { return 'removed' }
            $next = (Get-Date).AddMilliseconds($PollMs)
        }
        Start-Sleep -Milliseconds 100
    }
}

# ---------------------------------------------------------------- schermata d'attesa

# Disco appena inserito: un paio di secondi di disco che gira mentre il lettore lo legge
function Show-DiscReading {
    Show-Screen 'lettura disco'
    Write-Host ''
    Start-DiscSpin
    Write-Host ''
    $until = (Get-Date).AddSeconds(2)
    $tick = 0
    while ((Get-Date) -lt $until) {
        Update-DiscSpin
        Write-Status ('                  [{0}]  lettura del disco in corso...' -f $Spinner[$tick++ % 4]) $Theme.Accent
        Start-Sleep -Milliseconds 50
    }
    Stop-DiscSpin
    Write-Host ''
}

# Restituisce il disco trovato, oppure 'menu' / 'quit'
function Wait-ForDisc {
    Show-Screen 'pronto'
    $roots = @(Get-DiscRoots)
    if ($roots.Count) { Write-Info "Lettori: $($roots -join '  ')" }
    else { Write-Alert 'Nessun lettore ottico trovato: collega il masterizzatore, resto in attesa.' }
    Write-Host ''
    Write-DiscFrame 0
    Write-Host ''
    Write-Keys '                       [M] menu principale   [Q] spegni'
    Write-Host ''

    $blink = $true
    $candidate = $null
    $nextPoll = [datetime]::MinValue
    $nextBlink = [datetime]::MinValue
    while ($true) {
        $key = Read-KeyNow
        if ($key -and "$($key.KeyChar)".ToUpper() -eq 'Q') { Write-Host ''; return 'quit' }
        if ($key -and "$($key.KeyChar)".ToUpper() -eq 'M') { Write-Host ''; return 'menu' }
        if ((Get-Date) -ge $nextBlink) {
            $color = if ($blink) { $Theme.Title } else { $Theme.Accent }
            Write-Status '                >>>   INSERISCI UN DISCO   <<<' $color
            $blink = -not $blink
            $nextBlink = (Get-Date).AddMilliseconds(600)
        }
        if ((Get-Date) -ge $nextPoll) {
            # Un disco conta solo se due letture di fila danno lo stesso risultato: mentre il
            # lettore lo carica (o Windows non ha ancora aggiornato i file) le letture cambiano
            $disc = Find-Disc
            if ($disc -and $candidate -and $disc.Root -eq $candidate.Root -and $disc.Signature -eq $candidate.Signature) {
                Write-Host ''
                Show-DiscReading
                return $disc
            }
            $candidate = $disc
            $nextPoll = (Get-Date).AddMilliseconds($PollMs)
        }
        Start-Sleep -Milliseconds 100
    }
}

# ---------------------------------------------------------------- libreria locale

function Get-GameHome($Manifest) { Join-Path $Library (Get-SafeName $Manifest.id) }

function Read-LibraryPath([string]$Current) {
    Write-Host ''
    while ($true) {
        $path = Read-Text "Nuova cartella di installazione (puoi trascinarla qui)   [INVIO] = lascia questa"
        if (-not $path) { return $Current }
        try {
            $full = [IO.Path]::GetFullPath($path)
            [void][IO.Directory]::CreateDirectory($full)
            return $full
        } catch {
            Write-Alert "Cartella non utilizzabile: $path"
        }
    }
}

# Propone la cartella di installazione dell'ultima volta; senza risposta dopo 10 s la usa
# (Sibyl puo' partire da solo con Windows, come una console)
function Select-Library {
    $current = Get-LibraryPath
    Show-Screen 'cartella di installazione'
    Write-Box @('*DOVE INSTALLARE I GIOCHI', $current, "Spazio libero: $(Get-FreeSpace $current)")
    Write-Host ''
    Write-Keys '[INVIO] usa questa   [C] cambia'
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $key = Read-KeyNow
        if ($key -and $key.Key -eq 'Enter') { break }
        if ($key -and "$($key.KeyChar)".ToUpper() -eq 'C') { $current = Read-LibraryPath $current; break }
        Write-Status ('Continuo con questa tra {0}...' -f [math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)) $Theme.Accent
        Start-Sleep -Milliseconds 100
    }
    Write-Host ''
    Set-ConfigValue 'library' $current
    return $current
}

function Read-State($Manifest) {
    $path = Join-Path (Get-GameHome $Manifest) 'state.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { return $null }
}

function Save-State($Manifest, $State) {
    Write-TextFile (Join-Path (Get-GameHome $Manifest) 'state.json') ($State | ConvertTo-Json)
}

# Byte letti da un processo e da tutti i suoi figli (l'installer GOG lavora in un figlio "setup.tmp")
function Get-ProcessTreeReadBytes([int]$RootId) {
    try { $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, ReadTransferCount) }
    catch { return 0L }
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    [void]$ids.Add($RootId)
    do {
        $added = $false
        foreach ($p in $all) {
            if ($ids.Contains([int]$p.ParentProcessId) -and $ids.Add([int]$p.ProcessId)) { $added = $true }
        }
    } while ($added)
    $total = 0L
    foreach ($p in $all) { if ($ids.Contains([int]$p.ProcessId)) { $total += [long]$p.ReadTransferCount } }
    return $total
}

# Barra di avanzamento stimata dai byte che il processo legge dal disco rispetto a quelli attesi
function Wait-WithProgress([Diagnostics.Process]$Process, [string]$Label, [long]$ExpectedBytes) {
    $start = Get-Date
    $tick = 0
    $nextMeasure = [datetime]::MinValue
    $percent = 0.0
    while (-not $Process.HasExited) {
        $elapsed = (Get-Date) - $start
        if ((Get-Date) -ge $nextMeasure) {
            $read = Get-ProcessTreeReadBytes $Process.Id
            # Nessun dato leggibile (es. permessi) dopo 10 s: barra indeterminata invece di uno 0% fermo
            $percent = if ($ExpectedBytes -le 0 -or ($read -eq 0 -and $elapsed.TotalSeconds -gt 10)) { -1 }
                       else { [math]::Max($percent, [math]::Min(99, 100.0 * $read / $ExpectedBytes)) }
            $nextMeasure = (Get-Date).AddSeconds(1)
        }
        $suffix = if ($percent -ge 3) {
            '~' + ([TimeSpan]::FromSeconds($elapsed.TotalSeconds * (100 - $percent) / $percent)).ToString('mm\:ss')
        } else {
            $elapsed.ToString('mm\:ss')
        }
        Write-ProgressBar $Label $percent $suffix ($tick++)
        Update-DiscSpin
        Start-Sleep -Milliseconds 100
    }
    Write-ProgressBar $Label 100 ((Get-Date) - $start).ToString('mm\:ss')
    Write-Host ''
}

# Codici di uscita di Inno Setup, il sistema su cui sono fatti gli installer GOG
$InstallerExitReasons = @{
    1 = "l'installer non e' riuscito ad avviarsi"
    2 = "installazione annullata prima di iniziare"
    3 = "errore grave durante la preparazione"
    4 = "errore grave durante l'installazione"
    5 = "installazione interrotta: di solito un file che non si riesce a leggere dal disco"
    6 = "l'installer e' stato chiuso forzatamente"
    7 = "l'installer ha stabilito che non puo' procedere"
    8 = "serve riavviare Windows prima di installare"
    -1073740771 = "l'installer si e' bloccato (crash della sua interfaccia grafica)"
    -1073741819 = "l'installer si e' bloccato (violazione di accesso)"
}

# Gli installer GOG a volte si bloccano DOPO aver finito (nella loro grafica personalizzata):
# conta quello che dice il log, non il codice di uscita
function Test-InstallLogSucceeded([string]$Log) {
    return (Test-Path -LiteralPath $Log) -and [bool](Select-String -LiteralPath $Log -Pattern 'Installation process succeeded' -SimpleMatch -Quiet)
}

# Le righe di errore dal log dell'installer (/LOG), senza data e ora
function Get-InstallLogErrors([string]$Log) {
    if (-not (Test-Path -LiteralPath $Log)) { return @() }
    return @(Get-Content -LiteralPath $Log |
        Where-Object {
            $_ -match 'error|abort|crc|failed|exception|cannot|unable|denied' -and
            # rumore normale degli installer GOG, presente anche quando tutto va bene
            $_ -notmatch 'Failed to import the DLL function|Extracting temporary file|Dest filename|DLL name'
        } |
        Select-Object -Last 5 |
        ForEach-Object { ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+\s+', '').Trim() })
}

# Dimensione di un installer GOG: il setup .exe piu' i suoi .bin (<nome>-1.bin, <nome>-2.bin, ...)
function Get-InstallerBytes([string]$Exe) {
    $base = [IO.Path]::GetFileNameWithoutExtension($Exe)
    $parts = @(Get-Item -LiteralPath $Exe) + @(Get-ChildItem -LiteralPath (Split-Path $Exe) -Filter "$base-*.bin" -File)
    return [long]($parts | Measure-Object -Property Length -Sum).Sum
}

# Avvia un installer. Inno Setup, NSIS e MSI si installano in silenzio nella cartella scelta da Sibyl;
# gli altri tipi (o con -ShowInstaller) si aprono con le loro finestre e l'utente sceglie dove.
function Start-Installer([string]$Exe, [string]$Type, [string]$Dir, [string]$Log) {
    $work = Split-Path $Exe
    if ($Type -eq 'inno') {
        $silent = if ($ShowInstaller) { '' } else { '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- ' }
        return Start-Process -FilePath $Exe -ArgumentList "$silent/LOG=`"$Log`" /DIR=`"$Dir`"" -WorkingDirectory $work -PassThru
    }
    if ($ShowInstaller -or $Type -notin 'nsis', 'msi') {
        Write-Info 'Segui l''installazione nella finestra dell''installer.'
        if ($Type -eq 'msi') { return Start-Process msiexec.exe -ArgumentList "/i `"$Exe`"" -PassThru }
        return Start-Process -FilePath $Exe -WorkingDirectory $work -PassThru
    }
    if ($Type -eq 'nsis') {
        # /D deve essere l'ultimo parametro e senza virgolette, anche con gli spazi
        return Start-Process -FilePath $Exe -ArgumentList "/S /D=$Dir" -WorkingDirectory $work -PassThru
    }
    return Start-Process msiexec.exe -PassThru -ArgumentList ("/i `"$Exe`" /qn /norestart /L*v `"$Log`" " +
        "INSTALLDIR=`"$Dir`" INSTALLLOCATION=`"$Dir`" TARGETDIR=`"$Dir`"")
}

# Se l'installer ha scelto da solo la cartella (o non si sa dove abbia installato), si chiede all'utente
function Read-InstallDir {
    Write-Host ''
    Write-Alert "Non so in quale cartella e' stato installato il gioco."
    while ($true) {
        $path = Read-Text 'Cartella in cui e'' stato installato (puoi trascinarla qui)'
        if (-not $path) { throw 'Installazione non completata: cartella del gioco sconosciuta' }
        if (Test-Path -LiteralPath $path -PathType Container) { return (Resolve-Path -LiteralPath $path).ProviderPath }
        Write-Alert "Cartella non trovata: $path"
    }
}

# Copia i file di un disco ($Disc) nella cartella $Target, con la barra di avanzamento
function Copy-DiscFiles($Disc, [string]$Target) {
    $n = Get-DiscNumber $Disc.Manifest
    $files = @($Disc.Manifest.files | Where-Object { (Get-FileDisc $_) -eq $n })
    $total = [long]($files | ForEach-Object { [long]$_.size } | Measure-Object -Sum).Sum
    $done = 0L
    $start = Get-Date
    $label = "Copia disco $n/$(Get-DiscCount $Disc.Manifest)"
    $buffer = New-Object byte[] (1MB)
    foreach ($f in $files) {
        $from = Join-Path $Disc.Root ($f.path -replace '/', '\')
        $to = Join-Path $Target ($f.path -replace '/', '\')
        [void][IO.Directory]::CreateDirectory((Split-Path $to))
        $in = [IO.File]::OpenRead($from)
        $out = [IO.File]::Create($to)
        try {
            while (($read = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $out.Write($buffer, 0, $read)
                $done += $read
                Write-ProgressBar $label (100.0 * $done / [math]::Max(1, $total)) ((Get-Date) - $start).ToString('mm\:ss')
                Update-DiscSpin
            }
        } finally { $in.Dispose(); $out.Dispose() }
    }
    Write-ProgressBar $label 100 ((Get-Date) - $start).ToString('mm\:ss')
    Write-Host ''
}

# Gioco su piu' dischi: aspetta un disco della stessa serie tra quelli che mancano (in qualsiasi
# ordine). Restituisce il disco, oppure $null se l'utente annulla con [A].
function Wait-NextDisc($Manifest, [int[]]$Missing) {
    Show-Screen 'cambio disco'
    $count = Get-DiscCount $Manifest
    Write-Box @(
        ''
        "*  $($Manifest.title.ToUpper())"
        ''
        "  Inserisci il disco $($Missing[0]) di $count"
        "  Dischi mancanti: $($Missing -join ', ')"
        ''
    )
    Write-Host ''
    Write-Keys '[A] annulla l''installazione'
    Write-Host ''
    $candidate = $null
    $next = [datetime]::MinValue
    $tick = 0
    $message = 'In attesa del disco...'
    while ($true) {
        $key = Read-KeyNow
        if ($key -and "$($key.KeyChar)".ToUpper() -eq 'A') { Write-Host ''; return $null }
        if ((Get-Date) -ge $next) {
            $disc = Find-Disc
            if ($disc -and $disc.Manifest -and (Test-SameSet $disc.Manifest $Manifest)) {
                $n = Get-DiscNumber $disc.Manifest
                if ($Missing -contains $n) {
                    # Come all'inserimento normale: due letture uguali di fila prima di fidarsi
                    if ($candidate -and $candidate.Signature -eq $disc.Signature) { Write-Host ''; return $disc }
                    $candidate = $disc
                } else {
                    $message = "Il disco $n e' gia' stato copiato: serve il disco $($Missing[0])"
                }
            } elseif ($disc) {
                $message = "Questo disco non fa parte di $($Manifest.title)"
                $candidate = $null
            } else {
                $message = 'In attesa del disco...'
                $candidate = $null
            }
            $next = (Get-Date).AddMilliseconds($PollMs)
        }
        Write-Status ('[{0}] {1}' -f $Spinner[$tick++ % 4], (T $message)) $Theme.Accent
        Start-Sleep -Milliseconds 150
    }
}

# Copia sul PC tutti i dischi di un gioco su piu' dischi, partendo da quello inserito.
# Restituisce l'ultimo disco inserito (ancora nel lettore), oppure $null se annullato.
function Copy-DiscSet($Disc, [string]$Staging) {
    $m = $Disc.Manifest
    $count = Get-DiscCount $m
    $copied = @{}
    if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
    [void][IO.Directory]::CreateDirectory($Staging)
    $current = $Disc
    while ($true) {
        Show-Screen 'installazione'
        Write-Info "$($m.title) e' su $count dischi: vengono copiati sul PC, poi si installa."
        Write-Host ''
        Start-DiscSpin
        Write-Host ''
        Copy-DiscFiles $current $Staging
        Stop-DiscSpin
        $copied[(Get-DiscNumber $current.Manifest)] = $true
        $missing = @(1..$count | Where-Object { -not $copied.ContainsKey($_) })
        if (-not $missing.Count) { return $current }
        Invoke-Eject $current
        $current = Wait-NextDisc $m $missing
        if (-not $current) { return $null }
    }
}

# Installa il gioco dal disco o, per i giochi su piu' dischi, dalla cartella $SourceRoot in cui sono
# stati copiati. Le voci di "App installate" prima e dopo dicono dove e' finito, l'exe e come si disinstalla.
function Install-Game($Disc, [string]$SourceRoot) {
    $m = $Disc.Manifest
    $gameHome = Get-GameHome $m
    $dir = Join-Path $gameHome 'game'
    [void][IO.Directory]::CreateDirectory($dir)
    Start-DiscSpin   # gira sopra le barre finche' l'installer legge dal disco
    Write-Host ''
    $entry = $null

    if ((Get-Prop $m 'mode') -eq 'portable') {
        # Gioco gia' installato sul disco, nella cartella Game\: si copia in locale
        $src = Join-Path $SourceRoot 'Game'
        if (-not (Test-Path -LiteralPath $src)) { throw "Modalita' portable ma sul disco manca la cartella Game\" }
        $bytes = [long](Get-ChildItem -LiteralPath $src -File -Recurse | Measure-Object -Property Length -Sum).Sum
        $p = Start-Process robocopy -ArgumentList "`"$src`" `"$dir`" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP" -WindowStyle Hidden -PassThru
        $null = $p.Handle   # senza questo ExitCode resta vuoto
        Wait-WithProgress $p 'Copia dal disco' $bytes
        if ($p.ExitCode -ge 8) { throw "Copia fallita (robocopy $($p.ExitCode))" }
    } else {
        $installers = @(Get-Prop $m 'installer') + @($m.files | Where-Object { $_.category -eq 'DLC' -and $_.path -like '*.exe' } |
            ForEach-Object { $_.path })
        $installers = @($installers | Where-Object { $_ })
        if (-not $installers.Count) { throw 'Il manifest non indica nessun installer' }
        $type = Get-Prop $m 'installerType'
        if (-not $type) { $type = 'inno' }   # dischi GOG preparati prima che il manifest lo dicesse
        $interactive = $ShowInstaller -or $type -notin 'inno', 'nsis', 'msi'
        $before = @(Get-UninstallEntries | ForEach-Object { $_.Key })

        for ($n = 0; $n -lt $installers.Count; $n++) {
            $rel = $installers[$n]
            $exe = Join-Path $SourceRoot ($rel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $exe)) { throw "Installer mancante sul disco: $rel" }
            $label = if ($installers.Count -gt 1) { "Installazione $($n + 1)/$($installers.Count)" } else { 'Installazione' }
            Write-Info (Split-Path -Leaf $exe)
            $log = Join-Path $gameHome ("install-{0}.log" -f ($n + 1))
            Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
            # I DLC dei giochi GOG sono Inno Setup come il gioco
            $p = Start-Installer $exe $(if ($n -gt 0) { 'inno' } else { $type }) $dir $log
            $null = $p.Handle
            Wait-WithProgress $p $label (Get-InstallerBytes $exe)
            if ($type -eq 'msi' -and $p.ExitCode -notin 0, 1641, 3010) {
                Write-Host ''
                Write-Alert "Installazione fallita (codice $($p.ExitCode)): $(T 'errore sconosciuto')"
                Write-Info "Log completo: $log"
                throw "Installazione di $(Split-Path -Leaf $exe) non completata"
            }
            if ($type -eq 'nsis' -and -not $interactive -and $p.ExitCode -ne 0) {
                throw "Installazione di $(Split-Path -Leaf $exe) non completata"
            }
            if ($type -ne 'inno') { continue }
            if ($p.ExitCode -ne 0 -and (Test-InstallLogSucceeded $log)) {
                Write-Info "L'installer si e' chiuso con un errore (codice $($p.ExitCode)) ma il suo log dice che l'installazione e' riuscita."
            } elseif ($p.ExitCode -ne 0) {
                $reason = $InstallerExitReasons[[int]$p.ExitCode]
                if (-not $reason) { $reason = "errore sconosciuto" }
                Write-Host ''
                Write-Alert "Installazione fallita (codice $($p.ExitCode)): $reason"
                $details = @(Get-InstallLogErrors $log)
                if ($details.Count) {
                    Write-Info 'Dal log dell''installer:'
                    $details | ForEach-Object { Write-Info "  $_" }
                }
                Write-Info "Log completo: $log"
                if ($p.ExitCode -eq 5) { Write-Info 'Premi [V] sulla schermata del disco per controllare se e'' leggibile.' }
                throw "Installazione di $(Split-Path -Leaf $exe) non completata"
            }
        }

        # La voce nuova in "App installate": quella nella cartella di Sibyl, o col nome del gioco, o l'unica
        $new = @(Get-UninstallEntries | Where-Object { $before -notcontains $_.Key })
        $entry = $new | Where-Object { $_.InstallLocation -and $_.InstallLocation.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if (-not $entry) {
            $word = ($m.title -split '\W+' | Where-Object { $_.Length -gt 2 } | Select-Object -First 1)
            if ($word) { $entry = $new | Where-Object { $_.Name -and $_.Name -like "*$word*" } | Select-Object -First 1 }
        }
        if (-not $entry -and $new.Count -eq 1) { $entry = $new[0] }

        # Installer con le finestre, o cartella di Sibyl rimasta vuota: il gioco e' altrove, lo dice il registro
        if ($interactive -or -not (Get-ChildItem -LiteralPath $dir -Force | Select-Object -First 1)) {
            $location = $null
            if ($entry) {
                $location = $entry.InstallLocation
                if (-not $location) { $icon = Get-ExeFromIcon $entry.DisplayIcon; if ($icon) { $location = Split-Path $icon } }
            }
            if ($location -and (Test-Path -LiteralPath $location)) { $dir = $location.TrimEnd('\') }
            else { Stop-DiscSpin; $dir = Read-InstallDir }
        }
    }

    Stop-DiscSpin
    $old = Read-State $m
    $state = [pscustomobject]@{
        id              = $m.id
        title           = $m.title
        version         = $m.version
        build           = $m.build
        installDir      = $dir
        installedAt     = (Get-Date).ToString('s')
        playSeconds     = $(if ($old) { [long](Get-Prop $old 'playSeconds') } else { 0 })
        lastPlayed      = $(if ($old) { Get-Prop $old 'lastPlayed' } else { '' })
        launchExe       = $(if ($old) { Get-Prop $old 'launchExe' } else { '' })
        displayIcon     = $(if ($entry) { Get-ExeFromIcon $entry.DisplayIcon } else { '' })
        uninstallString = $(if ($entry) { $entry.Uninstall } else { '' })
        quietUninstall  = $(if ($entry) { $entry.QuietUninstall } else { '' })
    }
    Save-State $m $state
    return $state
}

# Quale exe avvia il gioco, chiesto all'utente quando non si riesce a capirlo da soli
function Select-LaunchExe([string]$Dir, $Candidates) {
    Write-Host ''
    Write-Step 'Quale di questi file avvia il gioco?'
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        Write-Host ('   [{0}]  ' -f ($i + 1)) -ForegroundColor $Theme.Accent -NoNewline
        Write-Host $Candidates[$i].FullName.Substring($Dir.TrimEnd('\').Length + 1) -ForegroundColor $Theme.Text
    }
    while ($true) {
        $answer = Read-Answer 'Numero   [INVIO] = 1'
        if (-not $answer) { return $Candidates[0].FullName }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Candidates.Count) { return $Candidates[$n - 1].FullName }
        Write-Alert "Scrivi un numero da 1 a $($Candidates.Count)"
    }
}

# Ordine: launch del manifest (scelta manuale) > exe scelto la volta scorsa > goggame-*.info di GOG >
# icona registrata dall'installer > unico exe adatto > domanda all'utente (la risposta resta in $State)
function Resolve-LaunchTarget($Manifest, $State) {
    $Dir = $State.installDir
    $launch = Get-Prop $Manifest 'launch'
    if ((Get-Prop $launch 'exe')) {
        $wd = Get-Prop $launch 'workingDir'
        return [pscustomobject]@{
            Exe        = Join-Path $Dir $launch.exe
            Args       = Get-Prop $launch 'args'
            WorkingDir = $(if ($wd) { Join-Path $Dir $wd } else { '' })
        }
    }

    $saved = Get-Prop $State 'launchExe'
    if ($saved -and (Test-Path -LiteralPath $saved)) { return [pscustomobject]@{ Exe = $saved; Args = ''; WorkingDir = '' } }

    foreach ($info in Get-ChildItem -LiteralPath $Dir -Filter 'goggame-*.info' -File -ErrorAction SilentlyContinue) {
        $json = Read-Manifest $info.FullName
        $task = @(Get-Prop $json 'playTasks') | Where-Object {
            $_ -and (Get-Prop $_ 'isPrimary') -and (Get-Prop $_ 'type') -eq 'FileTask'
        } | Select-Object -First 1
        if (-not $task) { continue }
        $wd = Get-Prop $task 'workingDir'
        return [pscustomobject]@{
            Exe        = Join-Path $Dir $task.path
            Args       = Get-Prop $task 'arguments'
            WorkingDir = $(if ($wd) { Join-Path $Dir $wd } else { '' })
        }
    }

    $icon = Get-Prop $State 'displayIcon'
    if ($icon -and (Test-Path -LiteralPath $icon) -and (Split-Path -Leaf $icon) -notmatch '^(unins|uninst)') {
        return [pscustomobject]@{ Exe = $icon; Args = ''; WorkingDir = '' }
    }

    $candidates = @(Get-ChildItem -LiteralPath $Dir -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(unins|uninst|setup|dxsetup|vc_?redist|dotnet|oalinst|crash|ue4prereq|directx)' } |
        Sort-Object Length -Descending | Select-Object -First 9)
    if (-not $candidates.Count) { return $null }
    $exe = if ($candidates.Count -eq 1) { $candidates[0].FullName } else { Select-LaunchExe $Dir $candidates }
    $State | Add-Member -NotePropertyName launchExe -NotePropertyValue $exe -Force
    return [pscustomobject]@{ Exe = $exe; Args = ''; WorkingDir = '' }
}

function Start-Game($Target, [string]$Dir) {
    $wd = if ($Target.WorkingDir) { $Target.WorkingDir } else { Split-Path $Target.Exe }
    $params = @{ FilePath = $Target.Exe; WorkingDirectory = $wd; PassThru = $true }
    if ($Target.Args) { $params.ArgumentList = $Target.Args }
    $p = Start-Process @params

    # Molti giochi passano da un launcher che si chiude subito: la partita dura finche'
    # resta vivo un qualsiasi processo avviato dalla cartella del gioco.
    $prefix = $Dir.TrimEnd('\') + '\'
    $start = Get-Date
    $i = 0
    while ($true) {
        $elapsed = (Get-Date) - $start
        Write-Status ('[{0}] IN GIOCO   {1:hh\:mm\:ss}      chiudi il gioco per tornare qui' -f $Spinner[$i++ % 4], $elapsed) $Theme.Accent
        Start-Sleep -Seconds 1
        if (-not $p.HasExited -or $elapsed.TotalSeconds -lt 5) { continue }
        $alive = @(Get-Process | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
        })
        if (-not $alive.Count) { break }
    }
    Write-Host ''
    return (Get-Date) - $start
}

# ---------------------------------------------------------------- verifica disco

function Test-Disc($Disc) {
    Show-Screen 'verifica disco'
    $bad = @(Test-DiscWithProgress $Disc.Root $Disc.Manifest)
    Write-Host ''
    if ($bad.Count) {
        Write-Alert "$($bad.Count) file con problemi:"
        $bad | ForEach-Object { Write-Info $_ }
    } else {
        $n = Get-DiscNumber $Disc.Manifest
        Write-Ok "Disco integro: $(@($Disc.Manifest.files | Where-Object { (Get-FileDisc $_) -eq $n }).Count) file verificati"
    }
    Write-Host ''
    Write-Keys '[un tasto qualsiasi] torna al disco'
    $until = (Get-Date).AddSeconds(30)
    while (-not (Read-KeyNow) -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 100 }
}

# ---------------------------------------------------------------- sessione con un disco

function Show-Card($Disc, $State) {
    $m = $Disc.Manifest
    Show-Screen 'disco inserito'
    $status = if (-not $State) { 'DA INSTALLARE' }
              elseif ($State.version -ne $m.version) { "AGGIORNAMENTO: $($State.version) -> $($m.version)" }
              else { 'INSTALLATO' }
    $played = if ($State -and (Get-Prop $State 'playSeconds')) { Format-Duration ([TimeSpan]::FromSeconds($State.playSeconds)) } else { '-' }
    $lines = @(
        ''
        "*  $($m.title.ToUpper())"
        ''
        "  Versione     : $(if ($m.version) { $m.version } else { '?' })"
        "  Lettore      : $($Disc.Root)   (disco: $($Disc.Label))"
    )
    if ((Get-DiscCount $m) -gt 1) { $lines += "  Disco        : $(Get-DiscNumber $m) di $(Get-DiscCount $m)" }
    $lines += @("  Stato        : $status", "  Tempo giocato: $played", '')
    Write-Box $lines
    Write-Host ''
    Write-Keys '[INVIO] gioca   [V] verifica disco   [R] reinstalla   [U] disinstalla'
    Write-Keys '[E] espelli   [M] menu principale   [Q] spegni'
    Write-Host ''
}

# Restituisce: play | verify | reinstall | eject | menu | quit | removed
function Read-Choice($Disc, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $nextPoll = (Get-Date).AddMilliseconds($PollMs)
    while ($true) {
        $key = Read-KeyNow
        if ($key) {
            if ($key.Key -eq 'Enter') { Write-Host ''; return 'play' }
            switch ("$($key.KeyChar)".ToUpper()) {
                'V' { return 'verify' }
                'R' { return 'reinstall' }
                'E' { return 'eject' }
                'U' { return 'uninstall' }
                'M' { return 'menu' }
                'Q' { return 'quit' }
            }
        }
        $left = [math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($left -le 0) { Write-Host ''; return 'play' }
        Write-Status "Avvio tra $left..." $Theme.Accent
        if ((Get-Date) -ge $nextPoll) {
            if ((Get-DiscSignature $Disc.Root) -ne $Disc.Signature) { Write-Host ''; return 'removed' }
            $nextPoll = (Get-Date).AddMilliseconds($PollMs)
        }
        Start-Sleep -Milliseconds 100
    }
}

# Restituisce 'menu' o 'quit' se si lascia il launcher, '' se si torna ad aspettare un disco
function Invoke-DiscSession($Disc) {
    $m = $Disc.Manifest
    $wait = $Countdown
    while ($true) {
        $state = Read-State $m
        Show-Card $Disc $state
        $choice = Read-Choice $Disc $wait
        $wait = $Countdown

        if ($choice -in 'quit', 'menu') { return $choice }
        if ($choice -eq 'removed') { return '' }
        if ($choice -eq 'eject') { Invoke-Eject $Disc; return '' }
        if ($choice -eq 'verify') { Test-Disc $Disc; continue }
        if ($choice -eq 'uninstall') {
            Show-Screen 'disinstallazione'
            if ($state) { [void](Invoke-UninstallScreen $m.title (Get-GameHome $m) $state $Library) }
            else { Write-Alert "$($m.title) non e' installato."; Start-Sleep -Seconds 2 }
            continue
        }

        # Si installa e si gioca solo se nel lettore c'e' ancora questo disco, o un altro dello stesso
        # gioco (dopo "gioca ancora" o con il conto alla rovescia a zero il disco potrebbe essere cambiato)
        $here = Test-DiscStillHere $Disc
        if (-not $here) {
            Write-Host ''
            Write-Alert "Nel lettore non c'e' piu' il disco di $($m.title): non lo avvio."
            Start-Sleep -Seconds 3
            return ''
        }
        $Disc = $here

        $staging = $null
        try {
            if ($choice -eq 'reinstall' -or -not $state -or $state.version -ne $m.version -or
                -not (Test-Path -LiteralPath $state.installDir)) {
                $source = $Disc.Root
                if ((Get-DiscCount $m) -gt 1) {
                    # Gioco su piu' dischi: prima si copiano tutti sul PC, poi si installa da li'
                    $staging = Join-Path (Get-GameHome $m) '_dischi'
                    $last = Copy-DiscSet $Disc $staging
                    if (-not $last) {
                        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Info 'Installazione annullata.'
                        Start-Sleep -Seconds 2
                        return ''
                    }
                    $Disc = $last
                    $source = $staging
                }
                Show-Screen 'installazione'
                Write-Info "$($m.title) viene installato in $(Get-GameHome $m)"
                Write-Info 'Solo al primo inserimento: le volte successive parte subito.'
                Write-Host ''
                $state = Install-Game $Disc $source
                Write-Ok 'Installazione completata'
            }
            $target = Resolve-LaunchTarget $m $state
            if (-not $target -or -not (Test-Path -LiteralPath $target.Exe)) {
                throw "Non trovo l'eseguibile del gioco. Indicalo in launch.exe dentro $ManifestName"
            }
            Save-State $m $state   # ricorda l'exe scelto
        } catch {
            Write-Host ''
            Write-Alert $_.Exception.Message
            if ($Once) { return 'quit' }
            $r = Wait-DiscChange $Disc '[INVIO] riprova   [E] espelli   [M] menu principale   [Q] spegni' -AllowReplay
            if ($r -in 'quit', 'menu') { return $r }
            if ($r -eq 'replay') { continue }
            return ''
        } finally {
            # La copia dei dischi serve solo all'installazione
            if ($staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
        }

        Show-Screen 'in gioco'
        Write-Box @('', "*  $($m.title.ToUpper())", '', "  $(Split-Path -Leaf $target.Exe)", '') $Theme.Accent
        Write-Host ''
        $session = Start-Game $target $state.installDir

        $state.playSeconds = [long](Get-Prop $state 'playSeconds') + [long]$session.TotalSeconds
        $state.lastPlayed = (Get-Date).ToString('s')
        Save-State $m $state

        Show-Screen 'partita terminata'
        Write-Box @(
            ''
            "*  $($m.title.ToUpper())"
            ''
            "  Questa sessione: $(Format-Duration $session)"
            "  Tempo totale   : $(Format-Duration ([TimeSpan]::FromSeconds($state.playSeconds)))"
            ''
        )
        if ($Once) { return 'quit' }
        $r = Wait-DiscChange $Disc '[INVIO] gioca ancora   [E] espelli   [M] menu   [Q] spegni   (o cambia disco)' -AllowReplay
        if ($r -in 'quit', 'menu') { return $r }
        if ($r -ne 'replay') { return '' }
        $wait = 0
    }
}

# ================================================================ MAIN

# Permette di caricare le funzioni con ". .\SibylLauncher.ps1" senza avviare la console
if ($MyInvocation.InvocationName -eq '.') { return }

if ($Autostart) {
    Write-Banner 'avvio automatico' 'Launcher'
    Set-Autostart ($Autostart -eq 'On')
    if ($Autostart -eq 'On') { Write-Ok 'Il launcher partira'' a ogni accesso a Windows' }
    else { Write-Ok 'Il launcher non partira'' piu'' all''accesso a Windows' }
    return
}

if (-not $Library) { $Library = Select-Library }
[void][IO.Directory]::CreateDirectory($Library)

$action = 'quit'
while ($true) {
    $disc = Wait-ForDisc
    if ($disc -is [string]) { $action = $disc; break }

    if (-not $disc.Manifest) {
        Show-Screen 'disco non riconosciuto'
        Write-Alert "Il disco in $($disc.Root) non e' un disco Sibyl (manca $ManifestName)."
        Write-Info 'Prepara i giochi con l''Organizzatore prima di masterizzarli.'
        $r = Wait-DiscChange $disc '[E] espelli   [M] menu principale   [Q] spegni'
        if ($r -in 'quit', 'menu') { $action = $r; break }
        continue
    }

    $r = Invoke-DiscSession $disc
    if ($r) { $action = $r; break }
    if ($Once) { break }
}

if ($action -eq 'menu') { Exit-ToMenu $FromMenu }
Show-Screen 'spegnimento'
Write-Host ('                     ' + (T 'Grazie per aver giocato. A presto!')) -ForegroundColor $Theme.Title
Write-Host ''
Exit-QuitAll $FromMenu
