@echo off
cd /d "%~dp0"
title La Trinchera - Prueba
set NOMBRE=
set TIPO=
set RANGO=
set /p NOMBRE=Nombre del viewer (Enter = aleatorio):
set /p TIPO=Comando del NPC, ej. zombie (Enter = aleatorio):
set /p RANGO=Rango: viewer, sub, vip, mod, streamer (Enter = viewer):
if "%NOMBRE%"=="" set NOMBRE=Viewer%RANDOM%
if "%TIPO%"=="" set TIPO=-
node prueba.js %NOMBRE% %TIPO% %RANGO%
pause
