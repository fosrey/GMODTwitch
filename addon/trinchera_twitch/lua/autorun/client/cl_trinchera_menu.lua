-- La Trinchera: menú de configuración (trinchera_menu, o Utilidades > La Trinchera en el menú Q)

if not TRINCHERA then include("autorun/sh_trinchera_estilos.lua") end

local RELACIONES = { { "defecto", "Por defecto" }, { "aliado", "Aliado" }, { "enemigo", "Enemigo" } }
local RANGOS = { { "viewer", "Todos" }, { "sub", "Subs o más" }, { "vip", "VIPs o más" }, { "mod", "Solo mods" } }
local VIDAS = { { "sub", "Vida SUB (x)" }, { "vip", "Vida VIP (x)" }, { "mod", "Vida MOD (x)" }, { "streamer", "Vida STREAMER (x)" } }
local RANGOS_VISTA = { "viewer", "sub", "vip", "mod", "streamer" }
local RANGOS_SPAWN = { { "viewer", "Viewer" }, { "sub", "Sub" }, { "vip", "VIP" }, { "mod", "Mod" }, { "streamer", "Streamer" } }

local FONDO = Color(30, 30, 34)
local PANEL = Color(42, 42, 48)
local FILA = Color(52, 52, 58)
local FILA_ACTIVA = Color(48, 72, 52)
local MORADO = Color(145, 70, 255)

local ventana

local function Traducir(texto)
	if isstring(texto) and string.sub(texto, 1, 1) == "#" then return language.GetPhrase(string.sub(texto, 2)) end
	return texto or ""
end

-- En un DScrollPanel los hijos van dentro de su canvas.
local function Dentro(padre)
	return padre.GetCanvas and padre:GetCanvas() or padre
end

local function Etiqueta(padre, texto, fuente)
	local l = vgui.Create("DLabel", Dentro(padre))
	l:SetText(texto)
	l:SetFont(fuente or "DermaDefault")
	l:SetTextColor(color_white)
	l:SizeToContents()
	return l
end

local function Combo(padre, opciones, valor, ancho, alElegir)
	local c = vgui.Create("DComboBox", Dentro(padre))
	c:SetWide(ancho)
	c:SetSortItems(false)
	for _, o in ipairs(opciones) do c:AddChoice(o[2], o[1], o[1] == valor) end
	c.OnSelect = function(_, _, _, dato) alElegir(dato) end
	return c
end

