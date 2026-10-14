-- La Trinchera: cámara en tercera persona sobre el NPC de un viewer (cliente)
--   trinchera_ver            -> pasa al siguiente NPC de viewer
--   trinchera_ver <usuario>  -> va directo al NPC de ese viewer
--   trinchera_ver_salir      -> vuelve a tu cámara
-- Mientras miras, tu personaje se queda quieto y es invulnerable.
-- En los duelos, una cámara lateral muestra a los dos (trinchera_camara_duelo 0 para desactivarla).

if not TRINCHERA then include("autorun/sh_trinchera_estilos.lua") end

local camaraDuelo = CreateClientConVar("trinchera_camara_duelo", "1", true, false, "Cámara automática en los duelos de La Trinchera")

surface.CreateFont("TrincheraCamara", { font = "Roboto", size = 26, weight = 800, antialias = true, extended = true })
surface.CreateFont("TrincheraCamaraAyuda", { font = "Roboto", size = 18, weight = 500, antialias = true, extended = true })

local DISTANCIA = 90         -- detrás del NPC (más la mitad de su altura)
local HOMBRO = 24            -- hacia la derecha, para no tapar al NPC
local ESPERA_MUERTO = 3      -- segundos mirando el cadáver antes de volver
local ESPERA_FIN_DUELO = 3   -- segundos para ver al ganador celebrar
local MORADO = Color(145, 70, 255)

local objetivo   -- NPC que se está mirando (o nil)
local cadaver    -- su ragdoll de cliente, si murió
local soltarEn   -- RealTime en que se vuelve a la cámara propia tras su muerte
local duelo      -- { a, b, lado, terminaEn } mientras la cámara del duelo está activa
local pos, ang   -- cámara actual (suavizada)
local angJugador -- hacia dónde miraba el jugador al empezar; se conserva al volver
local ayudaHasta = 0

local function Activa()
	return objetivo ~= nil or duelo ~= nil
end

-- El servidor te hace invulnerable y te manda lo que pasa alrededor del NPC aunque esté lejos de ti.
local function AvisarServidor()
	net.Start("TrincheraCamara")
	net.WriteBool(Activa())
	net.WriteEntity(IsValid(objetivo) and objetivo or NULL)
	net.SendToServer()
end

local function Empezar()
	if Activa() then return end
	angJugador = LocalPlayer():EyeAngles()
	pos, ang = nil, nil
	ayudaHasta = RealTime() + 5
end

local function Ver(npc)
	Empezar()
	objetivo, cadaver, soltarEn = npc, nil, nil
	AvisarServidor()
end

local function Salir()
	local estaba = Activa()
	objetivo, duelo, cadaver, soltarEn = nil, nil, nil, nil
	if estaba then AvisarServidor() end
end

local function NombreDe(ent)
	return ent:GetNWString("TrincheraNombre", "")
end

