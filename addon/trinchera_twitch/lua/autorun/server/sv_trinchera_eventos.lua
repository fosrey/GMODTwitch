-- La Trinchera: duelos, votaciones y cámara (servidor)
--   - Duelo: "!duelo @viewer" y el retado acepta con "!aceptar". Sus NPCs pelean frente al streamer.
--   - Votación: el streamer o un mod escribe "!votacion"; el chat vota con un número y el evento ganador ocurre.
--     Eventos: horda zombie, rebelión (los NPCs de viewers se vuelven contra el streamer) y cámara lenta.
--   - Cámara: mientras el streamer mira desde un NPC (cl_trinchera_camara.lua) es invulnerable.

if not TRINCHERA then include("autorun/sh_trinchera_estilos.lua") end

util.AddNetworkString("TrincheraAnuncio")
util.AddNetworkString("TrincheraVotacion")
util.AddNetworkString("TrincheraCamara")
util.AddNetworkString("TrincheraCamaraDuelo")

local ESPERA_ACEPTAR = 30 -- segundos para aceptar un reto
local DURACION_DUELO = 90 -- si nadie cae antes, es empate
local VELOCIDAD_LENTA = 0.35

local MORADO = Color(145, 70, 255)
local ROJO = Color(230, 60, 50)
local DORADO = Color(255, 200, 60)
local VERDE = Color(120, 210, 90)
local GRIS = Color(200, 200, 200)

local function Streamer()
	return player.GetHumans()[1]
end

