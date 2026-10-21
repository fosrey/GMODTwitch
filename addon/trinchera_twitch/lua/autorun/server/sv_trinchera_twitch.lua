-- La Trinchera: NPCs de viewers de Twitch (servidor)
-- Lee los eventos que deja el puente de Node en garrysmod/data/trinchera_twitch/
-- La configuración se edita en el juego con "trinchera_menu" y se guarda en garrysmod/data/trinchera_config.json

if not TRINCHERA then include("autorun/sh_trinchera_estilos.lua") end

AddCSLuaFile("autorun/client/cl_trinchera_twitch.lua")
AddCSLuaFile("autorun/client/cl_trinchera_menu.lua")
AddCSLuaFile("autorun/client/cl_trinchera_eventos.lua")
AddCSLuaFile("autorun/client/cl_trinchera_camara.lua")

util.AddNetworkString("TrincheraAviso")
util.AddNetworkString("TrincheraPedirConfig")
util.AddNetworkString("TrincheraConfig")
util.AddNetworkString("TrincheraGuardarConfig")
util.AddNetworkString("TrincheraProbar")
util.AddNetworkString("TrincheraGlobo")
util.AddNetworkString("TrincheraOlvidarCadaver")

local CARPETA = "trinchera_twitch"
local CONFIG_ARCHIVO = "trinchera_config.json"
local MAX_POR_TICK = 10
local MAX_LARGO_GLOBO = 150
local MAX_EMOTES = 20
local RELACIONES = { defecto = true, aliado = true, enemigo = true }
local RANGOS_NPC = { viewer = true, sub = true, vip = true, mod = true }

---------------------------------------------------------------------------
-- Configuración
---------------------------------------------------------------------------

local function ConfigPorDefecto()
	local function npc(alias, rango) return { alias = alias, relacion = "defecto", rango = rango or "viewer" } end

	return {
		activo = true,
		globos = true,
		unoPorViewer = true,
		cadaveres = true,
		duelos = true,
		duracionDuelo = 40,
		estilo = "ww1",
		colorTwitch = false,
		max = 25,
		vida = { sub = 1.25, vip = 1.5, mod = 2, streamer = 3 },
		albedrio = { activo = true, radio = 800, min = 10, max = 25, correr = false, animaciones = 35, resbalon = 5 },
		frases = { activo = true, cada = 20, silencio = 45 },
		votacion = { duracion = 30, horda = 10, rebelion = 30, lenta = 15 },
		npcs = {
			npc_citizen      = npc("ciudadano"),
			Rebel            = npc("rebelde"),
			Medic            = npc("medico"),
			npc_vortigaunt   = npc("vortigaunt"),
			npc_combine_s    = npc("combine"),
			ShotgunSoldier   = npc("escopetero"),
			CombineElite     = npc("elite", "vip"),
			npc_metropolice  = npc("metrocop"),
			npc_zombie       = npc("zombie"),
			npc_fastzombie   = npc("rapido"),
			npc_poisonzombie = npc("venenoso"),
			npc_zombine      = npc("zombine", "sub"),
			npc_headcrab     = npc("headcrab"),
			npc_antlion      = npc("antlion"),
			npc_antlionguard = npc("guardian", "mod"),
			npc_hunter       = npc("hunter", "mod"),
		},
	}
end

local function Numero(t, clave, defecto, minimo, maximo)
	local v = istable(t) and tonumber(t[clave]) or defecto
	return math.Clamp(v, minimo, maximo)
end

