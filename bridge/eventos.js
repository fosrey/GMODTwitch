// Escribe cada evento como un archivo .txt separado en garrysmod/data/trinchera_twitch.
// Se escribe primero como .tmp y luego se renombra, para que GMod nunca lea un archivo a medias.
const fs = require('fs');
const path = require('path');
const { buscarGMod } = require('./gmod');

let contador = 0;

function escribirEvento(carpeta, evento) {
  fs.mkdirSync(carpeta, { recursive: true });
  const base = `${Date.now()}_${String(contador++ % 10000).padStart(4, '0')}`;
  const tmp = path.join(carpeta, `${base}.tmp`);
  fs.writeFileSync(tmp, JSON.stringify(evento), 'utf8');
  fs.renameSync(tmp, path.join(carpeta, `${base}.txt`));
}

// "carpetaData": "auto" (o vacío) busca GMod solo. También se puede poner una ruta fija.
function cargarConfig() {
  const ruta = path.join(__dirname, 'config.json');
  const config = JSON.parse(fs.readFileSync(ruta, 'utf8'));

  if (!config.carpetaData || config.carpetaData === 'auto') {
    const gmod = buscarGMod();
    if (!gmod) {
      console.error('No se encontró Garry\'s Mod. Pon la ruta a mano en "carpetaData" de bridge/config.json,');
      console.error('por ejemplo: "D:/SteamLibrary/steamapps/common/GarrysMod/garrysmod/data/trinchera_twitch"');
      process.exit(1);
    }
    config.carpetaData = path.join(gmod, 'data', 'trinchera_twitch');
  }

  return config;
}

module.exports = { escribirEvento, cargarConfig };
