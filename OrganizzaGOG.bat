@echo off
rem Sibyl :: Disc Prep
rem Doppio clic per scegliere la cartella, oppure trascina la cartella dei download GOG su questo file.
title Sibyl - Disc Prep
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Organize-GogGames.ps1" %*
echo.
pause