local function Sanear(c)
	local d = ConfigPorDefecto()
	if not istable(c) then return d end

	local a, f, v = c.albedrio, c.frases, c.votacion

	local out = {
		activo = c.activo ~= false,
		globos = c.globos ~= false,
		unoPorViewer = c.unoPorViewer ~= false,
		cadaveres = c.cadaveres ~= false,
		duelos = c.duelos ~= false,
		duracionDuelo = math.floor(Numero(c, "duracionDuelo", d.duracionDuelo, 15, 120)),
		votacion = {
			duracion = Numero(v, "duracion", d.votacion.duracion, 10, 120),
			horda = math.floor(Numero(v, "horda", d.votacion.horda, 1, 30)),
			rebelion = Numero(v, "rebelion", d.votacion.rebelion, 10, 120),
			lenta = Numero(v, "lenta", d.votacion.lenta, 5, 60),
		},
		albedrio = {
			activo = not (istable(a) and a.activo == false),
			radio = Numero(a, "radio", d.albedrio.radio, 100, 4000),
			min = Numero(a, "min", d.albedrio.min, 2, 120),
			max = Numero(a, "max", d.albedrio.max, 2, 300),
			correr = istable(a) and a.correr == true,
			animaciones = Numero(a, "animaciones", d.albedrio.animaciones, 0, 100),
			resbalon = Numero(a, "resbalon", d.albedrio.resbalon, 0, 100),
		},
		frases = {
			activo = not (istable(f) and f.activo == false),
			cada = Numero(f, "cada", d.frases.cada, 3, 600),
			silencio = Numero(f, "silencio", d.frases.silencio, 0, 900),
		},
		estilo = TRINCHERA.ESTILOS[c.estilo] and c.estilo or d.estilo,
		colorTwitch = c.colorTwitch == true,
		max = math.Clamp(math.floor(tonumber(c.max) or d.max), 1, 100),
		vida = {},
		npcs = {},
	}

	out.albedrio.max = math.max(out.albedrio.min, out.albedrio.max)

	for rango, valor in pairs(d.vida) do
		out.vida[rango] = Numero(c.vida, rango, valor, 0.1, 10)
	end

	if istable(c.npcs) then
		local usados = {}
		for clave, n in pairs(c.npcs) do
			if isstring(clave) and istable(n) then
				local alias = string.sub((string.gsub(string.lower(tostring(n.alias or "")), "[^%w_]", "")), 1, 20)
				if alias == "" then alias = TRINCHERA.AliasPorDefecto(clave) end

				if not usados[alias] then
					usados[alias] = true
					out.npcs[clave] = {
						alias = alias,
						relacion = RELACIONES[n.relacion] and n.relacion or "defecto",
						rango = RANGOS_NPC[n.rango] and n.rango or "viewer",
					}
				end
			end
		end
	end

	return out
end

local config

local function CargarConfig()
	local contenido = file.Read(CONFIG_ARCHIVO, "DATA")
	config = contenido and Sanear(util.JSONToTable(contenido)) or ConfigPorDefecto()
end

local function GuardarConfig()
	file.Write(CONFIG_ARCHIVO, util.TableToJSON(config, true))
end

CargarConfig()

---------------------------------------------------------------------------
-- Avisos en el chat del juego. Se mandan como segmentos (textos y colores);
-- los textos que empiezan con "#" se traducen en el cliente (nombres de NPCs).
---------------------------------------------------------------------------

local GRIS = Color(200, 200, 200)

local function Aviso(...)
	local segmentos = {}
	for _, s in ipairs({ ... }) do
		if IsColor(s) then
			table.insert(segmentos, { r = s.r, g = s.g, b = s.b })
		else
			table.insert(segmentos, tostring(s))
		end
	end

	net.Start("TrincheraAviso")
	TRINCHERA.EscribirTabla(segmentos)
	net.Broadcast()
end

local function NombreNPC(ent)
	local datos = ent.NPCName and list.GetEntry("NPC", ent.NPCName)
	return (datos and datos.Name) or ("#" .. ent:GetClass())
end

---------------------------------------------------------------------------
-- Spawn
---------------------------------------------------------------------------

local vivos = {}
local porUsuario = {} -- usuario de Twitch (minúsculas) -> su NPC más reciente

---------------------------------------------------------------------------
-- Cadáveres con nombre. Según "ai_serverragdolls" el cuerpo lo crea el servidor
-- (se maneja aquí) o cada cliente (se maneja en cl_trinchera_twitch.lua).
-- Cuando el viewer vuelve a hacer !spawn, su cadáver anterior pierde el nombre.
---------------------------------------------------------------------------

local cadaveres = {} -- usuario -> ragdoll del servidor

local function OlvidarCadaver(usuario)
	local rag = cadaveres[usuario]
	if IsValid(rag) then rag:SetNWString("TrincheraNombre", "") end
	cadaveres[usuario] = nil

	net.Start("TrincheraOlvidarCadaver")
	net.WriteString(usuario)
	net.Broadcast()
end

hook.Add("CreateEntityRagdoll", "TrincheraCadaver", function(npc, rag)
	local nombre = npc:GetNWString("TrincheraNombre", "")
	if nombre == "" or not npc:GetNWBool("TrincheraCadaver") then return end

	local usuario = npc:GetNWString("TrincheraUsuario", "")
	rag:SetNWString("TrincheraNombre", nombre)
	rag:SetNWString("TrincheraEstilo", npc:GetNWString("TrincheraEstilo", "ninguno"))
	rag:SetNWString("TrincheraUsuario", usuario)
	cadaveres[usuario] = rag
end)

