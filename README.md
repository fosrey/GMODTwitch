# La Trinchera — NPCs de Twitch para Garry's Mod

Los viewers escriben `!spawn` en el chat de **latrinchera_** y aparece un NPC con su nombre en tu partida.

```
Chat de Twitch ──> bridge (Node.js) ──> garrysmod/data/trinchera_twitch/*.txt ──> addon de GMod ──> NPC
```

## Instalación (una sola vez, en cualquier PC)

1. Instala **Node.js** (versión LTS) desde https://nodejs.org. Es lo único que hace falta aparte de GMod.
2. Descomprime esta carpeta donde quieras, por ejemplo en el Escritorio.
3. Doble clic en **`instalar.bat`**. El instalador:
   - busca solo dónde está Garry's Mod, en cualquier biblioteca de Steam;
   - copia el addon a `garrysmod/addons` (si ya había una versión, la reemplaza);
   - restaura tu configuración y tus frases desde la carpeta `respaldo`, **solo si** en ese GMod no existen todavía.
4. El canal ya está configurado en `bridge/config.json`.

**Sin Node.js:** el addon funciona igual si copias a mano `addon/trinchera_twitch` a `garrysmod/addons`. Sin el puente no hay conexión con Twitch, pero sirven el menú y los comandos de consola.

`"carpetaData": "auto"` en `bridge/config.json` hace que el puente encuentre GMod solo. Si alguna vez no lo encuentra, ahí puedes poner la ruta a mano.

### Respaldar tu configuración

La configuración del menú (`trinchera_config.json`) y las frases (`trinchera_frases.txt`) se guardan dentro de GMod, en `garrysmod/data`.
Antes de formatear o cambiar de PC, cópialas a la carpeta `respaldo` de este proyecto para llevártelas.

## Cada stream

1. Doble clic en `bridge/iniciar.bat`. Debe decir `Conectado al chat de #latrinchera_`.
2. Abre Garry's Mod y carga un mapa.
3. Listo: `!spawn` en el chat.

## Comandos del chat

| Comando | Quién | Qué hace |
|---|---|---|
| `!spawn` | Todos | NPC aleatorio |
| `!spawn <tipo>` | Todos | NPC de ese tipo |
| `!dar @viewer <tipo>` | Streamer y mods | Le da a ese viewer el NPC elegido, sin cooldown ni restricción de rango, aunque los spawns estén pausados |

| `!duelo @viewer` | Quien tenga NPC | Reta al NPC de otro viewer (cooldown 20 s, `cooldownDueloSegundos`) |
| `!aceptar` / `!rechazar` | El retado | Responde al reto (30 s para contestar) |
| `!votacion` | Streamer y mods | Abre una votación de evento |
| `1`, `2` | Todos | Vota durante una votación (también sale en globo) |

Con `!dar`, si el viewer ya escribió en el chat, se usan su nombre, su color y su rango reales.

## Duelos

- `!duelo @luis`: Luis tiene 30 s para escribir `!aceptar` (o `!rechazar`). Los dos necesitan tener su NPC en el mapa.
- Al aceptar, los dos NPCs aparecen **frente al streamer**, uno a cada lado, se curan del todo y pelean. Si no hay espacio frente a ti, pelean donde estén.
- Cada uno pelea con su NPC actual, así que un antlion guard contra un headcrab es posible.
- **Arma sorteada:** al empezar se sortea un arma (pistola, SMG, escopeta, AR2, .357, ballesta, palanca o porra) y la reciben **los dos**. Solo la usan los NPCs con manos (ciudadanos, rebeldes, combine…); zombies, antlions y demás pelean con lo suyo. Al terminar, cada uno vuelve a su arma de antes.
- **Como en un juego de pelea:** arriba aparecen las **barras de vida** de los dos con su nombre y su porcentaje, y un **reloj** al centro. La barra parpadea cuando a alguien le queda menos del 25 %. Los últimos 10 s el reloj se pone rojo y hace tic.
- **40 s por duelo** (ajustable en el menú, de 15 a 120). Si se acaba el tiempo, sale **"¡TIEMPO!"** y gana el que tenga más vida en porcentaje. Si uno cae antes, **K.O.**
- Si uno desaparece (nuevo `!spawn`, limpieza…) el duelo se cancela.
- **Diálogos:** los duelistas se provocan al empezar, hablan cada 5–8 s, se quejan de los golpes fuertes, dicen sus últimas palabras con poca vida, y el ganador celebra (el que pierde por tiempo pide la revancha). A veces se les escapa una frase ambiental en plena pelea.
  - Se editan en `garrysmod/data/trinchera_frases_duelo.txt`, por secciones: `[inicio]`, `[combate]`, `[golpe]`, `[pocavida]`, `[victoria]` y `[derrota]`. `{nombre}` es quien habla y `{rival}` su oponente. Se recarga solo al guardar; si lo borras, vuelve el original.
