# Sibyl — preserve memories

Sibyl trasforma i tuoi giochi senza DRM (GOG e non solo) in dischi fisici, da usare come le cartucce
di una vecchia console: inserisci il disco e il gioco parte.

Interfaccia a riga di comando con grafica ASCII, in italiano e in inglese, per Windows 10/11.
Non serve installare niente: usa PowerShell e il motore di masterizzazione già presenti in Windows.

## Come funziona

- **Organizer** — prende gli installer offline scaricati da GOG (o, con **[I]**, un gioco qualsiasi da
  una cartella: installer Inno Setup, NSIS, MSI, oppure un gioco già pronto da avviare), li ordina in una
  libreria, calcola gli SHA-256, masterizza il disco e lo verifica. Se il gioco non entra in un disco lo
  divide su più dischi e li chiede uno alla volta, con **[A]** per annullare tra un disco e l'altro.
- **Launcher** — resta in attesa come una console. Quando inserisci un disco lo riconosce, al primo
  inserimento installa il gioco (copiando prima tutti i dischi, se sono più di uno), poi lo avvia e
  conta le ore giocate. Scopre dove è stato installato il gioco, il suo eseguibile e il disinstallatore
  confrontando le voci di "App installate" di Windows prima e dopo l'installazione.
- **Menu principale** — apre Launcher e Organizer; nelle opzioni si scelgono lingua e avvio automatico
  e si trovano tutti i comandi di avvio.

## Avvio

Scarica `Sibyl.exe` dalle [release](../../releases) e aprilo con un doppio clic, oppure:

```
Sibyl.exe                      menu principale
Sibyl.exe launcher             solo il launcher (es. Sibyl.exe launcher -Autostart On)
Sibyl.exe organizer            solo l'organizer
Sibyl.exe <cartella>           organizer su quella cartella
```

Senza l'exe valgono gli stessi comandi con `Sibyl.bat`, `SibylLauncher.bat` e `OrganizzaGOG.bat`.

## File

| File | Ruolo |
|---|---|
| `Sibyl.ps1` | menu principale e opzioni |
| `SibylLauncher.ps1` | launcher: dischi, installazione, avvio, tempo di gioco |
| `Organize-GogGames.ps1` | organizer: libreria, importazione, masterizzazione su uno o più dischi |
| `Sibyl.Common.ps1` | grafica, traduzioni, verifica dei dischi, installer di ogni tipo, disinstallazione |
| `Sibyl.Lang.ps1` | dizionario inglese |
| `Sibyl.Burn.ps1`, `Sibyl.BurnWorker.ps1` | masterizzazione con IMAPI2 (permessi di amministratore solo per scrivere) |
| `Sibyl.Exe.cs`, `Build-SibylExe.ps1`, `Sibyl.ico` | contenitore `Sibyl.exe` e script per compilarlo |

## Compilare Sibyl.exe

```
powershell -ExecutionPolicy Bypass -File Build-SibylExe.ps1
```

Usa il compilatore C# del .NET Framework 4, già presente in Windows. L'exe finisce in `dist\`.