local function LimpiarVivos()
	for i = #vivos, 1, -1 do
		if not IsValid(vivos[i]) then table.remove(vivos, i) end
	end
end

-- Busca un punto libre en el suelo alrededor del jugador, sin atravesar paredes.
local function BuscarPosicion(ply)
	local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
	local ojo = ply:GetPos() + Vector(0, 0, 48)

	for _ = 1, 15 do
		local dir = Angle(0, math.Rand(0, 360), 0):Forward()
		local hacia = util.TraceLine({ start = ojo, endpos = ojo + dir * math.Rand(150, 400), mask = MASK_NPCSOLID_BRUSHONLY })
		local punto = hacia.HitPos - dir * 24

		if ojo:Distance(punto) > 80 then
			local suelo = util.TraceLine({ start = punto, endpos = punto - Vector(0, 0, 512), mask = MASK_NPCSOLID_BRUSHONLY })
			if suelo.Hit and not suelo.StartSolid then
				local pos = suelo.HitPos + Vector(0, 0, 4)
				local hueco = util.TraceHull({ start = pos, endpos = pos, mins = mins, maxs = maxs, mask = MASK_NPCSOLID })
				if not hueco.Hit then return suelo.HitPos end
			end
		end
	end

	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 300, filter = ply })
	return tr.HitPos
end

local function ArmaParaNPC(clase)
	for _, v in pairs(list.Get("NPCUsableWeapons")) do
		if v.class == clase then return true end
	end
	return false
end