- Un duelo a la vez. Mientras pelean no pasean ni se les puede pedir que te sigan.
- Se activan o desactivan en el menú ("Permitir duelos").

## Votaciones

- El streamer o un mod escribe `!votacion` (o botón **"Abrir votación ahora"** en el menú, o `trinchera_votacion`).
- A la derecha de la pantalla aparece un panel con las opciones y los votos en vivo. El chat vota escribiendo `1` o `2`; se puede cambiar de voto. Dura 30 s (ajustable en el menú).
- Gana la opción con más votos (empate: al azar). Si nadie vota, no pasa nada.
- **1 · Horda zombie:** aparecen 10 zombies (ajustable) alrededor del streamer y van por él.
- **2 · Rebelión:** todos los NPCs de viewers atacan al streamer durante 30 s (ajustable) y después vuelven a su relación normal. Los que van montados en un vehículo no participan.
- **3 · Cámara lenta:** todo el juego va al 35 % de velocidad durante 15 s reales (ajustable), con los colores apagados y estela de movimiento.

## Cámara en tercera persona

Mira la partida desde detrás del NPC de un viewer, como si lo siguiera una cámara.

| Comando | Qué hace |
|---|---|
| `trinchera_ver` | Pasa al siguiente NPC de viewer |
| `trinchera_ver <usuario>` | Va directo al NPC de ese viewer, por ejemplo `trinchera_ver ana` |
| `trinchera_ver_salir` | Vuelve a tu cámara |

Atajos recomendados: `bind F7 trinchera_ver` y `bind F8 trinchera_ver_salir`.

- Mientras miras, tu personaje se queda quieto donde estaba y es **invulnerable**; al salir vuelves a mirar hacia donde mirabas.
- Arriba a la izquierda sale "VIENDO A Ana" (se ve en el stream).
- Si el NPC muere, la cámara se queda 3 s sobre su cuerpo y vuelve a ti.
- **Duelos:** al empezar un duelo, la cámara salta sola a un plano lateral con los dos duelistas y, al terminar, muestra al ganador unos segundos. Se desactiva en el menú ("Cámara automática en los duelos") o con `trinchera_camara_duelo 0`.

## Menú de configuración (dentro del juego)

Ábrelo con `trinchera_menu` en la consola, o en **menú Q → Utilidades → La Trinchera**.
Atajo recomendado: `bind F6 trinchera_menu`.

- **Lista de NPCs**: todos los NPCs de GMod, incluidos los de addons del Workshop. Por cada uno:
  - **Activo**: si puede aparecer desde el chat.
  - **Comando**: lo que escribe el viewer, por ejemplo `zombie` para `!spawn zombie`.
  - **Relación**: por defecto, aliado o enemigo tuyo.
  - **Quién**: todos, subs o más, VIPs o más, o solo mods.
  - **Spawnear**: lo hace aparecer al instante para el viewer y el rango de la barra **"Spawnear como"**, arriba de la lista. Si el nombre está vacío, sale un nombre de prueba. Funciona con cualquier NPC, aunque no esté activo para el chat.
    Escribe el **usuario de Twitch** del viewer para que sus mensajes salgan en globos sobre ese NPC.
