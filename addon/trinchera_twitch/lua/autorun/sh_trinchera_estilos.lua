-- La Trinchera: estilos de nombre y rangos (compartido servidor/cliente)
AddCSLuaFile()

TRINCHERA = TRINCHERA or {}

-- Rangos de Twitch, de menor a mayor.
TRINCHERA.NIVEL = { viewer = 0, sub = 1, vip = 2, mod = 3, streamer = 4 }

TRINCHERA.INSIGNIAS = {
	sub      = { texto = "SUB",      color = Color(145, 70, 255) },
	vip      = { texto = "VIP",      color = Color(224, 5, 185) },
	mod      = { texto = "MOD",      color = Color(0, 173, 3) },
	streamer = { texto = "STREAMER", color = Color(233, 25, 22) },
}

-- Cada estilo define la fuente y el color del nombre.
-- "globo" es el aspecto de los globos de texto con lo que el viewer escribe en el chat.
TRINCHERA.ESTILOS = {
	ninguno = {
		nombre = "Ninguno",
		fuente = "Roboto",
		color  = color_white,
		globo  = { fuente = "Roboto", fondo = Color(255, 255, 255), borde = Color(40, 40, 40), texto = Color(20, 20, 20) },
	},
	ww1 = {
		nombre = "Gran Guerra (WW1)",
		fuente = "Stencil",
		color  = Color(205, 190, 140),
		-- Carta desde el frente: papel envejecido y máquina de escribir.
		globo  = { fuente = "Courier New", fondo = Color(232, 220, 188), borde = Color(90, 70, 40), texto = Color(45, 35, 20) },
	},
	lovecraft = {
		nombre = "Lovecraft",
		fuente = "Old English Text MT",
		color  = Color(120, 210, 160),
		temblor = true,
		globo  = { fuente = "Georgia", fondo = Color(16, 26, 22), borde = Color(80, 160, 120), texto = Color(150, 230, 180) },
	},
}

TRINCHERA.ORDEN_ESTILOS = { "ninguno", "ww1", "lovecraft" }

-- Comando de chat sugerido a partir de la clave del NPC: "npc_fastzombie" -> "fastzombie"
function TRINCHERA.AliasPorDefecto(clave)
	local alias = string.lower(clave)
	alias = string.gsub(alias, "^npc_", "")
	alias = string.gsub(alias, "^monster_", "")
	alias = string.gsub(alias, "[^%w_]", "")
	return string.sub(alias, 1, 20)
end

-- Tablas por red (configuración, avisos), comprimidas para no pasar el límite de los mensajes.
function TRINCHERA.EscribirTabla(tabla)
	local datos = util.Compress(util.TableToJSON(tabla))
	net.WriteUInt(#datos, 32)
	net.WriteData(datos, #datos)
end

function TRINCHERA.LeerTabla()
	local largo = net.ReadUInt(32)
	if largo == 0 or largo > 60000 then return end
	local json = util.Decompress(net.ReadData(largo))
	return json and util.JSONToTable(json)
end

-- NPCs que solo se pueden poner en el techo (barnacle, cámaras...) no sirven para aparecer junto al jugador.
function TRINCHERA.NPCValido(datos)
	return istable(datos) and isstring(datos.Class) and not (datos.OnCeiling and not datos.OnFloor)
end
