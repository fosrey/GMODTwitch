// Simula un viewer sin necesidad de estar en vivo.
// Uso: node prueba.js [nombre] [comando] [viewer|sub|vip|mod|streamer]
const { escribirEvento, cargarConfig } = require('./eventos');

const config = cargarConfig();
const nombre = process.argv[2] || `Viewer${Math.floor(Math.random() * 900 + 100)}`;
const tipo = (process.argv[3] || '').toLowerCase();
const rango = (process.argv[4] || 'viewer').toLowerCase();

escribirEvento(config.carpetaData, { accion: 'spawn', usuario: nombre.toLowerCase(), nombre, color: '#9146FF', tipo, rango });
console.log(`Evento de prueba enviado: [${rango}] ${nombre}${tipo ? ` (${tipo})` : ''}`);
