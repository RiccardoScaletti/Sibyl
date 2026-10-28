# Sibyl :: masterizzazione con IMAPI2, il motore di masterizzazione integrato in Windows

# IMAPI_MEDIA_PHYSICAL_TYPE
$MediaTypeNames = @{
    1 = 'CD-ROM'; 2 = 'CD-R'; 3 = 'CD-RW'; 4 = 'DVD-ROM'; 5 = 'DVD-RAM'; 6 = 'DVD+R'; 7 = 'DVD+RW'
    8 = 'DVD+R DL'; 9 = 'DVD-R'; 10 = 'DVD-RW'; 11 = 'DVD-R DL'; 13 = 'DVD+RW DL'
    17 = 'BD-ROM'; 18 = 'BD-R'; 19 = 'BD-RE'
}
# Capacita' nominale dei riscrivibili, per i dischi usati (IMAPI non la riporta finche' non sono cancellati)
$RewritableCapacity = @{ 3 = 737280000; 7 = 4700372992; 10 = 4700372992; 13 = 8543666176; 19 = 25025314816 }

function Get-Burners {
    try { $master = New-Object -ComObject IMAPI2.MsftDiscMaster2 } catch { return @() }
    if (-not $master.IsSupportedEnvironment) { return @() }
    $burners = for ($i = 0; $i -lt $master.Count; $i++) {
        try {
            $rec = New-Object -ComObject IMAPI2.MsftDiscRecorder2
            $rec.InitializeDiscRecorder($master.Item($i))
            $paths = @($rec.VolumePathNames)
            $fmt = New-Object -ComObject IMAPI2.MsftDiscFormat2Data
            [pscustomobject]@{
                Id       = $rec.ActiveDiscRecorder
                Root     = $(if ($paths.Count) { [string]$paths[0] } else { '' })
                Name     = ('{0} {1}' -f $rec.VendorId, $rec.ProductId).Trim() -replace '\s+', ' '
                CanWrite = [bool]$fmt.IsRecorderSupported($rec)
                Recorder = $rec
            }
        } catch { }
    }
    return @($burners)
}

# State: empty | blank | erasable | used | unsupported
function Get-MediaState($Burner) {
    $fmt = New-Object -ComObject IMAPI2.MsftDiscFormat2Data
    $fmt.Recorder = $Burner.Recorder
    try { $type = [int]$fmt.CurrentPhysicalMediaType }
    catch { return [pscustomobject]@{ State = 'empty'; Name = ''; Capacity = 0L } }

    $name = $MediaTypeNames[$type]
    if (-not $name) { $name = "tipo $type" }
    $state = [pscustomobject]@{ State = 'unsupported'; Name = $name; Capacity = 0L }

    $supported = $false
    try { $supported = [bool]$fmt.IsCurrentMediaSupported($Burner.Recorder) } catch { }
    $blank = $false
    if ($supported) { try { $blank = [bool]$fmt.MediaHeuristicallyBlank } catch { } }

    if ($blank) {
        $state.State = 'blank'
        $state.Capacity = [long]$fmt.FreeSectorsOnMedia * 2048
    } elseif ($RewritableCapacity.ContainsKey($type)) {
        $state.State = 'erasable'
        $total = 0L
        try { $total = [long]$fmt.TotalSectorsOnMedia * 2048 } catch { }
        $state.Capacity = [math]::Max($total, [long]$RewritableCapacity[$type])
    } elseif ($supported) {
        $state.State = 'used'
    }
    return $state
}

function Get-VolumeLabel([string]$Title) {
    $label = ($Title.ToUpper() -replace '[^A-Z0-9]+', '_').Trim('_')
    if ($label.Length -gt 15) { $label = $label.Substring(0, 15).TrimEnd('_') }
    if (-not $label) { $label = 'SIBYL' }
    return $label
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Scrive il CONTENUTO di $Folder nella radice del disco (UDF, disco chiuso).
# La scrittura gira in Sibyl.BurnWorker.ps1, con i permessi di amministratore chiesti
# solo adesso (UAC); qui si legge il suo file di stato e si disegna la barra.
function Invoke-Burn($Burner, [string]$Folder, [string]$Label, [bool]$Erase) {
    $work = Join-Path $env:TEMP ('Sibyl-burn-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($work)
    $jobPath = Join-Path $work 'job.json'
    $statusPath = Join-Path $work 'status.json'
    Write-TextFile $jobPath (@{ RecorderId = $Burner.Id; Folder = $Folder; Label = $Label; Erase = $Erase; StatusPath = $statusPath } | ConvertTo-Json)

    $worker = Join-Path $PSScriptRoot 'Sibyl.BurnWorker.ps1'
    $params = @{
        FilePath     = 'powershell.exe'
        ArgumentList = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Job "{1}"' -f $worker, $jobPath
        WindowStyle  = 'Hidden'
        PassThru     = $true
    }
    if (-not (Test-IsAdmin)) {
        $params.Verb = 'RunAs'
        Write-Info "Windows chiedera' i permessi di amministratore: servono solo per scrivere il disco."
    }
    Set-BurnMarker $Burner.Root   # un Launcher aperto lascia stare il lettore fino alla fine
    try {
        try { $process = Start-Process @params }
        catch { throw 'Permessi di amministratore negati: senza non si puo'' scrivere il disco' }

        $state = $null
        $tick = 0
        $start = Get-Date
        while ($true) {
            try { $state = [IO.File]::ReadAllText($statusPath) | ConvertFrom-Json } catch { }
            if (($state -and $state.done) -or $process.HasExited) { break }
            $phase = if ($state) { $state.phase } else { 'Avvio' }
            $percent = if ($state) { [double]$state.percent } else { -1 }
            $suffix = if ($state -and $state.remaining -gt 0) {
                '~' + ([TimeSpan]::FromSeconds($state.remaining)).ToString('mm\:ss')
            } else {
                ((Get-Date) - $start).ToString('mm\:ss')
            }
            Write-ProgressBar $phase $percent $suffix ($tick++)
            Start-Sleep -Milliseconds 250
        }
        Start-Sleep -Milliseconds 300
        try { $state = [IO.File]::ReadAllText($statusPath) | ConvertFrom-Json } catch { }
    } finally {
        Clear-BurnMarker
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $state -or -not $state.done) { Write-Host ''; throw 'Il processo di masterizzazione si e'' interrotto' }
    if ($state.error) { Write-Host ''; throw $state.error }
    Write-ProgressBar 'Masterizzazione' 100 ((Get-Date) - $start).ToString('mm\:ss')
    Write-Host ''
}
