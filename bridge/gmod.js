// Busca dónde está instalado Garry's Mod, en cualquier biblioteca de Steam.
// Uso desde consola: node gmod.js         -> imprime la carpeta garrysmod
//                    node gmod.js frases  -> imprime la ruta del archivo de frases
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function carpetasDeSteam() {
  const candidatas = [];

  try {
    const salida = execSync('reg query "HKCU\\Software\\Valve\\Steam" /v SteamPath', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const m = salida.match(/SteamPath\s+REG_SZ\s+(.+)/);
    if (m) candidatas.push(m[1].trim());
  } catch {
    // Sin Steam en el registro: se prueban las rutas típicas.
  }

  if (process.env['ProgramFiles(x86)']) candidatas.push(path.join(process.env['ProgramFiles(x86)'], 'Steam'));
  if (process.env.ProgramFiles) candidatas.push(path.join(process.env.ProgramFiles, 'Steam'));
  return candidatas;
}

function bibliotecas() {
  const resultado = new Set();

  for (const steam of carpetasDeSteam()) {
    resultado.add(path.normalize(steam));
    try {
      const vdf = fs.readFileSync(path.join(steam, 'steamapps', 'libraryfolders.vdf'), 'utf8');
      for (const m of vdf.matchAll(/"path"\s+"(.+?)"/g)) resultado.add(path.normalize(m[1].replace(/\\\\/g, '\\')));
    } catch {
      // Esta carpeta de Steam no existe o no tiene bibliotecas.
    }
  }

  return [...resultado];
}

// Devuelve la carpeta "garrysmod" de la instalación real (la que tiene el ejecutable),
// o null si no se encuentra. Así se descartan restos de instalaciones viejas.
function buscarGMod() {
  for (const biblioteca of bibliotecas()) {
    const juego = path.join(biblioteca, 'steamapps', 'common', 'GarrysMod');
    const tieneExe = ['gmod.exe', 'hl2.exe'].some((exe) => fs.existsSync(path.join(juego, exe)));
    if (tieneExe && fs.existsSync(path.join(juego, 'garrysmod'))) return path.join(juego, 'garrysmod');
  }
  return null;
}

module.exports = { buscarGMod };

if (require.main === module) {
  const gmod = buscarGMod();
  if (!gmod) {
    console.error('No se encontró Garry\'s Mod.');
    process.exit(1);
  }
  console.log(process.argv[2] === 'frases' ? path.join(gmod, 'data', 'trinchera_frases.txt') : gmod);
}
