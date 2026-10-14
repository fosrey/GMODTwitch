// Instala La Trinchera en Garry's Mod:
//   1. Copia el addon a garrysmod/addons (reemplaza la versión anterior).
//   2. Restaura la configuración y las frases de la carpeta "respaldo", solo si en GMod no existen todavía.
const fs = require('fs');
const path = require('path');
const { buscarGMod } = require('./gmod');

const raiz = path.join(__dirname, '..');
const gmod = buscarGMod();

if (!gmod) {
  console.error('No se encontró Garry\'s Mod. ¿Está instalado desde Steam?');
  console.error('Si está en otro lado, copia a mano la carpeta "addon/trinchera_twitch" a garrysmod/addons.');
  process.exit(1);
}

console.log(`Garry's Mod encontrado en:\n  ${gmod}\n`);

const origen = path.join(raiz, 'addon', 'trinchera_twitch');
const destino = path.join(gmod, 'addons', 'trinchera_twitch');
fs.rmSync(destino, { recursive: true, force: true });
fs.cpSync(origen, destino, { recursive: true });
console.log('Addon instalado en garrysmod/addons/trinchera_twitch');

const respaldo = path.join(raiz, 'respaldo');
for (const archivo of ['trinchera_config.json', 'trinchera_frases.txt']) {
  const desde = path.join(respaldo, archivo);
  const hacia = path.join(gmod, 'data', archivo);
  if (!fs.existsSync(desde)) continue;

  if (fs.existsSync(hacia)) {
    console.log(`${archivo}: ya existe en GMod, no se toca.`);
  } else {
    fs.mkdirSync(path.dirname(hacia), { recursive: true });
    fs.copyFileSync(desde, hacia);
    console.log(`${archivo}: restaurado desde el respaldo.`);
  }
}

console.log('\nListo. Abre Garry\'s Mod, carga un mapa y ejecuta bridge/iniciar.bat.');
