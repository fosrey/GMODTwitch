@echo off
cd /d "%~dp0"
title La Trinchera - Instalar

where node >nul 2>nul
if errorlevel 1 (
  echo No se encontro Node.js.
  echo Instala la version LTS desde https://nodejs.org y vuelve a ejecutar este archivo.
  echo.
  echo Si solo quieres el addon sin Twitch, copia a mano la carpeta
  echo "addon\trinchera_twitch" a garrysmod\addons.
  start "" https://nodejs.org
  pause
  exit /b
)

node bridge\instalar.js
pause