- **Estilo de los nombres**: Ninguno, Gran Guerra (WW1) o Lovecraft, con vista previa.
- **Usar el color de Twitch**: el nombre toma el color del viewer en el chat en vez del color del estilo.
- **Vida por rango**: multiplicador de vida del NPC para SUB, VIP, MOD y STREAMER.
- **Máximo de NPCs**: al pasarse, desaparece el más viejo.
- **Un NPC por viewer**: si un viewer vuelve a usar `!spawn`, su NPC anterior desaparece. El streamer puede tener varios.
- **Los cuerpos conservan el nombre**: al morir, el cadáver queda con `† Nombre` en gris y ya no se desvanece solo. Si ese viewer vuelve a usar `!spawn`, su cadáver anterior pierde el nombre.
- **Libre albedrío** y **frases ambientales**: ver abajo.

La configuración se guarda en `garrysmod/data/trinchera_config.json`.

### Estilos

El nombre siempre es el del viewer, sin títulos. El estilo solo cambia cómo se ve:

| Estilo | Nombre | Globos |
|---|---|---|
| Ninguno | Roboto, blanco | Blanco clásico |
| Gran Guerra (WW1) | Stencil, caqui | Papel envejecido, máquina de escribir |
| Lovecraft | Gótica, verde; flota y parpadea | Fondo oscuro, letras verdes |

Los rangos SUB, VIP, MOD y STREAMER llevan una insignia de color sobre el nombre.

## Globos de texto

Cuando un viewer ya tiene su NPC en el mapa, lo que escribe en el chat aparece en un globo sobre su NPC.

- El globo usa el estilo elegido: papel y máquina de escribir en WW1, fondo oscuro y letras verdes en Lovecraft.
- Dura entre 4 y 11 segundos según lo largo del mensaje. Corta los mensajes a 150 caracteres y 4 líneas.
- **Emotes de Twitch** (`Kappa`, `LUL`, los de suscriptor del canal…) se ven como imagen dentro del globo. Se descargan de Twitch y quedan solo en memoria mientras el juego está abierto; no se guarda nada en disco. Los animados salen quietos. Los de 7TV, BTTV y FFZ todavía salen como texto.
- Los mensajes que empiezan con `!` (comandos de otros bots) no salen en globo.
- Si el viewer escribe `*algo*` o usa `/me algo` en Twitch, sale como acción: texto amarillo flotante, sin globo.
- **Moderación:** si un mod borra el mensaje, da timeout o banea al viewer, el globo desaparece al instante.
- Se activan o desactivan en el menú. Un viewer puede sacar un globo cada 2 segundos (`cooldownGloboSegundos`).

## Libre albedrío

Los NPCs que están tranquilos (sin enemigo y sin pelear) eligen cada cierto tiempo un punto cercano del mapa y caminan hacia él. Si aparece un enemigo, pelean normalmente y luego vuelven a pasear.

- En el menú se ajusta la distancia del paseo, la pausa mínima y máxima entre paseos, y si caminan o corren.
- **Funciona mejor en mapas con nodos de IA**, como `gm_construct`, `gm_flatgrass` y los mapas de HL2. En mapas sin nodos solo dan paseos cortos en línea recta.
- Si el mapa tiene navmesh, se usan sus zonas caminables. Se genera una vez por mapa con `nav_generate` en la consola, con `sv_cheats 1`; tarda un poco.
- Torretas y algunos NPCs especiales no se mueven.
- **Animaciones al azar:** a veces, en vez de pasear, el NPC hace una animación de su modelo: saludar, celebrar, señas, reacciones… El código elige solo entre las que su modelo tiene, así que también sirve con NPCs de addons. Los ciudadanos y rebeldes tienen muchas; zombies y antlions, casi ninguna. Probabilidad en el menú, 35 % de entrada.
- **Resbalones:** a veces, mientras camina, se resbala, cae como muñeco de trapo con un `*se resbala*` amarillo y se levanta a los pocos segundos. Si le disparan en el suelo, el daño cuenta. Probabilidad en el menú, 5 % por paseo de entrada.

## Que te sigan (tecla E)

- Acércate al NPC de un viewer y aprieta **E**: te sigue y aparece `*Luis te está siguiendo*`. Camina si estás cerca y corre si te alejas.
- **E otra vez:** `*Luis dejó de seguirte*` y vuelve a pasear solo.
- Mientras te sigue no pasea por su cuenta, pero si aparece un enemigo, pelea.
- **Vehículos:** los NPCs de HL2 no saben manejar ni subirse a vehículos. Cuando te subes a uno, tus seguidores **se suben al techo y van surfeando** contigo; cuando te bajas, se bajan a tu lado.

