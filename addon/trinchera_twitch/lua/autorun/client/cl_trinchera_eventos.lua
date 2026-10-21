-- La Trinchera: anuncios en pantalla y panel de votación (cliente)

if not TRINCHERA then include("autorun/sh_trinchera_estilos.lua") end

surface.CreateFont("TrincheraAnuncioTitulo", { font = "Roboto", size = 84, weight = 900, antialias = true, extended = true })
surface.CreateFont("TrincheraAnuncioSub", { font = "Roboto", size = 34, weight = 700, antialias = true, extended = true })
surface.CreateFont("TrincheraVotoTitulo", { font = "Roboto", size = 28, weight = 900, antialias = true, extended = true })
surface.CreateFont("TrincheraVoto", { font = "Roboto", size = 24, weight = 700, antialias = true, extended = true })

local MORADO = Color(145, 70, 255)
local FONDO = Color(20, 20, 24, 220)
local BARRA = Color(60, 60, 68)
local NEGRO = Color(0, 0, 0)

---------------------------------------------------------------------------
-- Anuncio: título grande con subtítulo, arriba al centro. Entra creciendo y se desvanece.
---------------------------------------------------------------------------

local anuncio -- { titulo, sub, color, inicio, fin }

net.Receive("TrincheraAnuncio", function()
	local titulo, sub = net.ReadString(), net.ReadString()
	local color = net.ReadColor()
	local duracion = net.ReadFloat()
	-- En tiempo real: con la cámara lenta el tiempo del juego va más despacio.
	anuncio = { titulo = titulo, sub = sub, color = color, inicio = RealTime(), fin = RealTime() + duracion }
	surface.PlaySound("buttons/bell1.wav")
end)

local function DibujarAnuncio(ahora)
	if not anuncio then return end
	if ahora > anuncio.fin then
		anuncio = nil
		return
	end

	local entrada = math.Clamp((ahora - anuncio.inicio) / 0.25, 0, 1)
	local salida = math.Clamp((anuncio.fin - ahora) / 0.6, 0, 1)
	local a = 255 * math.min(entrada, salida)
	local x, y = ScrW() / 2, ScrH() * 0.2 - (1 - entrada) * 30

	draw.SimpleTextOutlined(anuncio.titulo, "TrincheraAnuncioTitulo", x, y, ColorAlpha(anuncio.color, a),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 4, ColorAlpha(NEGRO, a))
	if anuncio.sub ~= "" then
		draw.SimpleTextOutlined(anuncio.sub, "TrincheraAnuncioSub", x, y + 62, Color(255, 255, 255, a),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, ColorAlpha(NEGRO, a))
	end
end

---------------------------------------------------------------------------
-- Votación: panel a la derecha con las opciones, los votos en vivo y el tiempo que queda.
---------------------------------------------------------------------------

local votacion -- { fin, opciones = { { nombre, votos } } }

net.Receive("TrincheraVotacion", function()
	if not net.ReadBool() then
		votacion = nil
		return
	end

	local fin = net.ReadFloat()
	local opciones = {}
	for _ = 1, net.ReadUInt(4) do
		table.insert(opciones, { nombre = net.ReadString(), votos = net.ReadUInt(16) })
	end
	votacion = { fin = fin, opciones = opciones }
end)

