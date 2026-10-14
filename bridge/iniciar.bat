@echo off
cd /d "%~dp0"
title La Trinchera - Puente Twitch
if not exist node_modules (
  echo Instalando dependencias por primera vez...
  call npm install
)
node index.js
pause
