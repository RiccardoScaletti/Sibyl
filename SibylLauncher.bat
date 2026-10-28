@echo off
rem Sibyl Launcher :: la console per i giochi GOG su disco (si apre anche dal menu di Sibyl.bat).
rem Per farla partire a ogni accesso a Windows: SibylLauncher.bat -Autostart On
title Sibyl - Launcher
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SibylLauncher.ps1" %*
