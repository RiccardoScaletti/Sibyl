<#
.SYNOPSIS
    Crea dist\Sibyl.exe: un solo file che contiene tutti gli script di Sibyl.

.DESCRIPTION
    Compila Sibyl.Exe.cs con il compilatore C# gia' presente in Windows (.NET Framework 4),
    incorporando gli script come risorse e Sibyl.ico come icona (creata la prima volta).
    Rilancialo dopo ogni modifica agli script: l'exe nuovo estrae da solo la versione aggiornata.

.EXAMPLE
    .\Build-SibylExe.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Sibyl.Common.ps1')

$Scripts = @(
    'Sibyl.ps1'
    'SibylLauncher.ps1'
    'Organize-GogGames.ps1'
    'Sibyl.Common.ps1'
    'Sibyl.Lang.ps1'
    'Sibyl.Burn.ps1'
    'Sibyl.BurnWorker.ps1'
)

# Icona: un disco come quello animato nel launcher, in piu' dimensioni (PNG dentro un .ico)
function New-DiscIcon([string]$Path) {
    Add-Type -AssemblyName System.Drawing
    $images = foreach ($size in 256, 64, 48, 32, 16) {
        $bmp = New-Object Drawing.Bitmap $size, $size
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'
        $g.Clear([Drawing.Color]::Transparent)
        $c = $size / 2
        $circle = { param($ratio) $r = $c * $ratio; New-Object Drawing.RectangleF ($c - $r), ($c - $r), (2 * $r), (2 * $r) }

        $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 16, 32, 48))), (& $circle 0.96))
        foreach ($ratio in 0.85, 0.74, 0.63, 0.52) {
            $g.DrawEllipse((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(70, 0, 188, 212)), ([math]::Max(1, $size / 128))), (& $circle $ratio))
        }
        # i due riflessi di luce, come nell'animazione
        $s = & $circle 0.93
        $g.FillPie((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(150, 255, 255, 255))), $s.X, $s.Y, $s.Width, $s.Height, 200, 40)
        $g.FillPie((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(130, 200, 80, 220))), $s.X, $s.Y, $s.Width, $s.Height, 20, 40)
        $g.DrawEllipse((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 0, 188, 212)), ([math]::Max(1, $size / 32))), (& $circle 0.95))
        $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 60, 90, 110))), (& $circle 0.38))
        $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 176, 64, 192))), (& $circle 0.28))
        $g.CompositingMode = 'SourceCopy'
        $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::Transparent)), (& $circle 0.12))
        $g.Dispose()

        $stream = New-Object IO.MemoryStream
        $bmp.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        , @{ Size = $size; Bytes = $stream.ToArray() }
    }

    $out = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $out
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$images.Count)   # ICONDIR
    $offset = 6 + 16 * $images.Count
    foreach ($img in $images) {                                                  # ICONDIRENTRY
        $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
        $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$img.Bytes.Length); $w.Write([uint32]$offset)
        $offset += $img.Bytes.Length
    }
    foreach ($img in $images) { $w.Write($img.Bytes) }
    $w.Flush()
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

Write-Banner 'build :: Sibyl.exe'

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path -LiteralPath $csc)) { Write-Alert 'Compilatore C# del .NET Framework 4 non trovato'; exit 1 }

$icon = Join-Path $PSScriptRoot 'Sibyl.ico'
if (-not (Test-Path -LiteralPath $icon)) {
    Write-Step 'Creo l''icona Sibyl.ico'
    New-DiscIcon $icon
}

# Build id = impronta degli script: cambia solo se cambia il codice
$hashes = foreach ($s in $Scripts) { (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $s) -Algorithm SHA256).Hash }
$sha = [Security.Cryptography.SHA256]::Create()
$buildId = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes(($hashes -join '')))) -replace '-', '').Substring(0, 12).ToLower()
Write-Info "Build: $buildId"

$work = Join-Path $env:TEMP 'Sibyl-build'
[void][IO.Directory]::CreateDirectory($work)
$source = Join-Path $work 'Sibyl.Exe.cs'
# Versione di Sibyl.Common.ps1 (es. 1.1) nel formato a quattro numeri delle proprieta' dell'exe: 1.1.0.0
$assemblyVersion = (("$SibylVersion.0.0.0" -split '\.')[0..3]) -join '.'
Write-Info "Versione: $SibylVersion"
$code = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sibyl.Exe.cs'))
Write-TextFile $source $code.Replace('@BUILD_ID@', $buildId).Replace('@VERSION@', $assemblyVersion)

$dist = Join-Path $PSScriptRoot 'dist'
[void][IO.Directory]::CreateDirectory($dist)
$exe = Join-Path $dist 'Sibyl.exe'

# winexe: l'exe non apre una console sua, apre direttamente la console classica di Sibyl
$cscArgs = @('/nologo', '/target:winexe', '/optimize+', '/reference:System.Windows.Forms.dll', "/out:$exe", "/win32icon:$icon")
$cscArgs += $Scripts | ForEach-Object { "/resource:$(Join-Path $PSScriptRoot $_),app/$_" }
$cscArgs += $source

Write-Step 'Compilazione'
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { Write-Alert "Compilazione fallita (codice $LASTEXITCODE)"; exit 1 }

Write-Ok "Creato $exe ($(Format-Size (Get-Item -LiteralPath $exe).Length))"
Write-Info 'Copialo dove vuoi: e'' l''unico file che serve per usare Sibyl.'
