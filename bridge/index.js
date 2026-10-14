// La Trinchera: puente Twitch -> Garry's Mod
// Lee el chat de forma anónima (no necesita contraseña ni token) y deja eventos para GMod:
//   - spawn:  alguien escribió el comando -> aparece su NPC
//   - dice:   alguien escribió en el chat -> globo de texto sobre su NPC (si tiene uno)
//   - callar: un mod borró su mensaje, le dio timeout o ban -> se quita su globo
//   - duelo / aceptar / rechazar: duelos entre NPCs de viewers
//   - votacion / voto: el streamer o un mod abre una votación y el chat vota con un número
const tmi = require('tmi.js');
const { escribirEvento, cargarConfig } = require('./eventos');

const config = cargarConfig();
const canal = String(config.canal || '').trim().toLowerCase();

if (!canal || canal === 'tu_canal_aqui') {
  console.error('Edita bridge/config.json y pon el nombre de tu canal en "canal".');
  process.exit(1);
}

const comando = (config.comando || '!spawn').toLowerCase();
const comandoDar = (config.comandoDar || '!dar').toLowerCase();
const comandoDuelo = (config.comandoDuelo || '!duelo').toLowerCase();
const comandoVotacion = (config.comandoVotacion || '!votacion').toLowerCase();
const cooldownDuelo = (config.cooldownDueloSegundos ?? 20) * 1000;
const cooldownGlobal = (config.cooldownGlobalSegundos ?? 3) * 1000;
const cooldownGlobo = (config.cooldownGloboSegundos ?? 2) * 1000;
const MAX_LARGO_GLOBO = 150;
const MAX_EMOTES = 20;

// Cooldown por viewer según su rango (en milisegundos). El streamer no tiene.
const cooldownPorRango = {
  viewer: (config.cooldownPorViewerSegundos ?? 60) * 1000,
  sub: (config.cooldownSubSegundos ?? 45) * 1000,
  vip: (config.cooldownVipSegundos ?? 30) * 1000,
  mod: (config.cooldownModSegundos ?? 8) * 1000,
  streamer: 0,
};

function rangoDe(tags) {
  const insignias = tags.badges || {};
  if (insignias.broadcaster) return 'streamer';
  if (tags.mod || insignias.moderator) return 'mod';
  if (tags.vip || insignias.vip) return 'vip';
  if (tags.subscriber || insignias.subscriber || insignias.founder) return 'sub';
  return 'viewer';
}

function enviar(evento, log) {
  try {
    escribirEvento(config.carpetaData, evento);
    if (log) console.log(log);
  } catch (err) {
    console.error(`No se pudo escribir el evento en ${config.carpetaData}:`, err.message);
  }
}

const ultimoPorViewer = new Map();
const ultimoGloboPorViewer = new Map();
const conocidos = new Map(); // usuario -> { nombre, color, rango } de la última vez que escribió
let ultimoGlobal = 0;

// Los nombres en otros alfabetos (coreano, japonés...) pueden no verse en GMod,
// así que en ese caso usamos el nombre de usuario.
function nombreVisible(tags) {
  const display = tags['display-name'] || tags.username;
  return display.toLowerCase() === tags.username ? display : tags.username;
}

function manejarSpawn(tags, tipo) {
  const usuario = tags.username;
  const rango = rangoDe(tags);
  const cooldown = cooldownPorRango[rango];
  const ahora = Date.now();

  if (cooldown > 0) {
    const ultimo = ultimoPorViewer.get(usuario) || 0;
    if (ahora - ultimo < cooldown) return;
    if (ahora - ultimoGlobal < cooldownGlobal) return;
  }

  ultimoPorViewer.set(usuario, ahora);
  ultimoGlobal = ahora;
  const nombre = nombreVisible(tags);

  const evento = {
    accion: 'spawn',
    usuario,
    nombre,
    color: tags.color || '',
    tipo: tipo.toLowerCase().slice(0, 20),
    rango,
  };

  enviar(evento, `-> [${rango}] ${nombre}${evento.tipo ? ` (${evento.tipo})` : ''}`);
}

// Recorta mensajes largos. Si es una *acción*, conserva el asterisco final para que GMod la reconozca.
function recortar(texto) {
  const letras = [...texto];
  if (letras.length <= MAX_LARGO_GLOBO) return texto;
  if (/^\*.+\*$/s.test(texto)) return `${letras.slice(0, MAX_LARGO_GLOBO - 2).join('')}…*`;
  return `${letras.slice(0, MAX_LARGO_GLOBO - 1).join('')}…`;
}

