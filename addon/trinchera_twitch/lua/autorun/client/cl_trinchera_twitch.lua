-- La Trinchera: NPCs de viewers de Twitch (cliente)
-- Dibuja el nombre del viewer (con su estilo e insignia de rango), sus globos de texto
-- y muestra los avisos en el chat.

if not TRINCHERA then include("autorun/sh_trinchera_estilos.lua") end

for id, estilo in pairs(TRINCHERA.ESTILOS) do
	surface.CreateFont("TrincheraNombre_" .. id, { font = estilo.fuente, size = 64, weight = 700, antialias = true, extended = true })
	surface.CreateFont("TrincheraGlobo_" .. id, { font = estilo.globo.fuente, size = 40, weight = 600, antialias = true, extended = true })
end
surface.CreateFont("TrincheraInsignia", { font = "Roboto", size = 30, weight = 900, antialias = true })

local MORADO_TWITCH = Color(145, 70, 255)
local DISTANCIA_MAX = 2000
local DISTANCIA_FADE = 1200

local cacheColores = {}

local function ColorDesdeHex(hex)
	if cacheColores[hex] then return cacheColores[hex] end

	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	local col = r and Color(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
	cacheColores[hex] = col or false
	return col
end

local function Traducir(texto)
	if string.sub(texto, 1, 1) == "#" then return language.GetPhrase(string.sub(texto, 2)) end
	return texto
end

net.Receive("TrincheraAviso", function()
	local segmentos = TRINCHERA.LeerTabla()
	if not istable(segmentos) then return end

	local partes = { MORADO_TWITCH, "[Twitch] " }
	for _, s in ipairs(segmentos) do
		if istable(s) then
			table.insert(partes, Color(s.r or 255, s.g or 255, s.b or 255))
		else
			table.insert(partes, Traducir(tostring(s)))
		end
	end
	chat.AddText(unpack(partes))
end)

---------------------------------------------------------------------------
-- Globos de texto
---------------------------------------------------------------------------

local GLOBO_ANCHO_MAX = 700
local GLOBO_MAX_LINEAS = 4
local GLOBO_PADDING = 18
local COLOR_ACCION = Color(255, 220, 60)

surface.CreateFont("TrincheraAccion", { font = "Roboto", size = 44, weight = 800, italic = true, antialias = true, extended = true })

local globos = {} -- entidad -> { texto, emotes, inicio, fin, lineas }

---------------------------------------------------------------------------
-- Emotes de Twitch: se descargan del CDN de Twitch y la imagen queda solo en memoria.
-- GMod solo crea imágenes desde un archivo y lo sigue leyendo mientras la muestra,
-- así que se escribe uno temporal que vive mientras dure el globo (+1 s) y luego se borra.
---------------------------------------------------------------------------

local CARPETA_EMOTES = "trinchera_emotes"
local URL_EMOTE = "https://static-cdn.jtvnw.net/emoticons/v2/%s/static/dark/2.0"
local MARGEN_EMOTE = 1 -- segundos que el archivo sobrevive al globo

-- Por si quedó algo de una sesión que se cerró de golpe.
file.CreateDir(CARPETA_EMOTES)
for _, f in ipairs(file.Find(CARPETA_EMOTES .. "/*", "DATA") or {}) do
	file.Delete(CARPETA_EMOTES .. "/" .. f)
end

-- id -> { png (bytes en memoria), mat, ruta (archivo temporal), hasta (cuándo se borra), fallo }
local emotes = {}
local escritos = 0

-- Cuando un emote termina de cargar (o falla), los globos se vuelven a acomodar.
local function ReacomodarGlobos()
	for _, g in pairs(globos) do g.lineas = nil end
end

local function Soltar(e)
	if e.ruta then file.Delete(e.ruta) end
	e.ruta, e.mat = nil, nil
end

-- Escribe el archivo temporal (con nombre nuevo cada vez, para que GMod no reuse un material viejo) y crea el material.
local function Preparar(id, e)
	if e.mat then return end

	escritos = escritos + 1
	e.ruta = CARPETA_EMOTES .. "/" .. id .. "_" .. escritos .. ".png"
	file.Write(e.ruta, e.png)

	local mat = Material("../data/" .. e.ruta, "smooth mips")
	if mat:IsError() then
		Soltar(e)
		e.fallo = true
	else
		e.mat = mat
	end
	ReacomodarGlobos()
end

-- hasta: hasta cuándo se necesita la imagen (fin del globo + margen).
local function PedirEmote(id, hasta)
	local e = emotes[id]
	if e then
		e.hasta = math.max(e.hasta, hasta)
		if e.png and not e.fallo then Preparar(id, e) end
		return
	end

	e = { hasta = hasta }
	emotes[id] = e
	http.Fetch(string.format(URL_EMOTE, id), function(cuerpo, _, _, codigo)
		if codigo == 200 and string.sub(cuerpo, 1, 8) == "\137PNG\r\n\26\n" then
			e.png = cuerpo
			Preparar(id, e)
		else
			e.fallo = true
			ReacomodarGlobos()
		end
	end, function()
		e.fallo = true
		ReacomodarGlobos()
	end)
end

-- Borra los archivos de los emotes que ya ningún globo muestra (la imagen sigue en memoria).
timer.Create("TrincheraEmotes", 1, 0, function()
	local ahora = CurTime()
	for _, e in pairs(emotes) do
		if e.ruta and ahora > e.hasta then Soltar(e) end
	end
end)

hook.Add("ShutDown", "TrincheraEmotes", function()
	for _, e in pairs(emotes) do Soltar(e) end
end)

-- El material del emote si ya está listo; "cargando" mientras se descarga (se deja su hueco).
local function EmoteDe(g, palabra)
	local id = g.emotes and g.emotes[palabra]
	local e = id and emotes[id]
	if not e or e.fallo then return end
	return e.mat or "cargando"
end

net.Receive("TrincheraGlobo", function()
	local ent = net.ReadEntity()
	local texto = net.ReadString()

	local ids
	for _ = 1, net.ReadUInt(8) do
		local palabra, id = net.ReadString(), net.ReadString()
		if string.match(id, "^[%w_%-]+$") then
			ids = ids or {}
			ids[palabra] = id
		end
	end

	for e in pairs(globos) do
		if not IsValid(e) then globos[e] = nil end
	end

	if not IsValid(ent) then return end
	if texto == "" then
		globos[ent] = nil
		return
	end

	-- *texto entre asteriscos* = acción o pensamiento: texto amarillo flotante en vez de globo.
	local accion = #texto > 2 and string.match(texto, "^%*.+%*$") ~= nil

	-- Más tiempo en pantalla para mensajes más largos.
	local largo = utf8.len(texto) or #texto
	local fin = CurTime() + math.Clamp(3 + largo * 0.07, 4, 11)
	globos[ent] = { texto = texto, emotes = ids, accion = accion, inicio = CurTime(), fin = fin }

	for _, id in pairs(ids or {}) do PedirEmote(id, fin + MARGEN_EMOTE) end
end)

-- Parte el texto en líneas que no pasen de GLOBO_ANCHO_MAX.
-- Cada línea es { ancho, piezas }, y cada pieza es { texto, ancho } o { emote = material, ancho }.
-- Los emotes son cuadrados del alto de una línea.
local function Envolver(g, fuente)
	surface.SetFont(fuente)
	local espacio = surface.GetTextSize(" ")
	local _, altoLinea = surface.GetTextSize("Ay")

	local lineas = {}
	local actual = { ancho = 0, piezas = {} }

	local function Agregar(pieza)
		local extra = #actual.piezas > 0 and espacio or 0
		if actual.ancho + extra + pieza.ancho > GLOBO_ANCHO_MAX and #actual.piezas > 0 then
			table.insert(lineas, actual)
			actual = { ancho = 0, piezas = {} }
			extra = 0
		end
		actual.ancho = actual.ancho + extra + pieza.ancho
		table.insert(actual.piezas, pieza)
	end

	for palabra in string.gmatch(g.texto, "%S+") do
		local emote = EmoteDe(g, palabra)
		if emote then
			Agregar({ emote = emote, ancho = altoLinea })
		else
			Agregar({ texto = palabra, ancho = (surface.GetTextSize(palabra)) })
		end
	end
	if #actual.piezas > 0 then table.insert(lineas, actual) end

	if #lineas > GLOBO_MAX_LINEAS then
		lineas = { unpack(lineas, 1, GLOBO_MAX_LINEAS) }
		local ultima = lineas[GLOBO_MAX_LINEAS]
		local puntos = surface.GetTextSize("…")
		table.insert(ultima.piezas, { texto = "…", ancho = puntos, pegado = true })
		ultima.ancho = ultima.ancho + puntos
	end
	return lineas, altoLinea, espacio
end

-- Dibuja una línea centrada en x. "texto" es una función que dibuja una palabra (con o sin borde).
local function DibujarLinea(linea, x, y, espacio, alto, a, texto)
	local cx = x - linea.ancho / 2
	for i, p in ipairs(linea.piezas) do
		if i > 1 and not p.pegado then cx = cx + espacio end
		if p.emote == "cargando" then
			-- Se deja el hueco hasta que termine de descargarse.
		elseif p.emote then
			surface.SetMaterial(p.emote)
			surface.SetDrawColor(255, 255, 255, a)
			surface.DrawTexturedRect(cx, y, alto, alto)
		else
			texto(p.texto, cx, y)
		end
		cx = cx + p.ancho
	end
end

-- "base" es el borde inferior disponible (encima del nombre/insignia), en coordenadas del 3D2D.
local function DibujarGlobo(npc, estiloId, estilo, x, base, alpha)
	local g = globos[npc]
	if not g then return end

	local ahora = CurTime()
	if ahora > g.fin then
		globos[npc] = nil
		return
	end

	local fuente = g.accion and "TrincheraAccion" or ("TrincheraGlobo_" .. estiloId)
	if not g.lineas then g.lineas, g.altoLinea, g.espacio = Envolver(g, fuente) end
	local altoLinea, espacio = g.altoLinea, g.espacio

	-- Aparece subiendo un poco y se desvanece al final.
	local entrada = math.Clamp((ahora - g.inicio) / 0.2, 0, 1)
	local salida = math.Clamp((g.fin - ahora) / 0.5, 0, 1)
	local a = alpha * math.min(entrada, salida)

	-- Acción: texto amarillo con borde negro que sube despacio y se mece, sin globo.
	if g.accion then
		local vida = ahora - g.inicio
		local ax = x + math.sin(vida * 1.5) * 6
		local abajo = base - 16 - vida * 6 + (1 - entrada) * 20
		local arriba = abajo - #g.lineas * altoLinea
		local col, borde = ColorAlpha(COLOR_ACCION, a), Color(0, 0, 0, a)

		for i, l in ipairs(g.lineas) do
			DibujarLinea(l, ax, arriba + (i - 1) * altoLinea, espacio, altoLinea, a, function(t, tx, ty)
				draw.SimpleTextOutlined(t, fuente, tx, ty, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 3, borde)
			end)
		end
		return
	end

	local ancho = 0
	for _, l in ipairs(g.lineas) do ancho = math.max(ancho, l.ancho) end

	local estiloGlobo = estilo.globo
	local w = ancho + GLOBO_PADDING * 2
	local h = #g.lineas * altoLinea + GLOBO_PADDING * 1.2
	local cola = base - 24 + (1 - entrada) * 20
	local bx, by = x - w / 2, cola - h

	-- Borde, cuerpo y la colita que apunta al NPC.
	draw.RoundedBox(18, bx - 3, by - 3, w + 6, h + 6, ColorAlpha(estiloGlobo.borde, a))
	draw.RoundedBox(16, bx, by, w, h, ColorAlpha(estiloGlobo.fondo, a))

	draw.NoTexture()
	surface.SetDrawColor(ColorAlpha(estiloGlobo.borde, a))
	surface.DrawPoly({ { x = x - 17, y = cola + 2 }, { x = x + 17, y = cola + 2 }, { x = x, y = cola + 21 } })
	surface.SetDrawColor(ColorAlpha(estiloGlobo.fondo, a))
	surface.DrawPoly({ { x = x - 13, y = cola - 1 }, { x = x + 13, y = cola - 1 }, { x = x, y = cola + 16 } })

	local colTexto = ColorAlpha(estiloGlobo.texto, a)
	for i, l in ipairs(g.lineas) do
		DibujarLinea(l, x, by + GLOBO_PADDING * 0.6 + (i - 1) * altoLinea, espacio, altoLinea, a, function(t, tx, ty)
			draw.SimpleText(t, fuente, tx, ty, colTexto, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end)
	end
end

---------------------------------------------------------------------------
-- Nombre + insignia + globo sobre la cabeza del NPC
---------------------------------------------------------------------------

local function DibujarNombre(npc, ojo, ang)
	local nombre = npc:GetNWString("TrincheraNombre", "")
	if nombre == "" then return end

	-- Si se resbaló, el NPC está en el suelo siguiendo a su muñeco: el nombre va más bajo.
	local altura = npc:GetNWBool("TrincheraCaido") and 30 or (npc:OBBMaxs().z + 14)
	local pos = npc:GetPos() + Vector(0, 0, altura)
	local dist = ojo:Distance(pos)
	if dist > DISTANCIA_MAX then return end

	local estiloId = npc:GetNWString("TrincheraEstilo", "ninguno")
	local estilo = TRINCHERA.ESTILOS[estiloId]
	if not estilo then estiloId, estilo = "ninguno", TRINCHERA.ESTILOS.ninguno end

	local alpha = math.Clamp(255 - (dist - DISTANCIA_FADE) / (DISTANCIA_MAX - DISTANCIA_FADE) * 255, 0, 255)
	local col = ColorDesdeHex(npc:GetNWString("TrincheraColor", "")) or estilo.color

	-- Lovecraft: el nombre flota y parpadea un poco, como si no fuera de este mundo.
	local x, y = 0, 0
	if estilo.temblor then
		local t = CurTime() * 2 + npc:EntIndex()
		x = math.sin(t * 1.7) * 3
		y = math.cos(t * 1.3) * 2
		alpha = alpha * (0.75 + 0.25 * math.sin(t * 2.3))
	end

	local fuente = "TrincheraNombre_" .. estiloId
	surface.SetFont(fuente)
	local _, alto = surface.GetTextSize(nombre)

	cam.Start3D2D(pos, ang, 0.08)
		draw.SimpleTextOutlined(nombre, fuente, x, y, ColorAlpha(col, alpha),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 3, Color(0, 0, 0, alpha))

		local tope = y - alto

		local insignia = TRINCHERA.INSIGNIAS[npc:GetNWString("TrincheraRango", "")]
		if insignia then
			surface.SetFont("TrincheraInsignia")
			local w, h = surface.GetTextSize(insignia.texto)
			w, h = w + 24, h + 6
			local arriba = tope - h - 6

			draw.RoundedBox(8, -w / 2, arriba, w, h, ColorAlpha(insignia.color, alpha))
			draw.SimpleText(insignia.texto, "TrincheraInsignia", 0, arriba + h / 2, Color(255, 255, 255, alpha),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			tope = arriba
		end

		DibujarGlobo(npc, estiloId, estilo, x, tope, alpha)
	cam.End3D2D()
end

---------------------------------------------------------------------------
-- Cadáveres con nombre: "† Soldado Luis" en gris sobre el cuerpo.
-- Los cuerpos del cliente se registran aquí; los del servidor traen el nombre por red.
-- Cuando el viewer vuelve a hacer !spawn, el servidor avisa y se borra el nombre.
---------------------------------------------------------------------------

local GRIS_CADAVER = Color(175, 175, 175)
local DISTANCIA_CADAVER = 1200

surface.CreateFont("TrincheraCruz", { font = "Roboto", size = 64, weight = 700, antialias = true, extended = true })

local cadaveres = {} -- ragdoll del cliente -> { nombre, estilo, usuario }

hook.Add("CreateClientsideRagdoll", "TrincheraCadaver", function(npc, rag)
	local nombre = npc:GetNWString("TrincheraNombre", "")
	if nombre == "" or not npc:GetNWBool("TrincheraCadaver") then return end

	cadaveres[rag] = {
		nombre = nombre,
		estilo = npc:GetNWString("TrincheraEstilo", "ninguno"),
		usuario = npc:GetNWString("TrincheraUsuario", ""),
	}
end)

net.Receive("TrincheraOlvidarCadaver", function()
	local usuario = net.ReadString()
	for rag, c in pairs(cadaveres) do
		if not IsValid(rag) or c.usuario == usuario then cadaveres[rag] = nil end
	end
end)

local function DibujarCadaver(rag, nombre, estiloId, ojo, ang)
	local pos = rag:WorldSpaceCenter() + Vector(0, 0, 28)
	local dist = ojo:Distance(pos)
	if dist > DISTANCIA_CADAVER then return end

	local alpha = math.Clamp(200 - (dist - DISTANCIA_CADAVER * 0.6) / (DISTANCIA_CADAVER * 0.4) * 200, 0, 200)
	local fuente = TRINCHERA.ESTILOS[estiloId] and ("TrincheraNombre_" .. estiloId) or "TrincheraNombre_ninguno"

	-- La cruz va en Roboto porque algunas fuentes de estilo (Stencil, gótica) no la tienen.
	surface.SetFont("TrincheraCruz")
	local anchoCruz = surface.GetTextSize("† ")
	surface.SetFont(fuente)
	local anchoNombre = surface.GetTextSize(nombre)
	local inicio = -(anchoCruz + anchoNombre) / 2

	local col, borde = ColorAlpha(GRIS_CADAVER, alpha), Color(0, 0, 0, alpha)
	cam.Start3D2D(pos, ang, 0.06)
		draw.SimpleTextOutlined("† ", "TrincheraCruz", inicio, 0, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 3, borde)
		draw.SimpleTextOutlined(nombre, fuente, inicio + anchoCruz, 0, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 3, borde)
	cam.End3D2D()
end

---------------------------------------------------------------------------

hook.Add("PostDrawTranslucentRenderables", "TrincheraNombres", function(depth, skybox)
	if depth or skybox then return end

	local ojo = EyePos()
	local ang = Angle(0, EyeAngles().y - 90, 90)

	-- No solo "npc_*": los NPCs de addons y de Half-Life 1 tienen otras clases.
	for _, ent in ents.Iterator() do
		if ent:IsNPC() or ent:IsNextBot() then
			DibujarNombre(ent, ojo, ang)
		elseif ent:GetClass() == "prop_ragdoll" then
			local nombre = ent:GetNWString("TrincheraNombre", "")
			if nombre ~= "" then DibujarCadaver(ent, nombre, ent:GetNWString("TrincheraEstilo", "ninguno"), ojo, ang) end
		end
	end

	for rag, c in pairs(cadaveres) do
		if IsValid(rag) then
			DibujarCadaver(rag, c.nombre, c.estilo, ojo, ang)
		else
			cadaveres[rag] = nil
		end
	end
end)