local function AbrirMenu(config)
	if IsValid(ventana) then ventana:Remove() end

	ventana = vgui.Create("DFrame")
	ventana:SetSize(math.min(ScrW() - 40, 1050), math.min(ScrH() - 40, 700))
	ventana:Center()
	ventana:SetTitle("La Trinchera — NPCs de Twitch")
	ventana:MakePopup()
	ventana.Paint = function(_, w, h)
		draw.RoundedBox(6, 0, 0, w, h, FONDO)
		draw.RoundedBoxEx(6, 0, 0, w, 24, MORADO, true, true, false, false)
	end

	---------------------------------------------------------------------
	-- Columna izquierda: ajustes generales
	---------------------------------------------------------------------
	local izq = vgui.Create("DScrollPanel", ventana)
	izq:Dock(LEFT)
	izq:SetWide(300)
	izq:DockMargin(0, 0, 8, 0)
	izq.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, PANEL) end

	local function Titulo(texto)
		local l = Etiqueta(izq, texto, "DermaDefaultBold")
		l:Dock(TOP)
		l:DockMargin(10, 12, 10, 4)
	end

	local function Casilla(texto, valor, alCambiar)
		local c = izq:Add("DCheckBoxLabel")
		c:SetText(texto)
		c:SetTextColor(color_white)
		c:SetValue(valor)
		c:Dock(TOP)
		c:DockMargin(10, 4, 10, 4)
		c.OnChange = function(_, v) alCambiar(v) end
	end

	local function Deslizador(texto, min, max, decimales, valor, alCambiar)
		local s = izq:Add("DNumSlider")
		s:SetText(texto)
		s:SetMinMax(min, max)
		s:SetDecimals(decimales)
		s:SetValue(valor)
		s:Dock(TOP)
		s:DockMargin(10, 0, 10, 0)
		s:SetTall(28)
		s.Label:SetTextColor(color_white)
		s.OnValueChanged = function(_, v) alCambiar(v) end
	end

	Titulo("GENERAL")
	Casilla("Aceptar spawns desde Twitch", config.activo, function(v) config.activo = v end)
	Casilla("Globos con lo que escriben en el chat", config.globos, function(v) config.globos = v end)
	Casilla("Un NPC por viewer (el nuevo reemplaza al anterior)", config.unoPorViewer, function(v) config.unoPorViewer = v end)
	Casilla("Los cuerpos conservan el nombre", config.cadaveres, function(v) config.cadaveres = v end)
	Deslizador("Máximo de NPCs", 1, 100, 0, config.max, function(v) config.max = math.floor(v) end)

	Titulo("ESTILO DE LOS NOMBRES")

	local opcionesEstilo = {}
	for _, id in ipairs(TRINCHERA.ORDEN_ESTILOS) do
		table.insert(opcionesEstilo, { id, TRINCHERA.ESTILOS[id].nombre })
	end

	local comboEstilo = Combo(izq, opcionesEstilo, config.estilo, 200, function(id) config.estilo = id end)
	comboEstilo:Dock(TOP)
	comboEstilo:DockMargin(10, 0, 10, 6)

	Casilla("Usar el color de Twitch del viewer", config.colorTwitch, function(v) config.colorTwitch = v end)

	-- Vista previa de cómo se verá "Luis" en cada rango con el estilo elegido (se redibuja sola).
	local vista = izq:Add("DPanel")
	vista:Dock(TOP)
	vista:DockMargin(10, 6, 10, 6)
	vista:SetTall(#RANGOS_VISTA * 26 + 12)
	vista.Paint = function(_, w, h)
		draw.RoundedBox(4, 0, 0, w, h, FONDO)
		local estilo = TRINCHERA.ESTILOS[config.estilo]
		for i, rango in ipairs(RANGOS_VISTA) do
			local yy = 6 + (i - 1) * 26
			local insignia = TRINCHERA.INSIGNIAS[rango]
			local etiqueta = insignia and insignia.texto or "VIEWER"
			draw.SimpleText(etiqueta, "DermaDefaultBold", 8, yy + 4, insignia and insignia.color or Color(160, 160, 160))
			draw.SimpleText("Luis", "DermaDefault", 78, yy + 4, estilo.color)
		end
	end

	Titulo("LIBRE ALBEDRÍO")
	local albedrio = config.albedrio
	Casilla("Pasean solos cuando están tranquilos", albedrio.activo, function(v) albedrio.activo = v end)
	Casilla("Corren en vez de caminar", albedrio.correr, function(v) albedrio.correr = v end)
	Deslizador("Distancia del paseo", 100, 4000, 0, albedrio.radio, function(v) albedrio.radio = math.floor(v) end)
	Deslizador("Pausa mínima (s)", 2, 120, 0, albedrio.min, function(v) albedrio.min = math.floor(v) end)
	Deslizador("Pausa máxima (s)", 2, 300, 0, albedrio.max, function(v) albedrio.max = math.floor(v) end)
	Deslizador("Animación en vez de paseo (%)", 0, 100, 0, albedrio.animaciones, function(v) albedrio.animaciones = math.floor(v) end)
	Deslizador("Resbalón al caminar (%)", 0, 100, 0, albedrio.resbalon, function(v) albedrio.resbalon = math.floor(v) end)

	Titulo("FRASES AMBIENTALES")
	local frases = config.frases
	Casilla("Dicen frases si su viewer está callado", frases.activo, function(v) frases.activo = v end)
	Deslizador("Una frase cada (s)", 3, 300, 0, frases.cada, function(v) frases.cada = math.floor(v) end)
	Deslizador("Viewer callado por (s)", 0, 600, 0, frases.silencio, function(v) frases.silencio = math.floor(v) end)

	local probarFrase = izq:Add("DButton")
	probarFrase:SetText("Probar una frase ahora")
	probarFrase:Dock(TOP)
	probarFrase:DockMargin(10, 4, 10, 0)
	probarFrase.DoClick = function() RunConsoleCommand("trinchera_frase") end

	local ayudaFrases = Etiqueta(izq, "Edítalas en garrysmod/data/trinchera_frases.txt\n(o con editar_frases.bat). Se recargan solas.")
	ayudaFrases:SetTextColor(Color(170, 170, 170))
	ayudaFrases:SetWrap(true)
	ayudaFrases:SetAutoStretchVertical(true)
	ayudaFrases:Dock(TOP)
	ayudaFrases:DockMargin(10, 6, 10, 0)

	Titulo("VENTAJAS POR RANGO")
	for _, v in ipairs(VIDAS) do
		local rango = v[1]
		Deslizador(v[2], 0.5, 5, 2, config.vida[rango] or 1, function(x) config.vida[rango] = x end)
	end

	local nota = Etiqueta(izq, "El cooldown por rango se cambia en bridge/config.json.\nLos mods tienen uno corto y el streamer ninguno.")
	nota:SetTextColor(Color(170, 170, 170))
	nota:SetWrap(true)
	nota:SetAutoStretchVertical(true)
	nota:Dock(TOP)
	nota:DockMargin(10, 10, 10, 10)

	---------------------------------------------------------------------
	-- Abajo: guardar
	---------------------------------------------------------------------
	local abajo = vgui.Create("DPanel", ventana)
	abajo:Dock(BOTTOM)
	abajo:SetTall(36)
	abajo:DockMargin(0, 8, 0, 0)
	abajo.Paint = nil

	local estado = {}

	local guardar = vgui.Create("DButton", abajo)
	guardar:Dock(RIGHT)
	guardar:SetWide(160)
	guardar:SetText("Guardar")
	guardar:SetFont("DermaDefaultBold")
	guardar.DoClick = function()
		local salida = table.Copy(config)
		salida.npcs = {}

		local usados = {}
		for clave, e in pairs(estado) do
			if e.activo then
				local alias = string.lower((string.gsub(e.alias, "[^%w_]", "")))
				if alias == "" then alias = TRINCHERA.AliasPorDefecto(clave) end

				if usados[alias] then
					notification.AddLegacy("El comando '" .. alias .. "' está repetido (" .. usados[alias] .. " y " .. clave .. ")", NOTIFY_ERROR, 6)
					surface.PlaySound("buttons/button10.wav")
					return
				end
				usados[alias] = clave
				salida.npcs[clave] = { alias = alias, relacion = e.relacion, rango = e.rango }
			end
		end

		net.Start("TrincheraGuardarConfig")
		TRINCHERA.EscribirTabla(salida)
		net.SendToServer()
		surface.PlaySound("buttons/button14.wav")
		ventana:Close()
	end

	local cancelar = vgui.Create("DButton", abajo)
	cancelar:Dock(RIGHT)
	cancelar:DockMargin(0, 0, 8, 0)
	cancelar:SetWide(100)
	cancelar:SetText("Cancelar")
	cancelar.DoClick = function() ventana:Close() end

	local contador = Etiqueta(abajo, "")
	contador:Dock(LEFT)
	contador:DockMargin(4, 0, 0, 0)
	contador.Think = function(self)
		local n = 0
		for _, e in pairs(estado) do if e.activo then n = n + 1 end end
		self:SetText(n .. " NPCs activos")
		self:SizeToContents()
	end

	---------------------------------------------------------------------
	-- Derecha: lista de NPCs
	---------------------------------------------------------------------
	local der = vgui.Create("DPanel", ventana)
	der:Dock(FILL)
	der.Paint = nil

	-- "Spawnear como": el botón "Spawnear" de cada fila hace aparecer ese NPC para este viewer.
	local como = vgui.Create("DPanel", der)
	como:Dock(TOP)
	como:SetTall(30)
	como:DockMargin(0, 0, 0, 6)
	como.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, PANEL) end

	local etiquetaComo = Etiqueta(como, "Spawnear como:", "DermaDefaultBold")
	etiquetaComo:Dock(LEFT)
	etiquetaComo:DockMargin(8, 0, 6, 0)

	local rangoComo = "viewer"
	local comboRangoComo = Combo(como, RANGOS_SPAWN, rangoComo, 100, function(v) rangoComo = v end)
	comboRangoComo:Dock(RIGHT)
	comboRangoComo:DockMargin(6, 4, 4, 4)

	-- Arma con la que aparece: por defecto ninguna.
	local opcionesArma = { { "ninguna", "Sin arma" }, { "", "La normal del NPC" } }
	local armasNPC = {}
	for _, v in pairs(list.Get("NPCUsableWeapons")) do
		table.insert(armasNPC, { v.class, Traducir(v.title or v.class) })
	end
	table.sort(armasNPC, function(a, b) return a[2] < b[2] end)
	for _, a in ipairs(armasNPC) do table.insert(opcionesArma, a) end

	local armaComo = "ninguna"
	local comboArmaComo = Combo(como, opcionesArma, armaComo, 150, function(v) armaComo = v end)
	comboArmaComo:Dock(RIGHT)
	comboArmaComo:DockMargin(6, 4, 0, 4)

	local nombreComo = vgui.Create("DTextEntry", como)
	nombreComo:Dock(FILL)
	nombreComo:DockMargin(0, 4, 0, 4)
	nombreComo:SetPlaceholderText("Usuario de Twitch del viewer (vacío = nombre de prueba)")

	local barra = vgui.Create("DPanel", der)
	barra:Dock(TOP)
	barra:SetTall(24)
	barra:DockMargin(0, 0, 0, 6)
	barra.Paint = nil

	local soloActivos = vgui.Create("DCheckBoxLabel", barra)
	soloActivos:Dock(RIGHT)
	soloActivos:DockMargin(10, 4, 4, 0)
	soloActivos:SetText("Solo activos")
	soloActivos:SetTextColor(color_white)
	soloActivos:SizeToContents()

	local buscar = vgui.Create("DTextEntry", barra)
	buscar:Dock(FILL)
	buscar:SetPlaceholderText("Buscar NPC (nombre, clase o categoría)...")

	-- Encabezado con las mismas columnas que las filas.
	local encabezado = vgui.Create("DPanel", der)
	encabezado:Dock(TOP)
	encabezado:SetTall(20)
	encabezado.Paint = nil
	local function Columna(texto, ancho)
		local l = Etiqueta(encabezado, texto, "DermaDefaultBold")
		l:Dock(RIGHT)
		l:SetWide(ancho)
		l:DockMargin(4, 0, 0, 0)
	end
	Columna("", 78)
	Columna("Quién", 110)
	Columna("Relación", 100)
	Columna("Comando: !spawn ...", 140)
	local colNombre = Etiqueta(encabezado, "Activo   NPC", "DermaDefaultBold")
	colNombre:Dock(FILL)
	colNombre:DockMargin(6, 0, 0, 0)

	local lista = vgui.Create("DScrollPanel", der)
	lista:Dock(FILL)

	-- Ordenar todos los NPCs (incluidos los de addons) por categoría y nombre.
	local categorias = {}
	for clave, datos in pairs(list.Get("NPC")) do
		if TRINCHERA.NPCValido(datos) then
			local cat = Traducir(datos.Category or "Otros")
			categorias[cat] = categorias[cat] or {}
			table.insert(categorias[cat], { clave = clave, nombre = Traducir(datos.Name or ("#" .. datos.Class)), cat = cat })
		end
	end

	local secciones = {}

	for cat, npcs in SortedPairs(categorias) do
		table.sort(npcs, function(a, b) return a.nombre < b.nombre end)

		local titulo = lista:Add("DLabel")
		titulo:SetText(cat)
		titulo:SetFont("DermaDefaultBold")
		titulo:SetTextColor(MORADO)
		titulo:Dock(TOP)
		titulo:DockMargin(2, 10, 0, 4)

		local seccion = { titulo = titulo, filas = {} }
		table.insert(secciones, seccion)

		for _, n in ipairs(npcs) do
			local actual = config.npcs[n.clave]
			local e = {
				activo = actual ~= nil,
				alias = actual and actual.alias or TRINCHERA.AliasPorDefecto(n.clave),
				relacion = actual and actual.relacion or "defecto",
				rango = actual and actual.rango or "viewer",
			}
			estado[n.clave] = e

			local fila = lista:Add("DPanel")
			fila:Dock(TOP)
			fila:SetTall(26)
			fila:DockMargin(0, 0, 0, 2)
			fila.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, e.activo and FILA_ACTIVA or FILA) end
			fila.busqueda = string.lower(n.nombre .. " " .. n.clave .. " " .. n.cat)
			fila.estado = e
			table.insert(seccion.filas, fila)

			local probar = vgui.Create("DButton", fila)
			probar:Dock(RIGHT)
			probar:DockMargin(4, 2, 2, 2)
			probar:SetWide(72)
			probar:SetText("Spawnear")
			probar.DoClick = function()
				net.Start("TrincheraProbar")
				net.WriteString(n.clave)
				net.WriteString(rangoComo)
				net.WriteString(nombreComo:GetValue())
				net.WriteString(armaComo)
				net.SendToServer()
			end

			local rango = Combo(fila, RANGOS, e.rango, 110, function(v) e.rango = v end)
			rango:Dock(RIGHT)
			rango:DockMargin(4, 2, 0, 2)

			local relacion = Combo(fila, RELACIONES, e.relacion, 100, function(v) e.relacion = v end)
			relacion:Dock(RIGHT)
			relacion:DockMargin(4, 2, 0, 2)

			local alias = vgui.Create("DTextEntry", fila)
			alias:Dock(RIGHT)
			alias:DockMargin(4, 2, 0, 2)
			alias:SetWide(140)
			alias:SetValue(e.alias)
			alias:SetUpdateOnType(true)
			alias.OnValueChange = function(_, v) e.alias = v end

			local activo = vgui.Create("DCheckBox", fila)
			activo:Dock(LEFT)
			activo:DockMargin(8, 5, 8, 5)
			activo:SetWide(16)
			activo:SetChecked(e.activo)
			activo.OnChange = function(_, v) e.activo = v end

			local nombre = Etiqueta(fila, n.nombre .. "   (" .. n.clave .. ")")
			nombre:Dock(FILL)
		end
	end

	local function Filtrar()
		local texto = string.lower(buscar:GetValue())
		local solo = soloActivos:GetChecked()

		for _, s in ipairs(secciones) do
			local alguna = false
			for _, fila in ipairs(s.filas) do
				local ver = (texto == "" or string.find(fila.busqueda, texto, 1, true) ~= nil) and (not solo or fila.estado.activo)
				fila:SetVisible(ver)
				alguna = alguna or ver
			end
			s.titulo:SetVisible(alguna)
		end
		lista:GetCanvas():InvalidateLayout()
	end

	buscar:SetUpdateOnType(true)
	buscar.OnValueChange = Filtrar
	soloActivos.OnChange = Filtrar
end

net.Receive("TrincheraConfig", function()
	local config = TRINCHERA.LeerTabla()
	if istable(config) then AbrirMenu(config) end
end)

concommand.Add("trinchera_menu", function()
	net.Start("TrincheraPedirConfig")
	net.SendToServer()
end)

hook.Add("PopulateToolMenu", "TrincheraMenu", function()
	spawnmenu.AddToolMenuOption("Utilities", "La Trinchera", "TrincheraTwitch", "NPCs de Twitch", "", "", function(panel)
		panel:ClearControls()
		panel:Help("Elige qué NPCs pueden aparecer desde el chat, el estilo de los nombres y las ventajas por rango.")
		panel:Button("Abrir menú de La Trinchera", "trinchera_menu")
		panel:Button("Eliminar NPCs de viewers", "trinchera_limpiar")
		panel:Help("Atajo: escribe en la consola  bind F6 trinchera_menu")
	end)
end)