// !dar @viewer [comando]  (solo streamer y mods): le da a ese viewer el NPC elegido,
// sin cooldown ni restricción de rango. Si el viewer ya escribió en el chat, usa su nombre, color y rango.
function manejarDar(tags, partes) {
  const rango = rangoDe(tags);
  if (rango !== 'streamer' && rango !== 'mod') return;

  const usuario = (partes[1] || '').replace(/^@/, '').toLowerCase();
  if (!/^[a-z0-9_]{1,25}$/.test(usuario)) return;

  const tipo = (partes[2] || '').toLowerCase().slice(0, 20);
  const conocido = conocidos.get(usuario);

  const evento = {
    accion: 'spawn',
    usuario,
    nombre: conocido?.nombre || usuario,
    color: conocido?.color || '',
    tipo,
    rango: conocido?.rango || 'viewer',
    forzado: true,
  };

  enviar(evento, `-> !dar de ${tags.username}: [${evento.rango}] ${evento.nombre}${tipo ? ` (${tipo})` : ''}`);
}

// Emotes de Twitch del mensaje: { Kappa: "25", LUL: "425618" }.
// Twitch da las posiciones en caracteres (no en bytes); los emotes siempre son palabras enteras,
// así que GMod solo tiene que cambiar esas palabras por la imagen.
function emotesDe(mensaje, emotes) {
  if (!emotes) return undefined;

  const letras = [...mensaje];
  const resultado = {};
  for (const [id, rangos] of Object.entries(emotes).slice(0, MAX_EMOTES)) {
    const [inicio, fin] = String(rangos[0]).split('-').map(Number);
    const nombre = letras.slice(inicio, fin + 1).join('');
    if (nombre && /^[\w-]+$/.test(id)) resultado[nombre] = id;
  }
  return Object.keys(resultado).length ? resultado : undefined;
}

// !duelo @viewer: reta al NPC de otro viewer. El retado responde con !aceptar o !rechazar.
const ultimoDueloPorViewer = new Map();

function manejarDuelo(tags, partes) {
  const usuario = tags.username;
  const rival = (partes[1] || '').replace(/^@/, '').toLowerCase();
  if (!/^[a-z0-9_]{1,25}$/.test(rival) || rival === usuario) return;

  const ahora = Date.now();
  if (ahora - (ultimoDueloPorViewer.get(usuario) || 0) < cooldownDuelo) return;
  ultimoDueloPorViewer.set(usuario, ahora);

  enviar({ accion: 'duelo', usuario, rival }, `-> duelo: ${usuario} reta a ${rival}`);
}

// Se mandan los mensajes de todos; GMod ignora a quien no tiene NPC.
function manejarGlobo(usuario, texto, emotes) {
  const ahora = Date.now();
  if (ahora - (ultimoGloboPorViewer.get(usuario) || 0) < cooldownGlobo) return;
  ultimoGloboPorViewer.set(usuario, ahora);

  enviar({ accion: 'dice', usuario, texto: recortar(texto), emotes });
}

function callar(usuario) {
  enviar({ accion: 'callar', usuario });
}

const client = new tmi.Client({
  connection: { secure: true, reconnect: true },
  channels: [canal],
});

client.on('connected', () => {
  console.log(`Conectado al chat de #${canal}. Esperando "${comando}"...`);
});

client.on('disconnected', (razon) => {
  console.log(`Desconectado (${razon}). Reintentando...`);
});

client.on('message', (_canal, tags, mensaje) => {
  const texto = mensaje.trim();
  const partes = texto.split(/\s+/);
  const cmd = (partes[0] || '').toLowerCase();
  if (!cmd) return;

  conocidos.set(tags.username, { nombre: nombreVisible(tags), color: tags.color || '', rango: rangoDe(tags) });

  if (cmd === comando) {
    manejarSpawn(tags, partes[1] || '');
    return;
  }

  if (cmd === comandoDar) {
    manejarDar(tags, partes);
    return;
  }

  if (cmd === comandoDuelo) {
    manejarDuelo(tags, partes);
    return;
  }

  if (cmd === '!aceptar' || cmd === '!rechazar') {
    enviar({ accion: cmd.slice(1), usuario: tags.username });
    return;
  }

  if (cmd === comandoVotacion) {
    const rango = rangoDe(tags);
    if (rango === 'streamer' || rango === 'mod') enviar({ accion: 'votacion' }, `-> votación abierta por ${tags.username}`);
    return;
  }

  // Los comandos de otros bots (!discord, !redes...) no van a los globos.
  if (texto.startsWith('!')) return;

  // Un número solo es un voto. GMod lo cuenta si hay votación abierta y además lo muestra en globo.
  if (/^[1-9]$/.test(texto)) {
    enviar({ accion: 'voto', usuario: tags.username, opcion: Number(texto), texto });
    return;
  }

  // "/me se esconde" en Twitch sale como acción: *se esconde*
  const esMe = tags['message-type'] === 'action';
  manejarGlobo(tags.username, esMe ? `*${texto}*` : texto, emotesDe(mensaje, tags.emotes));
});

// Moderación: si un mod borra el mensaje o sanciona al viewer, el globo desaparece al instante.
client.on('messagedeleted', (_canal, usuario) => callar(usuario));
client.on('timeout', (_canal, usuario) => callar(usuario));
client.on('ban', (_canal, usuario) => callar(usuario));

client.connect().catch((err) => {
  console.error('No se pudo conectar a Twitch:', err);
  process.exit(1);
});