local function DibujarVotacion(ahora)
	if not votacion then return end

	local total = 0
	for _, o in ipairs(votacion.opciones) do total = total + o.votos end

	local w, filaAlto = 340, 46
	local h = 78 + #votacion.opciones * filaAlto + 8
	local x, y = ScrW() - w - 24, ScrH() * 0.3

	draw.RoundedBox(8, x, y, w, h, FONDO)
	draw.RoundedBoxEx(8, x, y, w, 36, MORADO, true, true, false, false)

	local quedan = math.max(0, math.ceil(votacion.fin - ahora))
	draw.SimpleText("VOTACIÓN", "TrincheraVotoTitulo", x + 12, y + 18, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(quedan .. " s", "TrincheraVotoTitulo", x + w - 12, y + 18, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.SimpleText("Escribe el número en el chat", "TrincheraVoto", x + 12, y + 56, Color(200, 200, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	for i, o in ipairs(votacion.opciones) do
		local fy = y + 78 + (i - 1) * filaAlto
		local parte = total > 0 and o.votos / total or 0

		draw.RoundedBox(6, x + 10, fy, w - 20, filaAlto - 8, BARRA)
		if parte > 0 then draw.RoundedBox(6, x + 10, fy, (w - 20) * parte, filaAlto - 8, ColorAlpha(MORADO, 200)) end

		local cy = fy + (filaAlto - 8) / 2
		draw.SimpleText(i .. "   " .. o.nombre, "TrincheraVoto", x + 20, cy, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(tostring(o.votos), "TrincheraVoto", x + w - 20, cy, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

---------------------------------------------------------------------------
-- Duelo: barras de vida a los lados y reloj al centro, arriba, como en un juego de pelea.
-- La vida se queda pegada al borde exterior y un tramo naranja muestra el último golpe.
---------------------------------------------------------------------------

surface.CreateFont("TrincheraDueloReloj", { font = "Roboto", size = 60, weight = 900, antialias = true, extended = true })
surface.CreateFont("TrincheraDueloNombre", { font = "Roboto", size = 26, weight = 800, antialias = true, extended = true })
surface.CreateFont("TrincheraDueloArma", { font = "Roboto", size = 20, weight = 600, antialias = true, extended = true })

local ROJO = Color(230, 60, 50)
local NARANJA = Color(255, 140, 50)
local FONDO_BARRA = Color(50, 22, 22)

local estadoDuelo -- { nombres, fin, arma, vidas = { { vida, max } x2 }, mostradas, inicio, cierre }
local ultimoSegundo

net.Receive("TrincheraDueloEstado", function()
	local terminado = net.ReadBool()
	local nombreA, nombreB = net.ReadString(), net.ReadString()
	local fin, arma = net.ReadFloat(), net.ReadString()
	local vidas = {}
	for i = 1, 2 do vidas[i] = { vida = net.ReadUInt(20), max = net.ReadUInt(20) } end

	-- Duelo nuevo: las barras entran llenas.
	if not estadoDuelo or estadoDuelo.fin ~= fin then
		estadoDuelo = { inicio = RealTime(), mostradas = { 1, 1 } }
		ultimoSegundo = nil
	end
	estadoDuelo.nombres = { nombreA, nombreB }
	estadoDuelo.fin, estadoDuelo.arma, estadoDuelo.vidas = fin, arma, vidas
	if terminado then estadoDuelo.cierre = RealTime() + 3.5 end
end)

local function ColorVida(f)
	if f > 0.5 then return Color(90, 200, 70) end
	if f > 0.25 then return Color(240, 200, 40) end
	return ROJO
end

local function DibujarDuelo(ahora)
	local e = estadoDuelo
	if not e then return end
	if e.cierre and ahora > e.cierre then
		estadoDuelo = nil
		return
	end

	local entrada = math.Clamp((ahora - e.inicio) / 0.3, 0, 1)
	local a = 255 * (e.cierre and math.Clamp((e.cierre - ahora) / 0.8, 0, 1) or 1)
	local cx = ScrW() / 2
	local y = 30 - (1 - entrada) * 120
	local anchoBarra, altoBarra, hueco = math.min(560, ScrW() * 0.34), 30, 72

	for i = 1, 2 do
		local v = e.vidas[i]
		local f = math.Clamp(v.vida / math.max(1, v.max), 0, 1)
		e.mostradas[i] = math.max(f, math.Approach(e.mostradas[i], f, RealFrameTime() * 0.35))
		local m = e.mostradas[i]

		local izquierda = i == 1
		local x = izquierda and (cx - hueco - anchoBarra) or (cx + hueco)

		draw.RoundedBox(4, x - 3, y - 3, anchoBarra + 6, altoBarra + 6, ColorAlpha(NEGRO, a * 0.85))
		surface.SetDrawColor(FONDO_BARRA.r, FONDO_BARRA.g, FONDO_BARRA.b, a)
		surface.DrawRect(x, y, anchoBarra, altoBarra)

		-- Tramo entre "desde" y "hasta", medidos desde el borde exterior (0) hacia el reloj (1).
		local function Tramo(desde, hasta, col)
			local w = anchoBarra * (hasta - desde)
			if w <= 0 then return end
			local bx = izquierda and (x + anchoBarra * desde) or (x + anchoBarra * (1 - hasta))
			surface.SetDrawColor(col.r, col.g, col.b, a)
			surface.DrawRect(bx, y, w, altoBarra)
		end

		Tramo(f, m, NARANJA)
		local col = ColorVida(f)
		if f > 0 and f <= 0.25 and math.sin(ahora * 14) > 0 then col = color_white end -- a punto de perder: parpadea
		Tramo(0, f, col)

		local texto = e.nombres[i] .. "   " .. math.ceil(f * 100) .. " %"
		draw.SimpleTextOutlined(texto, "TrincheraDueloNombre", izquierda and x or (x + anchoBarra), y + altoBarra + 6,
			Color(255, 255, 255, a), izquierda and TEXT_ALIGN_LEFT or TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 2, ColorAlpha(NEGRO, a))
	end

	-- Reloj. Los últimos 10 segundos va en rojo y hace tic.
	local segundos = math.max(0, math.ceil(e.fin - CurTime()))
	if not e.cierre and segundos <= 10 and segundos > 0 and segundos ~= ultimoSegundo then
		ultimoSegundo = segundos
		surface.PlaySound("buttons/blip1.wav")
	end

	local reloj, colReloj = tostring(segundos), color_white
	if e.cierre then
		local ko = e.vidas[1].vida <= 0 or e.vidas[2].vida <= 0
		reloj, colReloj = ko and "K.O." or "0", ROJO
	elseif segundos <= 10 then
		colReloj = ColorAlpha(ROJO, 255 * (0.6 + 0.4 * math.abs(math.sin(ahora * 6))))
	end

	draw.RoundedBox(8, cx - 64, y - 16, 128, 66, ColorAlpha(FONDO, a))
	draw.SimpleTextOutlined(reloj, "TrincheraDueloReloj", cx, y + 17, ColorAlpha(colReloj, a * colReloj.a / 255),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, ColorAlpha(NEGRO, a))
	if e.arma ~= "" then
		draw.SimpleTextOutlined(e.arma, "TrincheraDueloArma", cx, y + 60, Color(230, 230, 230, a),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, ColorAlpha(NEGRO, a))
	end
end

hook.Add("HUDPaint", "TrincheraEventos", function()
	DibujarDuelo(RealTime())
	DibujarVotacion(CurTime())
	DibujarAnuncio(RealTime())
end)

---------------------------------------------------------------------------
-- Cámara lenta: colores apagados y estela de movimiento mientras dura.
---------------------------------------------------------------------------

local COLOR_LENTA = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0.02,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1.1, ["$pp_colour_colour"] = 0.5,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

hook.Add("RenderScreenspaceEffects", "TrincheraLenta", function()
	if not GetGlobalBool("TrincheraLenta") then return end
	DrawColorModify(COLOR_LENTA)
	DrawMotionBlur(0.25, 0.7, 0.01)
end)