## Darles armas (Shift + E)

- Con un arma en la mano, **Shift + E** sobre el NPC de un viewer le da una copia (tú te quedas con la tuya): `*Luis recibe una escopeta*`. Reemplaza el arma que tenía.
- Solo pueden usar armas los NPCs con manos (ciudadanos, rebeldes, combine, metrocops…) y solo armas para NPCs: las de HL2 y las de addons preparadas para NPCs. Si no se puede, sale `*Luis no sabe usar eso*`.
- Con el **botiquín** en la mano, Shift + E lo **cura** (gasta la carga del botiquín). El clic izquierdo normal del botiquín también cura NPCs.
- En el menú, la barra **"Spawnear como"** tiene una lista para elegir con qué arma aparece el invitado. Por defecto viene en **"Sin arma"**; también está "La normal del NPC".

## Frases ambientales

Si un viewer lleva un rato sin escribir, su NPC dice una frase al azar de una lista grande, la misma para todos los NPCs (trae 126).

- **Se editan en un archivo**, aunque el juego esté cerrado: doble clic en `editar_frases.bat`
  (abre `D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\trinchera_frases.txt`).
- Una frase por línea. Las líneas con `#` son comentarios. `{nombre}` se reemplaza por el nombre del viewer.
- **Acciones:** si la frase empieza y termina con `*`, por ejemplo `*se rasca la cabeza*`, sale como **texto amarillo flotante con borde negro** en vez de globo, como un pensamiento o una acción.
- Si lo editas con el juego abierto, **se recarga solo** a los pocos segundos.
- En el menú se ajusta cada cuánto habla alguien y cuánto tiempo debe estar callado el viewer. También hay un botón para probar una frase.
- Si borras el archivo, el juego vuelve a crear el original.

## Cooldowns (en `bridge/config.json`)

| Rango | Por defecto |
|---|---|
| Viewer | 60 s (`cooldownPorViewerSegundos`) |
| Sub | 45 s (`cooldownSubSegundos`) |
| VIP | 30 s (`cooldownVipSegundos`) |
| Mod | 8 s (`cooldownModSegundos`) |
| Streamer | sin cooldown |

Además, hay 3 s entre cualquier spawn (`cooldownGlobalSegundos`).

## Comandos de consola en GMod

| Comando | Qué hace |
|---|---|
| `trinchera_menu` | Abre el menú |
| `trinchera_test [nombre] [comando] [rango]` | NPC de prueba, por ejemplo `trinchera_test Luis zombie vip` |
| `trinchera_decir <nombre> <mensaje>` | Globo de prueba sobre el NPC de ese nombre, por ejemplo `trinchera_decir Luis hola a todos`. Para probar un emote: `palabra=id`, por ejemplo `trinchera_decir Luis hola Kappa=25` |
| `trinchera_frase` | Un NPC al azar dice una frase ambiental ahora mismo |
| `trinchera_resbalar` | El NPC que miras (o uno al azar) se resbala |
| `trinchera_animar` | El NPC que miras (o uno al azar) hace una animación al azar |
| `trinchera_animaciones` | Lista en la consola todas las animaciones del NPC que miras; `[*]` marca las que se usan al azar |
| `trinchera_duelo <usuario1> <usuario2>` | Duelo inmediato entre los NPCs de esos viewers, por ejemplo `trinchera_duelo ana luis` |
| `trinchera_votacion` | Abre una votación |
| `trinchera_evento horda` / `rebelion` / `lenta` | Lanza el evento sin votar |
| `trinchera_ver [usuario]` / `trinchera_ver_salir` | Cámara en tercera persona sobre un NPC de viewer |
| `trinchera_limpiar` | Borra todos los NPCs de viewers |
| `trinchera_tipos` | Lista los comandos activos |

También puedes quitarlos con **Z** (deshacer).

## Probar sin estar en vivo

Con GMod abierto en un mapa, doble clic en `bridge/prueba.bat`.
