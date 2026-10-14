@echo off
rem Abre el archivo de frases ambientales en el Bloc de notas.
rem Al guardarlo, el juego lo recarga solo (no hace falta reiniciar).
set ARCHIVO=
for /f "delims=" %%i in ('node "%~dp0bridge\gmod.js" frases 2^>nul') do set "ARCHIVO=%%i"

if "%ARCHIVO%"=="" (
  echo No se encontro Garry's Mod ^(o falta Node.js^).
  pause
  exit /b
)

if not exist "%ARCHIVO%" (
  echo Todavia no existe el archivo de frases.
  echo Abre Garry's Mod y carga un mapa una vez para crearlo.
  pause
  exit /b
)

start "" notepad "%ARCHIVO%"