local function EsJefe(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

local function NombreDe(npc)
	return npc.TrincheraViewer or "?"
end

-- Texto grande en el centro de la pantalla (cl_trinchera_eventos.lua).
local function Anuncio(titulo, subtitulo, color, duracion)
	net.Start("TrincheraAnuncio")
	net.WriteString(titulo)
	net.WriteString(subtitulo or "")
	net.WriteColor(color or color_white)
	net.WriteFloat(duracion or 4)
	net.Broadcast()
end

-- Un punto libre en el suelo cerca de "pos" donde cabe un NPC, o nil.
local function SueloLibre(pos)
	local suelo = util.TraceLine({ start = pos + Vector(0, 0, 64), endpos = pos - Vector(0, 0, 256), mask = MASK_NPCSOLID_BRUSHONLY })
	if not suelo.Hit or suelo.StartSolid then return end

	local p = suelo.HitPos + Vector(0, 0, 4)
	local hueco = util.TraceHull({ start = p, endpos = p, mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_NPCSOLID })
	if not hueco.Hit then return suelo.HitPos end
end

---------------------------------------------------------------------------
-- Duelos
---------------------------------------------------------------------------

local reto  -- { retador, rival, expira }  (usuarios de Twitch en minúsculas)
local duelo -- { a, b, nombreA, nombreB, fin, dispA, dispB }

-- Dos puntos frente al streamer, a los lados y a la vista, para que el duelo salga en cámara.
local function PuntosArena(ply)
	local giro = Angle(0, ply:EyeAngles().y, 0)
	local adelante, derecha = giro:Forward(), giro:Right()
	local ojo = ply:GetPos() + Vector(0, 0, 48)

	for _, distancia in ipairs({ 350, 250, 180 }) do
		local tr = util.TraceLine({ start = ojo, endpos = ojo + adelante * distancia, mask = MASK_NPCSOLID_BRUSHONLY })
		local centro = tr.HitPos - adelante * 40

		for _, separacion in ipairs({ 160, 110 }) do
			local a = SueloLibre(centro - derecha * separacion)
			local b = SueloLibre(centro + derecha * separacion)
			if a and b then
				local entre = util.TraceLine({ start = a + Vector(0, 0, 40), endpos = b + Vector(0, 0, 40), mask = MASK_NPCSOLID_BRUSHONLY })
				if not entre.Hit then return a, b end
			end
		end
	end
end

-- No puede pelear si está en el suelo por un resbalón o montado en un vehículo.
local function Ocupado(npc)
	return npc.TrincheraCaido or npc.TrincheraMontado
end

local function Atacar(npc, objetivo)
	npc:SetEnemy(objetivo)
	npc:UpdateEnemyMemory(objetivo, objetivo:GetPos())
end

-- Cámara automática del duelo en los clientes; sin argumentos, el duelo terminó.
local function CamaraDuelo(a, b)
	net.Start("TrincheraCamaraDuelo")
	net.WriteEntity(a or NULL)
	net.WriteEntity(b or NULL)
	net.Broadcast()
end

local function EmpezarDuelo(a, b)
	reto = nil

	for _, npc in ipairs({ a, b }) do
		npc.TrincheraSigue = nil
		npc.TrincheraDestino = nil
		npc.TrincheraDuelo = true
		npc:SetHealth(npc:GetMaxHealth())
	end

	local ply = Streamer()
	local pa, pb
	if IsValid(ply) then pa, pb = PuntosArena(ply) end
	if pa then
		a:SetPos(pa)
		b:SetPos(pb)
		a:SetAngles(Angle(0, (pb - pa):Angle().y, 0))
		b:SetAngles(Angle(0, (pa - pb):Angle().y, 0))
	end

	duelo = {
		a = a, b = b,
		nombreA = NombreDe(a), nombreB = NombreDe(b),
		fin = CurTime() + DURACION_DUELO,
		dispA = a:Disposition(b), dispB = b:Disposition(a),
	}

	a:AddEntityRelationship(b, D_HT, 99)
	b:AddEntityRelationship(a, D_HT, 99)
	Atacar(a, b)
	Atacar(b, a)

	CamaraDuelo(a, b)
	Anuncio("¡DUELO!", duelo.nombreA .. "  vs  " .. duelo.nombreB, ROJO, 4)
	TRINCHERA.Aviso(ROJO, "¡DUELO! ", color_white, duelo.nombreA, GRIS, " vs ", color_white, duelo.nombreB)
end

-- ganador: el NPC que quedó en pie; nil = empate o cancelado (motivo).
local function TerminarDuelo(ganador, motivo)
	local d = duelo
	if not d then return end
	duelo = nil
	CamaraDuelo()

	-- Vuelven a llevarse como antes del duelo.
	for _, par in ipairs({ { d.a, d.b, d.dispA }, { d.b, d.a, d.dispB } }) do
		local npc, otro, disp = par[1], par[2], par[3]
		if IsValid(npc) then
			npc.TrincheraDuelo = nil
			if IsValid(otro) then
				npc:AddEntityRelationship(otro, disp, 99)
				npc:ClearEnemyMemory(otro)
			end
		end
	end

	if IsValid(ganador) then
		local nombre = ganador == d.a and d.nombreA or d.nombreB
		local perdedor = ganador == d.a and d.nombreB or d.nombreA
		Anuncio(nombre .. " GANA", "derrotó a " .. perdedor .. " en duelo", DORADO, 5)
		TRINCHERA.Aviso(DORADO, nombre, GRIS, " ganó el duelo contra ", color_white, perdedor)
		TRINCHERA.GloboNPC(ganador, "*celebra su victoria*")
	else
		Anuncio("Duelo terminado", motivo, GRIS, 4)
		TRINCHERA.Aviso(GRIS, "Duelo entre ", color_white, d.nombreA, GRIS, " y ", color_white, d.nombreB, GRIS, ": " .. motivo)
	end
end

local function EnDuelo(npc)
	return duelo and (npc == duelo.a or npc == duelo.b)
end

hook.Add("OnNPCKilled", "TrincheraDuelo", function(npc)
	if not EnDuelo(npc) then return end
	local otro = npc == duelo.a and duelo.b or duelo.a
	if IsValid(otro) and otro:Health() > 0 then
		TerminarDuelo(otro)
	else
		TerminarDuelo(nil, "cayeron los dos")
	end
end)

-- Si uno desaparece (nuevo !spawn, limpieza, deshacer...), el duelo se cancela.
hook.Add("EntityRemoved", "TrincheraDuelo", function(ent)
	if EnDuelo(ent) then TerminarDuelo(nil, "uno abandonó la pelea") end
end)

TRINCHERA.EVENTOS.duelo = function(ev)
	if not TRINCHERA.Config().duelos then return end

	local retador = string.lower(tostring(ev.usuario or ""))
	local rival = string.lower(tostring(ev.rival or ""))
	if retador == "" or rival == "" or retador == rival then return end

	-- Sin NPC propio no se puede retar a nadie (y no se avisa, para no llenar el chat).
	local a = TRINCHERA.NPCDe(retador)
	if not a or not a:IsNPC() then return end

	if duelo or (reto and CurTime() < reto.expira) then
		TRINCHERA.Aviso(GRIS, "Ya hay un duelo en curso; ", color_white, NombreDe(a), GRIS, " tendrá que esperar")
		return
	end

	local b = TRINCHERA.NPCDe(rival)
	if not b or not b:IsNPC() then
		TRINCHERA.Aviso(color_white, NombreDe(a), GRIS, " quiere un duelo, pero ", color_white, rival, GRIS, " no tiene NPC en el mapa")
		return
	end

	reto = { retador = retador, rival = rival, expira = CurTime() + ESPERA_ACEPTAR }
	Anuncio("¡RETO A DUELO!", NombreDe(a) .. " reta a " .. NombreDe(b) .. "  ·  " .. NombreDe(b) .. ": escribe !aceptar", ROJO, 6)
	TRINCHERA.Aviso(ROJO, "¡Reto! ", color_white, NombreDe(a), GRIS, " reta a ", color_white, NombreDe(b),
		GRIS, ". Tiene " .. ESPERA_ACEPTAR .. " s para escribir ", color_white, "!aceptar", GRIS, " o ", color_white, "!rechazar")
end

TRINCHERA.EVENTOS.aceptar = function(ev)
	if not reto or string.lower(tostring(ev.usuario or "")) ~= reto.rival then return end

	local a, b = TRINCHERA.NPCDe(reto.retador), TRINCHERA.NPCDe(reto.rival)
	if not a or not b then
		reto = nil
		TRINCHERA.Aviso(GRIS, "El duelo se canceló: uno de los dos ya no tiene NPC")
		return
	end

	-- Si alguno está en el suelo o en un vehículo, el reto sigue en pie y puede volver a aceptar.
	for _, npc in ipairs({ a, b }) do
		if Ocupado(npc) then
			TRINCHERA.Aviso(color_white, NombreDe(npc), GRIS, " no puede pelear ahora mismo; intenta !aceptar en unos segundos")
			return
		end
	end

	EmpezarDuelo(a, b)
end

TRINCHERA.EVENTOS.rechazar = function(ev)
	if not reto or string.lower(tostring(ev.usuario or "")) ~= reto.rival then return end

	local b = TRINCHERA.NPCDe(reto.rival)
	TRINCHERA.Aviso(color_white, b and NombreDe(b) or reto.rival, GRIS, " rechazó el duelo")
	reto = nil
end

---------------------------------------------------------------------------
-- Eventos de las votaciones
---------------------------------------------------------------------------

local ZOMBIES = { "npc_zombie", "npc_zombie", "npc_fastzombie", "npc_poisonzombie" }

local function Horda(ply, cantidad)
	local ojo = ply:GetPos() + Vector(0, 0, 48)
	local n = 0

	for _ = 1, cantidad * 4 do
		if n >= cantidad then break end

		local dir = Angle(0, math.Rand(0, 360), 0):Forward()
		local tr = util.TraceLine({ start = ojo, endpos = ojo + dir * math.Rand(500, 1000), mask = MASK_NPCSOLID_BRUSHONLY })
		local pos = SueloLibre(tr.HitPos - dir * 32)

		if pos and pos:Distance(ply:GetPos()) > 300 then
			local z = ents.Create(ZOMBIES[math.random(#ZOMBIES)])
			z:SetPos(pos + Vector(0, 0, 4))
			z:SetAngles(Angle(0, (ply:GetPos() - pos):Angle().y, 0))
			z:Spawn()
			z:Activate()
			Atacar(z, ply)
			cleanup.Add(ply, "npcs", z)
			n = n + 1
		end
	end

	return n
end

local rebelion -- { ply, fin, previas = { npc -> disposición hacia el streamer } }

local function TerminarRebelion()
	local r = rebelion
	if not r then return end
	rebelion = nil

	for npc, disp in pairs(r.previas) do
		if IsValid(npc) and IsValid(r.ply) then
			npc:AddEntityRelationship(r.ply, disp, 99)
			npc:ClearEnemyMemory(r.ply)
		end
	end

	Anuncio("Fin de la rebelión", "Los NPCs del chat vuelven a la normalidad", VERDE, 4)
end

local function Rebelion(ply, duracion)
	TerminarRebelion()
	rebelion = { ply = ply, fin = CurTime() + duracion, previas = {} }

	for _, npc in ipairs(TRINCHERA.NPCsVivos()) do
		-- Los que van montados en el techo de un vehículo se quedan quietos.
		if npc:IsNPC() and not npc.TrincheraMontado then
			rebelion.previas[npc] = npc:Disposition(ply)
			npc:AddEntityRelationship(ply, D_HT, 99)
			Atacar(npc, ply)
		end
	end
end

-- Cámara lenta: todo el juego más despacio. Se mide en tiempo real, porque el del juego también va lento.
local lenta -- { fin }

local function TerminarLenta()
	if not lenta then return end
	lenta = nil
	game.SetTimeScale(1)
	SetGlobalBool("TrincheraLenta", false)
end

local function CamaraLenta(duracion)
	lenta = { fin = RealTime() + duracion }
	game.SetTimeScale(VELOCIDAD_LENTA)
	SetGlobalBool("TrincheraLenta", true)
end

local OPCIONES = {
	{
		nombre = "Horda zombie",
		Ejecutar = function(ply, ajustes)
			local n = Horda(ply, ajustes.horda)
			Anuncio("¡HORDA ZOMBIE!", n .. " zombies vienen por " .. ply:Nick(), ROJO, 5)
		end,
	},
	{
		nombre = "Rebelión",
		Ejecutar = function(ply, ajustes)
			Rebelion(ply, ajustes.rebelion)
			Anuncio("¡REBELIÓN!", "Los NPCs del chat atacan a " .. ply:Nick() .. " por " .. math.floor(ajustes.rebelion) .. " s", ROJO, 5)
		end,
	},
	{
		nombre = "Cámara lenta",
		Ejecutar = function(_, ajustes)
			CamaraLenta(ajustes.lenta)
			Anuncio("CÁMARA LENTA", "Todo va más despacio por " .. math.floor(ajustes.lenta) .. " s", MORADO, 4)
		end,
	},
}

TRINCHERA.EjecutarEvento = function(indice)
	local ply = Streamer()
	if IsValid(ply) and OPCIONES[indice] then OPCIONES[indice].Ejecutar(ply, TRINCHERA.Config().votacion) end
end

---------------------------------------------------------------------------
-- Votaciones
---------------------------------------------------------------------------

local votacion -- { fin, votos = { usuario -> opción }, cuenta = { opción -> votos }, cambio }

local function EnviarVotacion()
	net.Start("TrincheraVotacion")
	net.WriteBool(votacion ~= nil)
	if votacion then
		net.WriteFloat(votacion.fin)
		net.WriteUInt(#OPCIONES, 4)
		for i, o in ipairs(OPCIONES) do
			net.WriteString(o.nombre)
			net.WriteUInt(votacion.cuenta[i], 16)
		end
	end
	net.Broadcast()
end

local function AbrirVotacion()
	if votacion then return end

	local cuenta = {}
	for i = 1, #OPCIONES do cuenta[i] = 0 end
	votacion = { fin = CurTime() + TRINCHERA.Config().votacion.duracion, votos = {}, cuenta = cuenta }

	EnviarVotacion()
	Anuncio("¡VOTACIÓN!", "Escribe el número en el chat", MORADO, 4)
end

local function CerrarVotacion()
	local v = votacion
	votacion = nil
	EnviarVotacion()

	local mejores, maximo = {}, 0
	for i, n in ipairs(v.cuenta) do
		if n > maximo then
			mejores, maximo = { i }, n
		elseif n == maximo and n > 0 then
			table.insert(mejores, i)
		end
	end

	if maximo == 0 then
		Anuncio("Nadie votó", "No pasa nada... por ahora", GRIS, 4)
		return
	end

	-- Empate: decide la suerte.
	local ganador = mejores[math.random(#mejores)]
	TRINCHERA.Aviso(MORADO, "Votación: ", color_white, OPCIONES[ganador].nombre, GRIS, " gana con " .. maximo .. " voto" .. (maximo == 1 and "" or "s"))
	TRINCHERA.EjecutarEvento(ganador)
end

TRINCHERA.EVENTOS.votacion = AbrirVotacion

-- Los votos también salen en globo como cualquier mensaje.
TRINCHERA.EVENTOS.voto = function(ev)
	TRINCHERA.Decir(ev.usuario, ev.texto, ev.emotes)
	if not votacion then return end

	local usuario = string.lower(tostring(ev.usuario or ""))
	local opcion = math.floor(tonumber(ev.opcion) or 0)
	if usuario == "" or not OPCIONES[opcion] then return end

	-- Se puede cambiar de voto; cuenta el último.
	local anterior = votacion.votos[usuario]
	if anterior == opcion then return end
	if anterior then votacion.cuenta[anterior] = votacion.cuenta[anterior] - 1 end
	votacion.votos[usuario] = opcion
	votacion.cuenta[opcion] = votacion.cuenta[opcion] + 1
	votacion.cambio = true
end

---------------------------------------------------------------------------

timer.Create("TrincheraEventos", 0.5, 0, function()
	local ahora = CurTime()

	if reto and ahora >= reto.expira then
		local b = TRINCHERA.NPCDe(reto.rival)
		TRINCHERA.Aviso(color_white, b and NombreDe(b) or reto.rival, GRIS, " no aceptó el duelo a tiempo")
		reto = nil
	end

	if duelo then
		if ahora >= duelo.fin then
			TerminarDuelo(nil, "empate, nadie cayó a tiempo")
		elseif IsValid(duelo.a) and IsValid(duelo.b) then
			-- Que no se distraigan: se siguen buscando aunque se pierdan de vista.
			if duelo.a:GetEnemy() ~= duelo.b then Atacar(duelo.a, duelo.b) end
			if duelo.b:GetEnemy() ~= duelo.a then Atacar(duelo.b, duelo.a) end
		end
	end

	if votacion then
		if ahora >= votacion.fin then
			CerrarVotacion()
		elseif votacion.cambio then
			votacion.cambio = false
			EnviarVotacion()
		end
	end

	if rebelion and ahora >= rebelion.fin then TerminarRebelion() end
	if lenta and RealTime() >= lenta.fin then TerminarLenta() end
end)

---------------------------------------------------------------------------
-- Cámara: mientras el streamer mira desde un NPC, su cuerpo se queda quieto y es invulnerable.
-- Además se le manda lo que pasa alrededor del NPC, aunque esté lejos (si no, lo vería congelado).
---------------------------------------------------------------------------

net.Receive("TrincheraCamara", function(_, ply)
	if not ply:IsSuperAdmin() then return end
	local activa, npc = net.ReadBool(), net.ReadEntity()

	if activa then
		if ply.TrincheraDiosAntes == nil then ply.TrincheraDiosAntes = ply:HasGodMode() end
		ply:GodEnable()
		ply.TrincheraMirando = IsValid(npc) and npc or nil
	else
		ply.TrincheraMirando = nil
		if ply.TrincheraDiosAntes ~= nil then
			if not ply.TrincheraDiosAntes then ply:GodDisable() end
			ply.TrincheraDiosAntes = nil
		end
	end
end)

hook.Add("SetupPlayerVisibility", "TrincheraCamara", function(ply)
	if IsValid(ply.TrincheraMirando) then AddOriginToPVS(ply.TrincheraMirando:GetPos()) end
	if duelo then
		if IsValid(duelo.a) then AddOriginToPVS(duelo.a:GetPos()) end
		if IsValid(duelo.b) then AddOriginToPVS(duelo.b:GetPos()) end
	end
end)

---------------------------------------------------------------------------
-- Comandos de consola
---------------------------------------------------------------------------

concommand.Add("trinchera_votacion", function(ply)
	if EsJefe(ply) then AbrirVotacion() end
end)

-- trinchera_evento <horda|rebelion>: lanza el evento sin votar (para probar).
concommand.Add("trinchera_evento", function(ply, _, args)
	if not EsJefe(ply) then return end
	local cual = string.lower(args[1] or "")
	if cual == "horda" then
		TRINCHERA.EjecutarEvento(1)
	elseif cual == "rebelion" then
		TRINCHERA.EjecutarEvento(2)
	elseif cual == "lenta" then
		TRINCHERA.EjecutarEvento(3)
	else
		print("Uso: trinchera_evento horda | rebelion | lenta")
	end
end)

-- trinchera_duelo <usuario1> <usuario2>: duelo inmediato entre los NPCs de esos viewers (para probar).
concommand.Add("trinchera_duelo", function(ply, _, args)
	if not EsJefe(ply) or duelo then return end
	local a, b = TRINCHERA.NPCDe(args[1]), TRINCHERA.NPCDe(args[2])
	if a and b and a ~= b and a:IsNPC() and b:IsNPC() then EmpezarDuelo(a, b) end
end)
