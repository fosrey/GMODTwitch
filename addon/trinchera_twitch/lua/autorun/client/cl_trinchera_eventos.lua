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

hook.Add("HUDPaint", "TrincheraEventos", function()
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