-- Igual que el spawn del menú Q de Sandbox, para que los NPCs de addons salgan bien.
local function CrearNPC(clave, datos, pos, ply, armaElegida)
	local npc = ents.Create(datos.Class)
	if not IsValid(npc) then return end

	npc:SetPos(pos + Vector(0, 0, datos.Offset or 32))
	local ang = Angle(0, (ply:GetPos() - pos):Angle().y, 0)
	if datos.Rotate then ang = ang + datos.Rotate end
	npc:SetAngles(ang)

	local modelo = datos.Model
	if istable(modelo) then modelo = modelo[math.random(#modelo)] end
	if modelo then npc:SetModel(modelo) end
	if datos.Material then npc:SetMaterial(datos.Material) end

	-- Si los cuerpos conservan el nombre, no se desvanecen solos.
	local flags = config.cadaveres and SF_NPC_ALWAYSTHINK or bit.bor(SF_NPC_FADE_CORPSE, SF_NPC_ALWAYSTHINK)
	if datos.SpawnFlags then flags = bit.bor(flags, datos.SpawnFlags) end
	if datos.TotalSpawnFlags then flags = datos.TotalSpawnFlags end
	npc:SetKeyValue("spawnflags", flags)
	npc.SpawnFlags = flags

	local escuadra
	for k, v in pairs(datos.KeyValues or {}) do
		npc:SetKeyValue(k, v)
		if string.lower(k) == "squadname" then escuadra = v end
	end

	if escuadra and ai.GetSquadMemberCount(escuadra) >= 16 then
		local n = 0
		while ai.GetSquadMemberCount(escuadra .. n) >= 16 do n = n + 1 end
		npc:SetKeyValue("SquadName", escuadra .. n)
	end

	if datos.Skin then npc:SetSkin(datos.Skin) end

	-- armaElegida: nil/"" = la normal del NPC, "ninguna" = desarmado, o una clase de arma para NPCs.
	if armaElegida == "ninguna" then
		-- Aparece desarmado.
	elseif armaElegida and armaElegida ~= "" and ArmaParaNPC(armaElegida) then
		npc:SetKeyValue("additionalequipment", armaElegida)
	else
		local armas = {}
		for _, arma in ipairs(datos.Weapons or {}) do
			if arma ~= "" then table.insert(armas, arma) end
		end
		if #armas > 0 then
			npc:SetKeyValue("additionalequipment", armas[math.random(#armas)])
		end
	end

	if isfunction(datos.OnFloor) then datos.OnFloor(npc) end
	if isfunction(datos.OnDuplicated) then npc.OnDuplicated = datos.OnDuplicated end

	npc:Spawn()
	npc:Activate()
	npc.NPCName = clave

	if modelo and string.lower(npc:GetModel() or "") ~= string.lower(modelo) then npc:SetModel(modelo) end
	if datos.Skin then npc:SetSkin(datos.Skin) end
	if not datos.NoDrop and not datos.OnCeiling and not datos.OnFloor then npc:DropToFloor() end

	if datos.Health then
		npc:SetHealth(datos.Health)
		npc:SetMaxHealth(datos.Health)
	end

	for k, v in pairs(datos.BodyGroups or {}) do npc:SetBodygroup(k, v) end

	return npc
end

-- Elige el NPC: el que pidió el viewer si existe y su rango le alcanza; si no, uno aleatorio de los permitidos.
-- "exacto": si se pidió un comando que no existe, no se elige uno al azar (para !dar).
local function ElegirNPC(alias, nivel, exacto)
	local permitidos = {}

	for clave, ajustes in pairs(config.npcs) do
		if nivel >= TRINCHERA.NIVEL[ajustes.rango] and TRINCHERA.NPCValido(list.GetEntry("NPC", clave)) then
			if alias ~= "" and ajustes.alias == alias then return clave end
			table.insert(permitidos, clave)
		end
	end

	if #permitidos == 0 or (exacto and alias ~= "") then return end
	return permitidos[math.random(#permitidos)]
end

-- ev.forzado = lo pidió el streamer o un mod (!dar): sin restricción de rango y aunque los spawns estén pausados.
local function SpawnViewer(ev, forzarClave)
	if not forzarClave and not ev.forzado and not config.activo then return end

	local ply = player.GetHumans()[1]
	if not IsValid(ply) then return end

	local nombre = string.sub((string.gsub(tostring(ev.nombre or ""), "%c", "")), 1, 25)
	if nombre == "" then return end

	local rango = TRINCHERA.NIVEL[ev.rango] and ev.rango or "viewer"
	local alias = string.lower(tostring(ev.tipo or ""))
	local clave = forzarClave or ElegirNPC(alias, ev.forzado and 99 or TRINCHERA.NIVEL[rango], ev.forzado)
	if not clave then
		if ev.forzado then Aviso(Color(145, 70, 255), "[Twitch] ", color_white, "No existe el comando '" .. alias .. "' (mira trinchera_tipos)") end
		return
	end

	local datos = list.GetEntry("NPC", clave)
	if not TRINCHERA.NPCValido(datos) then return end

	-- Un NPC por viewer: el nuevo reemplaza al anterior (el streamer puede tener varios).
	local usuario = string.lower(tostring(ev.usuario or nombre))
	OlvidarCadaver(usuario)
	local anterior = porUsuario[usuario]
	if config.unoPorViewer and rango ~= "streamer" and IsValid(anterior) then
		anterior:Remove()
	end

	-- Si se llega al límite, desaparece el NPC más viejo para hacer espacio.
	LimpiarVivos()
	while #vivos >= config.max and #vivos > 0 do
		local viejo = table.remove(vivos, 1)
		if IsValid(viejo) then viejo:Remove() end
	end

	local npc = CrearNPC(clave, datos, BuscarPosicion(ply), ply, isstring(ev.arma) and ev.arma or nil)
	if not IsValid(npc) then return end

	npc:SetNWString("TrincheraNombre", nombre)
	npc:SetNWString("TrincheraEstilo", config.estilo)
	npc:SetNWString("TrincheraRango", rango)
	npc:SetNWString("TrincheraColor", (config.colorTwitch and isstring(ev.color)) and ev.color or "")
	npc:SetNWString("TrincheraUsuario", usuario)
	npc:SetNWBool("TrincheraCadaver", config.cadaveres)

	local multiplicador = config.vida[rango] or 1
	if multiplicador ~= 1 and npc:Health() > 0 then
		local vida = math.max(1, math.floor(npc:Health() * multiplicador))
		npc:SetMaxHealth(vida)
		npc:SetHealth(vida)
	end

	local relacion = (config.npcs[clave] or {}).relacion
	if relacion == "aliado" then
		npc:AddEntityRelationship(ply, D_LI, 99)
	elseif relacion == "enemigo" then
		npc:AddEntityRelationship(ply, D_HT, 99)
	end

	-- Para que se pueda quitar con Z (deshacer) o con la limpieza normal de GMod.
	npc:SetCreator(ply)
	undo.Create("NPC de Twitch")
		undo.AddEntity(npc)
		undo.SetPlayer(ply)
	undo.Finish()
	cleanup.Add(ply, "npcs", npc)

	npc.TrincheraViewer = nombre
	npc.TrincheraUltimoHabla = CurTime()

	table.insert(vivos, npc)
	porUsuario[usuario] = npc

	local insignia = TRINCHERA.INSIGNIAS[rango]
	local estilo = TRINCHERA.ESTILOS[config.estilo]
	if insignia then
		Aviso(insignia.color, "[" .. insignia.texto .. "] ", estilo.color, nombre, GRIS, " apareció como ", color_white, datos.Name or ("#" .. datos.Class))
	else
		Aviso(estilo.color, nombre, GRIS, " apareció como ", color_white, datos.Name or ("#" .. datos.Class))
	end
end

---------------------------------------------------------------------------
-- Globos de texto: lo que el viewer escribe en el chat aparece sobre su NPC.
-- Un texto vacío borra el globo (mensaje borrado, timeout o ban en Twitch).
---------------------------------------------------------------------------

-- emotes (opcional): { palabra = id } con los emotes de Twitch del mensaje.
local function GloboNPC(npc, texto, emotes)
	net.Start("TrincheraGlobo")
	net.WriteEntity(npc)
	net.WriteString(texto)
	net.WriteUInt(table.Count(emotes or {}), 8)
	for palabra, id in pairs(emotes or {}) do
		net.WriteString(palabra)
		net.WriteString(id)
	end
	net.Broadcast()
end

-- Solo palabras cortas e ids que sirvan como nombre de archivo (se guardan en data/trinchera_emotes/).
local function SanearEmotes(emotes)
	if not istable(emotes) then return end

	local out, n = {}, 0
	for palabra, id in pairs(emotes) do
		if isstring(palabra) and isstring(id) and #palabra <= 50 and string.match(id, "^[%w_%-]+$") and #id <= 64 then
			out[palabra] = id
			n = n + 1
			if n >= MAX_EMOTES then break end
		end
	end
	return out
end

local function NPCDe(usuario)
	usuario = string.lower(tostring(usuario or ""))
	local npc = porUsuario[usuario]
	if IsValid(npc) then return npc end
	porUsuario[usuario] = nil
end

local function Decir(usuario, texto, emotes)
	if not config.globos then return end

	local npc = NPCDe(usuario)
	if not npc then return end

	texto = string.Trim((string.gsub(tostring(texto or ""), "%c", "")))
	if texto == "" then return end

	-- Al recortar una *acción* se conserva el asterisco final para que siga viéndose como acción.
	local corte = utf8.offset(texto, MAX_LARGO_GLOBO + 1)
	if corte then
		local accion = string.match(texto, "^%*.+%*$") ~= nil
		texto = string.sub(texto, 1, corte - 1) .. (accion and "…*" or "…")
	end

	npc.TrincheraUltimoHabla = CurTime()
	GloboNPC(npc, texto, SanearEmotes(emotes))
end

local function Callar(usuario)
	local npc = NPCDe(usuario)
	if npc then GloboNPC(npc, "") end
end

-- Para sv_trinchera_vida.lua (libre albedrío y frases) y sv_trinchera_eventos.lua (duelos y votaciones).
function TRINCHERA.Config() return config end
function TRINCHERA.NPCsVivos()
	LimpiarVivos()
	return vivos
end
TRINCHERA.GloboNPC = GloboNPC
TRINCHERA.Aviso = Aviso
TRINCHERA.NPCDe = NPCDe
TRINCHERA.Decir = Decir

hook.Add("OnNPCKilled", "TrincheraMuerte", function(npc, atacante)
	local nombre = npc:GetNWString("TrincheraNombre", "")
	if nombre == "" then return end

	local quien = "el mundo"
	if IsValid(atacante) then
		if atacante == npc then
			quien = "sí mismo"
		elseif atacante:IsPlayer() then
			quien = atacante:Nick()
		elseif atacante:GetNWString("TrincheraNombre", "") ~= "" then
			quien = atacante:GetNWString("TrincheraNombre")
		elseif atacante:IsNPC() then
			quien = NombreNPC(atacante)
		else
			quien = "#" .. atacante:GetClass()
		end
	end

	Aviso(GRIS, "† ", color_white, nombre, GRIS, " cayó a manos de ", color_white, quien)
end)

---------------------------------------------------------------------------
-- Cola de eventos: cada archivo .txt es un viewer.
---------------------------------------------------------------------------

file.CreateDir(CARPETA)

-- Descartar lo que quedó pendiente de antes de cargar el mapa.
for _, f in ipairs(file.Find(CARPETA .. "/*.txt", "DATA") or {}) do
	file.Delete(CARPETA .. "/" .. f)
end

timer.Create("TrincheraLeerCola", 0.5, 0, function()
	local archivos = file.Find(CARPETA .. "/*.txt", "DATA", "nameasc") or {}

	for i = 1, math.min(#archivos, MAX_POR_TICK) do
		local ruta = CARPETA .. "/" .. archivos[i]
		local contenido = file.Read(ruta, "DATA")
		file.Delete(ruta)

		local ev = contenido and util.JSONToTable(contenido)
		if istable(ev) then
			if ev.accion == "dice" then
				Decir(ev.usuario, ev.texto, ev.emotes)
			elseif ev.accion == "callar" then
				Callar(ev.usuario)
			elseif TRINCHERA.EVENTOS[ev.accion] then
				TRINCHERA.EVENTOS[ev.accion](ev)
			else
				SpawnViewer(ev)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Menú y comandos de consola
---------------------------------------------------------------------------

local function EsJefe(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

net.Receive("TrincheraPedirConfig", function(_, ply)
	if not EsJefe(ply) then return end
	net.Start("TrincheraConfig")
	TRINCHERA.EscribirTabla(config)
	net.Send(ply)
end)

net.Receive("TrincheraGuardarConfig", function(_, ply)
	if not EsJefe(ply) then return end
	local nueva = TRINCHERA.LeerTabla()
	if not istable(nueva) then return end

	config = Sanear(nueva)
	GuardarConfig()
	Aviso(Color(145, 70, 255), "[Twitch] ", color_white, "Configuración guardada (" .. table.Count(config.npcs) .. " NPCs activos)")
end)

net.Receive("TrincheraProbar", function(_, ply)
	if not EsJefe(ply) then return end
	local clave = net.ReadString()
	local rango = net.ReadString()
	local nombre = string.Trim(net.ReadString())
	local arma = net.ReadString()
	if nombre == "" then nombre = "Prueba" .. math.random(10, 99) end
	SpawnViewer({ nombre = nombre, rango = rango, color = "#9146FF", arma = arma }, clave)
end)

-- trinchera_test [nombre] [comando] [viewer|sub|vip|mod|streamer]
concommand.Add("trinchera_test", function(ply, _, args)
	if not EsJefe(ply) then return end
	SpawnViewer({
		nombre = args[1] or ("Viewer" .. math.random(100, 999)),
		tipo = string.lower(args[2] or ""),
		rango = string.lower(args[3] or "viewer"),
		color = "#9146FF",
	})
end)

-- trinchera_decir <nombre> <mensaje...>  (prueba de globos sin Twitch)
-- Para probar emotes: palabra=id, por ejemplo  trinchera_decir Luis hola Kappa=25
concommand.Add("trinchera_decir", function(ply, _, args)
	if not EsJefe(ply) or #args < 2 then return end
	local usuario = table.remove(args, 1)

	local emotes = {}
	for i, palabra in ipairs(args) do
		local nombre, id = string.match(palabra, "^(.+)=([%w_%-]+)$")
		if nombre then
			args[i] = nombre
			emotes[nombre] = id
		end
	end

	Decir(usuario, table.concat(args, " "), emotes)
end)

concommand.Add("trinchera_limpiar", function(ply)
	if not EsJefe(ply) then return end
	for _, npc in ipairs(vivos) do
		if IsValid(npc) then npc:Remove() end
	end
	vivos = {}
	Aviso(Color(145, 70, 255), "[Twitch] ", color_white, "Se eliminaron todos los NPCs de viewers")
end)

concommand.Add("trinchera_tipos", function(ply)
	local lineas = {}
	for clave, ajustes in SortedPairsByMemberValue(config.npcs, "alias") do
		table.insert(lineas, string.format("  !spawn %-14s %-22s %s", ajustes.alias, clave, ajustes.rango))
	end
	local texto = "Comandos activos:\n" .. table.concat(lineas, "\n")
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, texto) else print(texto) end
end)

print("[La Trinchera] NPCs de Twitch cargado. Leyendo data/" .. CARPETA .. "/")
