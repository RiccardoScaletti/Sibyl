# Sibyl :: processo di masterizzazione.
# Lo avvia Invoke-Burn (Sibyl.Burn.ps1) con i permessi di amministratore, che IMAPI2 richiede
# per cancellare e scrivere i dischi. Comunica fase e avanzamento scrivendo un piccolo file JSON.
param([Parameter(Mandatory = $true)][string]$Job)

$ErrorActionPreference = 'Stop'
$spec = [IO.File]::ReadAllText($Job) | ConvertFrom-Json

# Gli eventi di avanzamento di IMAPI arrivano mentre Write() e' bloccato: li riceve questa
# classe C# (PowerShell non eseguirebbe uno script block finche' Write() non ritorna).
Add-Type -TypeDefinition @'
using System;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

public class SibylBurnStatus {
    static readonly Guid DataEvents  = new Guid("2735413C-7F64-5B0F-8F00-5D77AFBE261E");
    static readonly Guid EraseEvents = new Guid("2735413A-7F64-5B0F-8F00-5D77AFBE261E");
    const int UpdateDispId = 0x200;
    static readonly string[] Actions = {
        "Controllo del disco", "Formattazione", "Preparazione lettore", "Calibrazione laser",
        "Scrittura", "Chiusura del disco", "Completato", "Verifica"
    };

    readonly string path;
    public string Phase = "";
    public double Percent = -1;
    public long Remaining = -1;
    public string Error = "";
    public bool Done;

    public SibylBurnStatus(string path) { this.path = path; }

    public void WatchWrite(object format2Data) {
        ComEventsHelper.Combine(format2Data, DataEvents, UpdateDispId, new Action<object, object>(OnWrite));
    }

    public void WatchErase(object format2Erase) {
        ComEventsHelper.Combine(format2Erase, EraseEvents, UpdateDispId, new Action<object, object, object>(OnErase));
    }

    static long Get(object com, string name) {
        return Convert.ToInt64(com.GetType().InvokeMember(name, BindingFlags.GetProperty, null, com, null));
    }

    void OnWrite(object sender, object args) {
        try {
            long action = Get(args, "CurrentAction");
            if (action >= 0 && action < Actions.Length) Phase = Actions[action];
            if (action == 4) {
                long start = Get(args, "StartLba"), count = Get(args, "SectorCount"), last = Get(args, "LastWrittenLba");
                if (count > 0) Percent = Math.Max(0, Math.Min(100.0, 100.0 * (last - start) / count));
                Remaining = Get(args, "RemainingTime");
            } else if (action == 5 || action == 6) {
                Percent = 100;
                Remaining = 0;
            }
            Save();
        } catch { }
    }

    void OnErase(object sender, object elapsed, object total) {
        try {
            long e = Convert.ToInt64(elapsed), t = Convert.ToInt64(total);
            Phase = "Cancellazione disco";
            if (t > 0) Percent = Math.Min(100.0, 100.0 * e / t);
            Remaining = Math.Max(0, t - e);
            Save();
        } catch { }
    }

    public void Save() {
        string json = string.Format(CultureInfo.InvariantCulture,
            "{{\"phase\":\"{0}\",\"percent\":{1:0.0},\"remaining\":{2},\"error\":\"{3}\",\"done\":{4}}}",
            Escape(Phase), Percent, Remaining, Escape(Error), Done ? "true" : "false");
        try { File.WriteAllText(path, json); } catch { }
    }

    static string Escape(string s) {
        return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", " ").Replace("\n", " ");
    }
}
'@

$status = [SibylBurnStatus]::new([string]$spec.StatusPath)
$rec = $null
try {
    $rec = New-Object -ComObject IMAPI2.MsftDiscRecorder2
    $rec.InitializeDiscRecorder($spec.RecorderId)
    # Durante cancellazione e calibrazione il disco sembra sparire e ricomparire: senza gli avvisi
    # di cambio disco Esplora file e la riproduzione automatica non provano a leggerlo o espellerlo
    try { $rec.DisableMcn() } catch { }

    if ($spec.Erase) {
        $status.Phase = 'Cancellazione disco'
        $status.Save()
        $eraser = New-Object -ComObject IMAPI2.MsftDiscFormat2Erase
        $eraser.Recorder = $rec
        $eraser.ClientName = 'Sibyl'
        $eraser.FullErase = $false
        try { $status.WatchErase($eraser) } catch { }
        $eraser.EraseMedia()
    }

    $status.Phase = 'Preparazione immagine'
    $status.Percent = -1
    $status.Remaining = -1
    $status.Save()
    $fmt = New-Object -ComObject IMAPI2.MsftDiscFormat2Data
    $fmt.Recorder = $rec
    $fmt.ClientName = 'Sibyl'
    $fmt.ForceMediaToBeClosed = $true
    # Velocita' minima supportata: piu' lenta, ma molto meno errori di lettura (specie su RW e lettori USB)
    try {
        $speeds = @($fmt.SupportedWriteSpeeds | ForEach-Object { [int]$_ })
        if ($speeds.Count) { $fmt.SetWriteSpeed(($speeds | Measure-Object -Minimum).Minimum, $false) }
    } catch { }
    $fs = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fs.ChooseImageDefaults($rec)
    $fs.FileSystemsToCreate = 4   # solo UDF: nomi lunghi e file oltre i 4 GB
    $fs.VolumeName = $spec.Label
    $fs.Root.AddTree($spec.Folder, $false)
    $image = $fs.CreateResultImage()

    try { $status.WatchWrite($fmt) } catch { }
    $status.Phase = 'Scrittura'
    $status.Save()
    $fmt.Write($image.ImageStream)
    $status.Percent = 100
} catch {
    $status.Error = $_.Exception.Message
} finally {
    if ($rec) { try { $rec.EnableMcn() } catch { } }
    $status.Done = $true
    $status.Save()
}