-- Al morir, el NPC se borra (queda su ragdoll), así que basta con que siga existiendo.
local function NPCsDeViewers()
	local lista = {}
	for _, ent in ents.Iterator() do
		if (ent:IsNPC() or ent:IsNextBot()) and NombreDe(ent) ~= "" then
			table.insert(lista, ent)
		end
	end
	table.sort(lista, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return lista
end

---------------------------------------------------------------------------
-- Encuadres
---------------------------------------------------------------------------

-- Acerca la cámara si hay una pared entre el punto de giro y donde querría estar.
local function SinParedes(desde, hasta, filtro)
	local tr = util.TraceHull({
		start = desde, endpos = hasta,
		mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
		mask = MASK_SOLID_BRUSHONLY, filter = filtro,
	})
	return tr.HitPos
end

-- Detrás y un poco a la derecha del NPC, mirando hacia donde mira él.
local function EncuadreNPC(npc)
	local alto = npc:OBBMaxs().z
	local pivote = npc:GetPos() + Vector(0, 0, math.Clamp(alto * 0.85, 20, 160))
	local giro = Angle(12, npc:GetAngles().y, 0)
	local deseada = pivote - giro:Forward() * (DISTANCIA + alto * 0.5) + giro:Right() * HOMBRO
	return SinParedes(pivote, deseada, { npc, LocalPlayer() }), giro
end

-- Cuerpo en el suelo: la cámara se queda donde estaba y lo mira.
local function EncuadreCadaver(rag)
	local centro = rag:WorldSpaceCenter()
	local desde = pos or (centro + Vector(-120, 0, 60))
	return desde, (centro - desde):Angle()
end

-- Plano lateral con los dos duelistas. Se queda del mismo lado salvo que una pared lo tape.
local function EncuadreDuelo(d)
	local pa, pb = d.a:WorldSpaceCenter(), d.b:WorldSpaceCenter()
	local medio = (pa + pb) / 2
	local lado = (pb - pa):GetNormalized():Cross(Vector(0, 0, 1))
	local distancia = math.max(200, pa:Distance(pb) * 0.9)

	local function Hasta(signo)
		local deseada = medio + lado * signo * distancia + Vector(0, 0, 60)
		return SinParedes(medio, deseada, { d.a, d.b, LocalPlayer() }), deseada
	end

	local real, deseada = Hasta(d.lado)
	if real:Distance(deseada) > distancia * 0.4 then
		local otroReal, otroDeseada = Hasta(-d.lado)
		if otroReal:Distance(otroDeseada) < real:Distance(deseada) then
			d.lado = -d.lado
			real = otroReal
		end
	end

	return real, (medio - real):Angle()
end

-- Dónde debería estar la cámara ahora; nil = ya no hay nada que mirar.
local function Deseada()
	if duelo then
		local a, b = duelo.a, duelo.b
		local vivoA, vivoB = IsValid(a), IsValid(b)
		if duelo.terminaEn and RealTime() > duelo.terminaEn then
			duelo = nil
			AvisarServidor()
		elseif vivoA and vivoB then
			return EncuadreDuelo(duelo)
		elseif vivoA or vivoB then
			return EncuadreNPC(vivoA and a or b) -- el ganador celebrando
		elseif not objetivo and pos then
			return pos, ang -- cayeron los dos: la cámara se queda quieta hasta volver
		end
	end

	if objetivo then
		if IsValid(objetivo) then return EncuadreNPC(objetivo) end

		-- Murió: unos segundos sobre su cadáver y de vuelta a tu cámara.
		soltarEn = soltarEn or (RealTime() + ESPERA_MUERTO)
		if RealTime() > soltarEn then
			objetivo = nil
			AvisarServidor()
			return
		end
		if IsValid(cadaver) then return EncuadreCadaver(cadaver) end
		if pos then return pos, ang end
	end
end

hook.Add("CreateClientsideRagdoll", "TrincheraCamara", function(npc, rag)
	if npc == objetivo then cadaver = rag end
end)

---------------------------------------------------------------------------
-- Vista, controles y HUD
---------------------------------------------------------------------------

hook.Add("CalcView", "TrincheraCamara", function(_, _, _, fov)
	if not Activa() then return end

	local p, a = Deseada()
	if not p then return end

	-- Suavizado en tiempo real, para que no se vuelva perezosa con la cámara lenta.
	local t = math.min(RealFrameTime() * 6, 1)
	pos = pos and LerpVector(t, pos, p) or p
	ang = ang and LerpAngle(t, ang, a) or a

	return { origin = pos, angles = ang, fov = fov, drawviewer = true }
end)

-- Tu personaje se queda quieto y mirando hacia donde miraba; los binds (F7, F8...) siguen funcionando.
hook.Add("CreateMove", "TrincheraCamara", function(cmd)
	if not Activa() then return end
	cmd:ClearMovement()
	cmd:ClearButtons()
	if angJugador then cmd:SetViewAngles(angJugador) end
end)

hook.Add("PreDrawViewModel", "TrincheraCamara", function()
	if Activa() then return true end
end)

hook.Add("HUDShouldDraw", "TrincheraCamara", function(nombre)
	if Activa() and nombre == "CHudCrosshair" then return false end
end)

hook.Add("HUDPaint", "TrincheraCamara", function()
	if not Activa() then return end

	local texto
	if duelo and IsValid(duelo.a) and IsValid(duelo.b) then
		texto = "DUELO  ·  " .. NombreDe(duelo.a) .. " vs " .. NombreDe(duelo.b)
	elseif IsValid(objetivo) then
		texto = "VIENDO A  " .. NombreDe(objetivo)
	end
	if not texto then return end

	surface.SetFont("TrincheraCamara")
	local w, h = surface.GetTextSize(texto)
	draw.RoundedBox(6, 24, 24, w + 28, h + 12, ColorAlpha(MORADO, 220))
	draw.SimpleText(texto, "TrincheraCamara", 38, 30, color_white)

	if RealTime() < ayudaHasta then
		draw.SimpleTextOutlined("trinchera_ver: siguiente   ·   trinchera_ver_salir: volver", "TrincheraCamaraAyuda",
			24, 24 + h + 20, Color(230, 230, 230), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0))
	end
end)

---------------------------------------------------------------------------
-- Cámara automática de los duelos (la manda el servidor)
---------------------------------------------------------------------------

net.Receive("TrincheraCamaraDuelo", function()
	local a, b = net.ReadEntity(), net.ReadEntity()

	if IsValid(a) and IsValid(b) then
		if not camaraDuelo:GetBool() then return end
		Empezar()
		duelo = { a = a, b = b, lado = 1 }
		AvisarServidor()
	elseif duelo then
		-- Terminó: unos segundos más para ver al ganador y vuelve a lo que estabas viendo.
		duelo.terminaEn = RealTime() + ESPERA_FIN_DUELO
	end
end)

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------

concommand.Add("trinchera_ver", function(_, _, args)
	local lista = NPCsDeViewers()
	if #lista == 0 then
		chat.AddText(MORADO, "[Twitch] ", color_white, "No hay NPCs de viewers para mirar")
		return
	end

	local buscado = string.lower(args[1] or "")
	if buscado ~= "" then
		for _, npc in ipairs(lista) do
			if npc:GetNWString("TrincheraUsuario", "") == buscado or string.lower(NombreDe(npc)) == buscado then
				Ver(npc)
				return
			end
		end
		chat.AddText(MORADO, "[Twitch] ", color_white, "No hay un NPC de '" .. buscado .. "'")
		return
	end

	-- El siguiente después del que se está mirando.
	local siguiente = lista[1]
	for i, npc in ipairs(lista) do
		if npc == objetivo then
			siguiente = lista[i % #lista + 1]
			break
		end
	end
	Ver(siguiente)
end)

concommand.Add("trinchera_ver_salir", Salir)
