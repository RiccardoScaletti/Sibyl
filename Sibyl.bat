@echo off
rem Sibyl - preserve memories :: menu principale (launcher o organizzatore).
rem Crea un collegamento a questo file sul desktop per avviare Sibyl con un doppio clic.
title Sibyl - preserve memories
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sibyl.ps1"
