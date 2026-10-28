// Sibyl.exe :: contenitore. Porta dentro di se' gli script PowerShell di Sibyl, li estrae in
// %LOCALAPPDATA%\Sibyl\app\<build> e li esegue in una finestra della console classica (conhost),
// l'unica che Sibyl puo' ridimensionare a 700x700: Windows Terminal non lo permette.
// Si compila con Build-SibylExe.ps1, che sostituisce @BUILD_ID@ e incorpora gli script.
//
//   Sibyl.exe                       menu principale
//   Sibyl.exe launcher [opzioni]    launcher (es. Sibyl.exe launcher -Autostart On)
//   Sibyl.exe organizer [opzioni]   organizzatore
//   Sibyl.exe <cartella>            organizzatore su quella cartella (trascinata sull'exe)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Sibyl")]
[assembly: AssemblyDescription("Sibyl - preserve memories")]
[assembly: AssemblyProduct("Sibyl")]
[assembly: AssemblyVersion("@VERSION@")]
[assembly: AssemblyFileVersion("@VERSION@")]
[assembly: AssemblyInformationalVersion("@VERSION@")]

static class Program
{
    const string BuildId = "@BUILD_ID@";
    const string ResourcePrefix = "app/";

    static int Main(string[] args)
    {
        try
        {
            string appDir = Extract();
            List<string> rest = new List<string>(args);
            string script = "Sibyl.ps1";
            if (rest.Count > 0)
            {
                string first = rest[0].ToLowerInvariant();
                if (first == "launcher") { script = "SibylLauncher.ps1"; rest.RemoveAt(0); }
                else if (first == "organizer" || first == "organizzatore") { script = "Organize-GogGames.ps1"; rest.RemoveAt(0); }
                // qualsiasi altra cosa che non sia un'opzione e' una cartella: la controlla l'organizzatore
                else if (!first.StartsWith("-")) { script = "Organize-GogGames.ps1"; }
            }

            StringBuilder command = new StringBuilder("powershell.exe -NoProfile -ExecutionPolicy Bypass -File ");
            command.Append(Quote(Path.Combine(appDir, script)));
            foreach (string arg in rest) { command.Append(' ').Append(Quote(arg)); }

            string conhost = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "conhost.exe");
            ProcessStartInfo info = new ProcessStartInfo(conhost, command.ToString());
            info.UseShellExecute = false;
            info.EnvironmentVariables["SIBYL_EXE"] = Assembly.GetExecutingAssembly().Location;
            using (Process process = Process.Start(info))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception e)
        {
            MessageBox.Show(e.Message, "Sibyl", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    // Estrae gli script una volta per build e rimuove quelli delle build precedenti
    // (e quelli di quando il programma si chiamava TimeRunner)
    static string Extract()
    {
        string local = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        if (string.IsNullOrEmpty(local)) { local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData); }
        string root = Path.Combine(local, @"Sibyl\app");
        string dir = Path.Combine(root, BuildId);
        string marker = Path.Combine(dir, ".complete");

        if (!File.Exists(marker))
        {
            Directory.CreateDirectory(dir);
            Assembly assembly = Assembly.GetExecutingAssembly();
            foreach (string name in assembly.GetManifestResourceNames())
            {
                if (!name.StartsWith(ResourcePrefix)) { continue; }
                using (Stream source = assembly.GetManifestResourceStream(name))
                using (FileStream target = File.Create(Path.Combine(dir, name.Substring(ResourcePrefix.Length))))
                {
                    source.CopyTo(target);
                }
            }
            File.WriteAllText(marker, BuildId);
        }

        foreach (string old in Directory.GetDirectories(root))
        {
            if (string.Equals(Path.GetFileName(old), BuildId, StringComparison.OrdinalIgnoreCase)) { continue; }
            try { Directory.Delete(old, true); } catch { }   // forse in uso da un'altra finestra: si riprova la prossima volta
        }
        try { Directory.Delete(Path.Combine(local, @"TimeRunner\app"), true); } catch { }
        return dir;
    }

    // Un argomento per la riga di comando di Windows: virgolette e backslash finali
    static string Quote(string arg)
    {
        if (arg.Length > 0 && arg.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) { return arg; }
        string escaped = arg.Replace("\"", "\\\"");
        if (escaped.EndsWith("\\")) { escaped += "\\"; }
        return "\"" + escaped + "\"";
    }
}
