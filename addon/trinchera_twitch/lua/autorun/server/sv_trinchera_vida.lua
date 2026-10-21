-- La Trinchera: vida propia de los NPCs de viewers (servidor)
--   - Libre albedrío: cuando están tranquilos, pasean solos por el mapa.
--   - Frases ambientales: si su viewer lleva rato sin escribir, el NPC dice algo al azar.
--     Las frases están en garrysmod/data/trinchera_frases.txt y se recargan solas al guardar el archivo.

if not TRINCHERA then include("autorun/sh_trinchera_estilos.lua") end

---------------------------------------------------------------------------
-- Libre albedrío
---------------------------------------------------------------------------

local OCUPADO = {
	[NPC_STATE_COMBAT] = true,
	[NPC_STATE_SCRIPT] = true,
	[NPC_STATE_PLAYDEAD] = true,
	[NPC_STATE_DEAD] = true,
}

local function Tranquilo(npc)
	return npc:IsNPC() and not IsValid(npc:GetEnemy()) and not OCUPADO[npc:GetNPCState()]
end

-- Con navmesh (nav_generate) se eligen puntos de zonas caminables reales.
local function DestinoNavmesh(origen, radio)
	if not navmesh.IsLoaded() then return end

	local areas = navmesh.Find(origen, radio, 64, 64)
	if #areas == 0 then return end

	for _ = 1, 5 do
		local area = areas[math.random(#areas)]
		if IsValid(area) and not area:IsUnderwater() then
			local punto = area:GetRandomPoint()
			if punto:DistToSqr(origen) > 100 * 100 then return punto end
		end
	end
end

-- Sin navmesh: un punto al azar en el suelo, sin atravesar paredes ni cambiar mucho de altura.
local function DestinoTrazos(origen, radio)
	local alto = origen + Vector(0, 0, 40)

	for _ = 1, 8 do
		local dir = Angle(0, math.Rand(0, 360), 0):Forward()
		local hacia = util.TraceLine({ start = alto, endpos = alto + dir * math.Rand(radio * 0.3, radio), mask = MASK_NPCSOLID_BRUSHONLY })
		local punto = hacia.HitPos - dir * 32

		if punto:DistToSqr(alto) > 120 * 120 then
			local suelo = util.TraceLine({ start = punto, endpos = punto - Vector(0, 0, 300), mask = MASK_NPCSOLID_BRUSHONLY })
			if suelo.Hit and not suelo.StartSolid and math.abs(suelo.HitPos.z - origen.z) < 120 then
				return suelo.HitPos
			end
		end
	end
end

---------------------------------------------------------------------------
-- Animaciones al azar
-- Cada modelo tiene animaciones distintas, así que se eligen de las que el modelo
-- realmente tiene, filtradas por nombre (saludos, señas, reacciones...).
-- Se reproducen con un scripted_sequence, igual que en las escenas de Half-Life 2;
-- si aparece un enemigo, la animación se interrumpe.
---------------------------------------------------------------------------

local ANIM_INTERESANTES = {
	"wave", "cheer", "lineidle", "signal", "react", "harass", "look", "fear", "scared",
	"idle_subtle", "stretch", "dance", "shrug", "point", "nod", "laugh", "yawn", "scratch",
	"salute", "taunt", "pace", "inspect", "think", "sit", "lean", "cower", "panic", "pray",
}

local ANIM_PROHIBIDAS = {
	"walk", "run", "sprint", "aim", "shoot", "fire", "reload", "jump", "land", "fall", "climb",
	"death", "die", "dead", "ragdoll", "layer", "delta", "gesture", "pose", "attack", "melee",
	"swing", "throw", "grenade", "cover", "crouch", "flinch", "pain", "turn", "spine", "ref",
	"bind", "physgun", "_entry", "_exit", "_to_", "transition",
}

local cacheAnimaciones = {} -- modelo -> lista de nombres de secuencias

local function Contiene(nombre, lista)
	for _, palabra in ipairs(lista) do
		if string.find(nombre, palabra, 1, true) then return true end
	end
	return false
end

local function AnimacionesDe(npc)
	local modelo = npc:GetModel() or ""
	if cacheAnimaciones[modelo] then return cacheAnimaciones[modelo] end

	local lista = {}
	for id, nombre in pairs(npc:GetSequenceList() or {}) do
		local n = string.lower(nombre)
		local duracion = npc:SequenceDuration(id)
		if Contiene(n, ANIM_INTERESANTES) and not Contiene(n, ANIM_PROHIBIDAS) and duracion >= 0.8 and duracion <= 12 then
			table.insert(lista, nombre)
		end
	end

	cacheAnimaciones[modelo] = lista
	return lista
end

local function Animar(npc)
	local lista = AnimacionesDe(npc)
	if #lista == 0 then return false end

	local nombre = lista[math.random(#lista)]
	local duracion = npc:SequenceDuration(npc:LookupSequence(nombre))

	if npc:GetName() == "" then npc:SetName("trinchera_npc_" .. npc:EntIndex()) end

	local guion = ents.Create("scripted_sequence")
	guion:SetPos(npc:GetPos())
	guion:SetAngles(npc:GetAngles())
	guion:SetKeyValue("m_iszEntity", npc:GetName())
	guion:SetKeyValue("m_iszPlay", nombre)
	guion:SetKeyValue("m_fMoveTo", "0")                 -- se queda donde está
	guion:SetKeyValue("spawnflags", tostring(128 + 4096)) -- no teletransportar al final, puede morir
	guion:Spawn()
	guion:Fire("BeginSequence")
	SafeRemoveEntityDelayed(guion, duracion + 2)

	npc.TrincheraOcupadoHasta = CurTime() + duracion + 0.5
	return true
end

---------------------------------------------------------------------------
-- Resbalones: mientras camina, a veces se cae como muñeco de trapo y luego se levanta.
-- El NPC real se esconde y sigue al muñeco (así el nombre y los globos van con él).
---------------------------------------------------------------------------

local SONIDOS_GOLPE = {
	"physics/body/body_medium_impact_hard1.wav",
	"physics/body/body_medium_impact_hard2.wav",
	"physics/body/body_medium_impact_hard3.wav",
	"physics/body/body_medium_impact_hard4.wav",
}

local ACCIONES_RESBALON = { "*se resbala*", "*pierde el equilibrio*", "*se cae de la forma más ridícula*", "*resbala con algo*" }

local function Levantar(npc)
	if not IsValid(npc) then return end
	local muneco = npc.TrincheraCaido
	npc.TrincheraCaido = nil
	timer.Remove("TrincheraCaido" .. npc:EntIndex())

	if IsValid(muneco) then
		local suelo = util.TraceLine({ start = muneco:GetPos() + Vector(0, 0, 16), endpos = muneco:GetPos() - Vector(0, 0, 128), mask = MASK_NPCSOLID_BRUSHONLY })
		npc:SetPos(suelo.HitPos + Vector(0, 0, 4))
		muneco:Remove()
	end

	npc:SetNoDraw(false)
	npc:SetNotSolid(false)
	npc:SetNWBool("TrincheraCaido", false)
	local arma = npc:GetActiveWeapon()
	if IsValid(arma) then arma:SetNoDraw(false) end

	npc:SetCondition(COND_NPC_UNFREEZE)
	npc:SetSchedule(SCHED_IDLE_STAND)
	npc:DropToFloor()
	npc.TrincheraOcupadoHasta = CurTime() + 1
end

local function Resbalar(npc)
	if npc.TrincheraCaido or npc.TrincheraMontado or not util.IsValidRagdoll(npc:GetModel() or "") then return end

	local muneco = ents.Create("prop_ragdoll")
	muneco:SetModel(npc:GetModel())
	muneco:SetPos(npc:GetPos())
	muneco:SetAngles(npc:GetAngles())
	muneco:SetSkin(npc:GetSkin())
	for i = 0, npc:GetNumBodyGroups() - 1 do muneco:SetBodygroup(i, npc:GetBodygroup(i)) end
	muneco:Spawn()
	muneco:Activate()
	muneco:SetCollisionGroup(COLLISION_GROUP_WEAPON) -- no estorba al jugador
	muneco.TrincheraDueno = npc

	-- El muñeco empieza en la misma pose que el NPC; las piernas salen hacia adelante y el torso hacia atrás.
	local adelante = npc:GetForward()
	local velocidad = npc:GetVelocity()
	for i = 0, muneco:GetPhysicsObjectCount() - 1 do
		local fisica = muneco:GetPhysicsObjectNum(i)
		local hueso = muneco:TranslatePhysBoneToBone(i)
		local matriz = npc:GetBoneMatrix(hueso)

		if IsValid(fisica) then
			if matriz then
				fisica:SetPos(matriz:GetTranslation())
				fisica:SetAngles(matriz:GetAngles())
			end

			fisica:Wake()
			local nombreHueso = string.lower(muneco:GetBoneName(hueso) or "")
			if Contiene(nombreHueso, { "calf", "foot", "thigh", "toe" }) then
				fisica:SetVelocity(velocidad + adelante * 320 + Vector(0, 0, 220))
			else
				fisica:SetVelocity(velocidad - adelante * 60)
			end
		end
	end

	muneco:EmitSound(SONIDOS_GOLPE[math.random(#SONIDOS_GOLPE)], 70, math.random(95, 110))

	-- Esconder al NPC real y congelarlo mientras está en el suelo.
	npc.TrincheraCaido = muneco
	npc:SetSchedule(SCHED_NPC_FREEZE)
	npc:SetNoDraw(true)
	npc:SetNotSolid(true)
	npc:SetNWBool("TrincheraCaido", true)
	local arma = npc:GetActiveWeapon()
	if IsValid(arma) then arma:SetNoDraw(true) end

	local config = TRINCHERA.Config()
	if config.globos then TRINCHERA.GloboNPC(npc, ACCIONES_RESBALON[math.random(#ACCIONES_RESBALON)]) end

	-- El NPC sigue al muñeco para que el nombre y los globos vayan encima del cuerpo.
	timer.Create("TrincheraCaido" .. npc:EntIndex(), 0.1, 0, function()
		if not IsValid(npc) or not IsValid(muneco) then
			if IsValid(npc) then Levantar(npc) end
			return
		end
		npc:SetPos(muneco:GetPos())
	end)

	timer.Simple(math.Rand(2.5, 4), function()
		if IsValid(npc) and npc.TrincheraCaido == muneco then Levantar(npc) end
	end)
end

-- Si le disparan al muñeco, el daño le llega al NPC (los golpes del propio muñeco contra el suelo no cuentan).
hook.Add("EntityTakeDamage", "TrincheraResbalon", function(ent, dano)
	local npc = ent.TrincheraDueno
	if not IsValid(npc) then return end
	if not dano:IsDamageType(DMG_CRUSH) and not dano:IsDamageType(DMG_PHYSGUN) then
		-- Si el golpe lo mata, primero se "levanta" (vuelve a ser visible) para que su cadáver no salga invisible.
		if dano:GetDamage() >= npc:Health() then Levantar(npc) end
		npc:TakeDamageInfo(dano)
	end
	return true
end)

-- Si el NPC muere o desaparece mientras está en el suelo, se quita el muñeco.
local function QuitarMuneco(npc)
	if IsValid(npc.TrincheraCaido) then npc.TrincheraCaido:Remove() end
	if npc.EntIndex then timer.Remove("TrincheraCaido" .. npc:EntIndex()) end
end
hook.Add("OnNPCKilled", "TrincheraResbalon", QuitarMuneco)
hook.Add("EntityRemoved", "TrincheraResbalon", function(ent)
	if ent.TrincheraCaido then QuitarMuneco(ent) end
end)

---------------------------------------------------------------------------

local function Pasear(npc, ajustes)
	local destino = DestinoNavmesh(npc:GetPos(), ajustes.radio) or DestinoTrazos(npc:GetPos(), ajustes.radio)
	if not destino then return end

	npc:SetLastPosition(destino)
	npc:SetSchedule(ajustes.correr and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)

	-- A veces, a mitad del camino, se resbala.
	if math.random() * 100 < ajustes.resbalon then
		timer.Simple(math.Rand(0.8, 2.5), function()
			if IsValid(npc) and Tranquilo(npc) and npc:GetVelocity():Length2D() > 20 then Resbalar(npc) end
		end)
	end
end

local function AlbedrioTick(config, ahora)
	local ajustes = config.albedrio
	if not ajustes.activo then return end

	for _, npc in ipairs(TRINCHERA.NPCsVivos()) do
		-- Los que siguen al jugador o están en un duelo no pasean por su cuenta.
		if npc:IsNPC() and not npc.TrincheraCaido and not npc.TrincheraSigue and not npc.TrincheraDuelo and ahora >= (npc.TrincheraOcupadoHasta or 0) then
			-- El primer paseo llega pronto; luego cada min..max segundos.
			npc.TrincheraProximoPaseo = npc.TrincheraProximoPaseo or (ahora + math.Rand(2, ajustes.min))

			if ahora >= npc.TrincheraProximoPaseo then
				npc.TrincheraProximoPaseo = ahora + math.Rand(ajustes.min, ajustes.max)

				if Tranquilo(npc) then
					-- A veces, en vez de pasear, hace una animación.
					local anima = math.random() * 100 < ajustes.animaciones and Animar(npc)
					if not anima then Pasear(npc, ajustes) end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Seguir al jugador: E sobre el NPC de un viewer para que te siga; E otra vez para soltarlo.
-- Si el jugador se sube a un vehículo, sus seguidores se suben al techo y van "surfeando".
---------------------------------------------------------------------------

local function NombreViewer(npc)
	return npc.TrincheraViewer or "Alguien"
end

-- Busca un punto libre en el suelo alrededor de "centro" para dejar a un NPC.
local function PuntoLibreCerca(centro)
	local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
	for _ = 1, 12 do
		local dir = Angle(0, math.Rand(0, 360), 0):Forward()
		local punto = centro + dir * math.Rand(70, 140) + Vector(0, 0, 40)
		local suelo = util.TraceLine({ start = punto, endpos = punto - Vector(0, 0, 200), mask = MASK_NPCSOLID_BRUSHONLY })
		if suelo.Hit and not suelo.StartSolid then
			local pos = suelo.HitPos + Vector(0, 0, 4)
			local hueco = util.TraceHull({ start = pos, endpos = pos, mins = mins, maxs = maxs, mask = MASK_NPCSOLID })
			if not hueco.Hit then return pos end
		end
	end
	return centro + Vector(0, 0, 8)
end

local function Montar(npc, vehiculo, lugar)
	if npc.TrincheraMontado or npc.TrincheraCaido then return end

	npc.TrincheraMontado = vehiculo
	npc.TrincheraMoveType = npc:GetMoveType()
	npc:SetSchedule(SCHED_NPC_FREEZE)
	npc:SetNotSolid(true)
	npc:SetMoveType(MOVETYPE_NONE)

	-- En el techo, de dos en dos hacia atrás.
	local fila = math.floor((lugar - 1) / 2)
	local lado = (lugar % 2 == 1) and -1 or 1
	local local_ = Vector(lado * 16, -fila * 34, vehiculo:OBBMaxs().z - 4)

	npc:SetPos(vehiculo:LocalToWorld(local_))
	npc:SetAngles(vehiculo:LocalToWorldAngles(Angle(0, 90, 0)))
	npc:SetParent(vehiculo)
end

local function Bajar(npc, cerca)
	local vehiculo = npc.TrincheraMontado
	if not vehiculo then return end
	npc.TrincheraMontado = nil

	npc:SetParent(nil)
	npc:SetPos(PuntoLibreCerca(cerca or (IsValid(vehiculo) and vehiculo:GetPos()) or npc:GetPos()))
	npc:SetAngles(Angle(0, npc:GetAngles().y, 0))
	npc:SetMoveType(npc.TrincheraMoveType or MOVETYPE_STEP)
	npc:SetNotSolid(false)
	npc:SetCondition(COND_NPC_UNFREEZE)
	npc:SetSchedule(SCHED_IDLE_STAND)
	npc:DropToFloor()
end

local function Seguir(npc, ply)
	npc.TrincheraSigue = ply
	npc.TrincheraDestino = nil
	TRINCHERA.GloboNPC(npc, "*" .. NombreViewer(npc) .. " te está siguiendo*")

	-- Si el jugador ya va en un vehículo, se sube de una vez.
	if ply:InVehicle() then
		local n = 0
		for _, otro in ipairs(TRINCHERA.NPCsVivos()) do
			if otro.TrincheraSigue == ply then n = n + 1 end
		end
		Montar(npc, ply:GetVehicle(), n)
	end
end

local function DejarDeSeguir(npc, avisar)
	local ply = npc.TrincheraSigue
	npc.TrincheraSigue = nil
	npc.TrincheraDestino = nil
	Bajar(npc, IsValid(ply) and ply:GetPos() or nil)

	if avisar then TRINCHERA.GloboNPC(npc, "*" .. NombreViewer(npc) .. " dejó de seguirte*") end
end

local function EsDeViewer(ent)
	return IsValid(ent) and ent:IsNPC() and ent:GetNWString("TrincheraNombre", "") ~= ""
end

-- El NPC de viewer que el jugador tiene enfrente (también si está en el suelo por un resbalón).
local function NPCDelante(ply)
	local tr = util.TraceHull({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 110,
		mins = Vector(-6, -6, -6),
		maxs = Vector(6, 6, 6),
		filter = ply,
		mask = MASK_SHOT_HULL,
	})

	local ent = tr.Entity
	if IsValid(ent) and IsValid(ent.TrincheraDueno) then ent = ent.TrincheraDueno end
	if EsDeViewer(ent) then return ent end
end

---------------------------------------------------------------------------
-- Dar armas: Shift + E sobre el NPC le da una copia del arma que tienes en la mano.
-- Con el botiquín en la mano, en vez de dárselo, lo cura.
---------------------------------------------------------------------------

local NOMBRES_ARMAS = {
	weapon_pistol = "una pistola",
	weapon_357 = "un revólver .357",
	weapon_smg1 = "una SMG",
	weapon_ar2 = "un rifle AR2",
	weapon_shotgun = "una escopeta",
	weapon_crossbow = "una ballesta",
	weapon_rpg = "un lanzacohetes",
	weapon_crowbar = "una palanca",
	weapon_stunstick = "una porra eléctrica",
	weapon_alyxgun = "la pistola de Alyx",
	weapon_annabelle = "a Annabelle",
	weapon_oldmanharpoon = "un arpón",
}

local function ArmaUsablePorNPC(clase)
	for _, v in pairs(list.Get("NPCUsableWeapons")) do
		if v.class == clase then return true end
	end
	return false
end

local function NombreArma(arma)
	local clase = arma:GetClass()
	if NOMBRES_ARMAS[clase] then return NOMBRES_ARMAS[clase] end

	local nombre = arma.GetPrintName and arma:GetPrintName() or ""
	if nombre == "" or string.sub(nombre, 1, 1) == "#" then return clase end
	return nombre
end

local function Curar(npc, botiquin)
	local vida, maxima = npc:Health(), npc:GetMaxHealth()
	if vida >= maxima then
		TRINCHERA.GloboNPC(npc, "*" .. NombreViewer(npc) .. " ya está sano*")
		return
	end

	local cura = math.min(maxima - vida, botiquin:Clip1())
	if cura <= 0 then
		npc:EmitSound("WallHealth.Deny")
		return
	end

	botiquin:SetClip1(botiquin:Clip1() - cura)
	npc:SetHealth(vida + cura)
	npc:EmitSound("HealthKit.Touch")
	TRINCHERA.GloboNPC(npc, "*" .. NombreViewer(npc) .. " fue curado*")
end

local function DarArma(ply, npc)
	local arma = ply:GetActiveWeapon()
	if not IsValid(arma) then return end

	if arma:GetClass() == "weapon_medkit" then
		Curar(npc, arma)
		return
	end

	-- Solo NPCs con manos (ciudadanos, combine...) y solo armas que el motor deja usar a NPCs.
	local puedeArmas = bit.band(npc:CapabilitiesGet(), CAP_USE_WEAPONS) ~= 0
	if not puedeArmas or not ArmaUsablePorNPC(arma:GetClass()) then
		TRINCHERA.GloboNPC(npc, "*" .. NombreViewer(npc) .. " no sabe usar eso*")
		return
	end

	-- Suelta lo que tenía antes (no se acumulan armas).
	local viejas = npc.GetWeapons and npc:GetWeapons() or { npc:GetActiveWeapon() }
	for _, vieja in ipairs(viejas) do
		if IsValid(vieja) then vieja:Remove() end
	end
	npc:Give(arma:GetClass())
	npc:EmitSound("items/ammo_pickup.wav")
	TRINCHERA.GloboNPC(npc, "*" .. NombreViewer(npc) .. " recibe " .. NombreArma(arma) .. "*")
end

-- Se usa KeyPress y no PlayerUse porque la mayoría de los NPCs (combine, zombies...) no son
-- "usables" para el motor y PlayerUse nunca se dispara con ellos.
hook.Add("KeyPress", "TrincheraSeguir", function(ply, tecla)
	if tecla ~= IN_USE or ply:InVehicle() then return end

	local npc = NPCDelante(ply)
	if not npc then return end

	-- En pleno duelo no se le puede pedir que te siga ni darle armas.
	if npc.TrincheraDuelo then
		ply:PrintMessage(HUD_PRINTCENTER, "Está en pleno duelo")
		return
	end

	if ply:KeyDown(IN_SPEED) then
		DarArma(ply, npc)
	elseif npc.TrincheraSigue == ply then
		DejarDeSeguir(npc, true)
	else
		Seguir(npc, ply)
	end
end)

-- Que la E sobre estos NPCs solo haga lo de seguir (sin las respuestas normales de los ciudadanos).
hook.Add("PlayerUse", "TrincheraSeguir", function(_, ent)
	if EsDeViewer(ent) then return false end
end)

hook.Add("PlayerEnteredVehicle", "TrincheraSeguir", function(ply, vehiculo)
	local lugar = 0
	for _, npc in ipairs(TRINCHERA.NPCsVivos()) do
		if npc.TrincheraSigue == ply then
			lugar = lugar + 1
			Montar(npc, vehiculo, lugar)
		end
	end
end)

hook.Add("PlayerLeaveVehicle", "TrincheraSeguir", function(ply)
	for _, npc in ipairs(TRINCHERA.NPCsVivos()) do
		if npc.TrincheraSigue == ply then Bajar(npc, ply:GetPos()) end
	end
end)

-- Caminar hacia el jugador (correr si está lejos). Solo se da una orden nueva si el jugador se movió.
timer.Create("TrincheraSeguir", 0.4, 0, function()
	if not TRINCHERA.NPCsVivos then return end

	for _, npc in ipairs(TRINCHERA.NPCsVivos()) do
		local ply = npc.TrincheraSigue
		if ply ~= nil then
			if not IsValid(ply) or not ply:Alive() then
				DejarDeSeguir(npc, false)
			elseif not npc.TrincheraMontado and not npc.TrincheraCaido and not IsValid(npc:GetEnemy()) then
				local objetivo = ply:GetPos()
				local distancia = npc:GetPos():Distance(objetivo)

				if distancia > 140 then
					local movido = not npc.TrincheraDestino or npc.TrincheraDestino:Distance(objetivo) > 60
					if movido or not npc:IsMoving() then
						npc.TrincheraDestino = objetivo
						npc:SetLastPosition(objetivo - (objetivo - npc:GetPos()):GetNormalized() * 80)
						npc:SetSchedule(distancia > 350 and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)
					end
				elseif npc:IsCurrentSchedule(SCHED_FORCED_GO) or npc:IsCurrentSchedule(SCHED_FORCED_GO_RUN) then
					npc.TrincheraDestino = nil
					npc:SetSchedule(SCHED_IDLE_STAND)
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Comandos para probar (mirando a un NPC de viewer, o uno al azar si no miras a ninguno)
---------------------------------------------------------------------------

local function NPCObjetivo(ply)
	if IsValid(ply) then
		local ent = ply:GetEyeTrace().Entity
		if IsValid(ent) and ent:IsNPC() then return ent end
	end
	local vivos = TRINCHERA.NPCsVivos()
	return vivos[math.random(#vivos)]
end

local function EsJefe(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

concommand.Add("trinchera_resbalar", function(ply)
	if not EsJefe(ply) then return end
	local npc = NPCObjetivo(ply)
	if IsValid(npc) then Resbalar(npc) end
end)

concommand.Add("trinchera_animar", function(ply)
	if not EsJefe(ply) then return end
	local npc = NPCObjetivo(ply)
	if IsValid(npc) and not Animar(npc) and IsValid(ply) then
		ply:PrintMessage(HUD_PRINTTALK, "Ese NPC no tiene animaciones interesantes.")
	end
end)

-- Lista las animaciones del NPC que miras: [*] = las que se usan al azar.
concommand.Add("trinchera_animaciones", function(ply)
	if not EsJefe(ply) then return end
	local npc = NPCObjetivo(ply)
	if not IsValid(npc) then return end

	local elegidas = {}
	for _, n in ipairs(AnimacionesDe(npc)) do elegidas[n] = true end

	local lineas = { "Animaciones de " .. npc:GetModel() .. "  ([*] = se usan al azar):" }
	for id, nombre in SortedPairs(npc:GetSequenceList() or {}) do
		table.insert(lineas, string.format("  %s %-40s %.1fs", elegidas[nombre] and "[*]" or "   ", nombre, npc:SequenceDuration(id)))
	end

	local texto = table.concat(lineas, "\n")
	if IsValid(ply) then
		for _, l in ipairs(lineas) do ply:PrintMessage(HUD_PRINTCONSOLE, l) end
		ply:PrintMessage(HUD_PRINTTALK, "Lista de animaciones en la consola (" .. #lineas - 1 .. ").")
	else
		print(texto)
	end
end)

---------------------------------------------------------------------------
-- Frases ambientales
---------------------------------------------------------------------------

local FRASES_ARCHIVO = "trinchera_frases.txt"

local FRASES_POR_DEFECTO = [=[
# ============================================================
#  La Trinchera - Frases ambientales
# ============================================================
#  Si un viewer lleva un rato sin escribir, su NPC dice una de
#  estas frases al azar.
#
#  - Una frase por línea. Agrega todas las que quieras.
#  - Las líneas que empiezan con # son comentarios.
#  - Si la frase empieza y termina con *asteriscos*, sale como
#    texto amarillo flotante (una acción o pensamiento),
#    no como globo de diálogo.
#  - {nombre} se reemplaza por el nombre del viewer.
#
#  Guarda el archivo y el juego lo recarga solo en unos segundos.
# ============================================================

# --- Diálogos ---
¿Alguien tiene un cigarrillo?
Huele a gas... ¡máscaras!
Mi madre cree que estoy en una granja.
"Estaremos en casa para Navidad", dijeron.
Otra vez lluvia. Otra vez barro.
¿Escuchaste eso? ...Solo son ratas.
Silbato en tres minutos.
Cuando acabe esto abro una panadería.
Le escribí a Marie. Todavía no contesta.
Mi fusil tiene más barro que balas.
Las botas me están matando más que el enemigo.
Té frío y galletas duras. Delicioso.
¿Esa es nuestra artillería o la de ellos?
Nadie cruza la tierra de nadie dos veces.
Soy {nombre} y no pienso morir en esta trinchera.
Hace frío en esta trinchera.
Un día más, un día menos.
Ph'nglui mglw'nafh Cthulhu R'lyeh wgah'nagl fhtagn.
¿Escuchaste eso bajo la tierra?
Los ángulos de este lugar están mal...
No mires al cielo esta noche.
El mar me llama por mi nombre.
Leí una página de más.
¡Iä! ¡Iä!
Las estrellas casi están en posición.
Mis sueños ya no son míos.
Hay algo detrás de la niebla. Siempre lo hay.
Innsmouth no está tan mal... si te gustan los peces.
No es locura si todos lo vemos.
Siento que alguien escribe sobre mí en un chat.
¿Alguien más tiene hambre?
Saludos al chat.
¿Qué hora es?
Me aburro...
Yo no fui.
¿Y ahora qué hacemos?
Creo que dejé la estufa prendida.
¿Esto cuenta como horas extra?
Nadie me dijo que habría zombies.
Necesito vacaciones.
¿Alguien vio mi cartera?
Juraría que esta pared antes no estaba aquí.
Chat, ¿me ven?
No estoy perdido, estoy explorando.
Esto no venía en el contrato.
¿Quién apagó las luces?
Si me muero, que suene algo épico.
Tengo un mal presentimiento.
Shhh... creo que algo nos mira.
Hoy sí sobrevivo. Creo.
¿Y si mejor nos vamos de aquí?
Ese barril me mira raro.
No me pagan lo suficiente para esto.
Prometo que esta vez no huyo.
Me duele todo y no sé por qué.
Ya casi es hora de comer, ¿no?
Cuando sea grande quiero ser personaje principal.
Esto huele a emboscada.
Necesito un café... o diez.
Estoy bien. Todo bien. Perfectamente bien.
¿Alguien sabe dónde está la salida?
Yo solo vine por los snacks.
¿Quién dejó esa caja ahí?
Primero muerto que sin estilo.
¿Somos los buenos o los malos?
No toques eso.
Esto ya lo viví... déjà vu.
Ay, mi espalda.
¿Alguien más escucha música?
Pensé que esto sería más tranquilo.
Juro que vi algo moverse.
Si alguien pregunta, yo estaba aquí todo el tiempo.
Mi plan es infalible. Bueno, casi.
No confíes en nadie. Ni en mí.
¿Y si todo esto es un sueño?
Tengo hambre de aventuras. Y de tacos.

# --- Acciones y pensamientos ---
*se rasca la cabeza*
*bosteza ruidosamente*
*mira al horizonte con nostalgia*
*silba una canción vieja*
*revisa sus bolsillos vacíos*
*estornuda*
*se ata las botas*
*limpia su arma con cuidado*
*cuenta sus balas... otra vez*
*escribe una carta que nunca enviará*
*mira fijamente a la cámara*
*finge que no pasa nada*
*tararea algo desafinado*
*se estira*
*murmura algo ininteligible*
*escucha un susurro que nadie más oye*
*dibuja símbolos extraños en el suelo*
*se tapa los oídos*
*tiembla sin razón aparente*
*sonríe demasiado*
*cuenta las estrellas*
*se le cae algo y finge que fue a propósito*
*olfatea el aire*
*saluda a nadie*
*piensa en su hogar*
*suspira profundamente*
*se queda mirando una pared*
*hace guardia con mucha seriedad*
*se esconde detrás de algo*
*revisa que nadie lo esté mirando*
*baila un poquito*
*reza en voz baja*
*juega con una piedrita*
*come una galleta dura*
*pisa un charco*
*mira al chat*
*sospecha de todos*
*practica su saludo militar*
*se sacude el barro*
*escucha pasos a lo lejos*
*se acomoda el casco*
*cierra los ojos un momento*
*lee un mapa al revés*
*aplaude solo*
*le habla a una rata*
*ve algo moverse en la sombra*
*se ríe de un chiste que nadie contó*
*piensa en tacos*
*se pregunta qué hace aquí*
*tiene un mal presentimiento*
]=]

local frases = {}
local fechaArchivo
local ultimaFrase
local proximaFrase = 0

local function LeerFrases(texto)
	texto = string.gsub(texto, "^\239\187\191", "") -- BOM del Bloc de notas
	local resultado = {}

	for linea in string.gmatch(texto .. "\n", "(.-)\r?\n") do
		linea = string.Trim(linea)
		-- Se ignoran comentarios y los encabezados [ ... ] de versiones anteriores.
		local esEncabezado = string.match(linea, "^%[.*%]$") ~= nil
		if linea ~= "" and string.sub(linea, 1, 1) ~= "#" and not esEncabezado then
			table.insert(resultado, linea)
		end
	end

	return resultado
end

local function RevisarArchivoFrases()
	if not file.Exists(FRASES_ARCHIVO, "DATA") then
		file.Write(FRASES_ARCHIVO, FRASES_POR_DEFECTO)
	end

	local fecha = file.Time(FRASES_ARCHIVO, "DATA")
	if fecha == fechaArchivo then return end
	fechaArchivo = fecha

	frases = LeerFrases(file.Read(FRASES_ARCHIVO, "DATA") or "")
	print("[La Trinchera] Frases ambientales cargadas: " .. #frases)
end

RevisarArchivoFrases()
timer.Create("TrincheraFrasesArchivo", 5, 0, RevisarArchivoFrases)

local function FrasePara(npc)
	if #frases == 0 then return end

	local frase = frases[math.random(#frases)]
	if frase == ultimaFrase and #frases > 1 then frase = frases[math.random(#frases)] end
	ultimaFrase = frase

	return string.Replace(frase, "{nombre}", npc.TrincheraViewer or "")
end

-- Para los duelos (sv_trinchera_eventos.lua): a veces sueltan una frase ambiental en plena pelea.
TRINCHERA.FraseAmbiental = FrasePara

-- Cada "cada" segundos (con algo de azar), un NPC cuyo viewer lleva "silencio" segundos callado dice algo.
local function FrasesTick(config, ahora, forzar)
	local ajustes = config.frases
	if not forzar and (not ajustes.activo or not config.globos or ahora < proximaFrase) then return end
	proximaFrase = ahora + ajustes.cada * math.Rand(0.7, 1.3)

	local candidatos = {}
	for _, npc in ipairs(TRINCHERA.NPCsVivos()) do
		if forzar or ahora - (npc.TrincheraUltimoHabla or 0) >= ajustes.silencio then
			table.insert(candidatos, npc)
		end
	end
	if #candidatos == 0 then return end

	local npc = candidatos[math.random(#candidatos)]
	local frase = FrasePara(npc)
	if not frase then return end

	npc.TrincheraUltimoHabla = ahora
	TRINCHERA.GloboNPC(npc, frase)
end

---------------------------------------------------------------------------

timer.Create("TrincheraVida", 1, 0, function()
	local config = TRINCHERA.Config and TRINCHERA.Config()
	if not config then return end

	local ahora = CurTime()
	AlbedrioTick(config, ahora)
	FrasesTick(config, ahora)
end)

-- trinchera_frase: un NPC al azar dice una frase ahora mismo (para probar).
concommand.Add("trinchera_frase", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	FrasesTick(TRINCHERA.Config(), CurTime(), true)
end)
