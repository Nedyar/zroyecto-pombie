# Mods adoptados

**36 elementos del Workshop · 37 Mod ID** — validados en staging el 10/08/2026
sobre Project Zomboid **42.20**: los 37 cargan y el servidor arranca sin errores
de script.

El orden de las tablas **es el orden de carga**. No es decorativo: `Mods=` se
evalúa en orden y los últimos sobrescriben a los anteriores.

Los `Mod ID` van tal cual, sin prefijo `\` (varias guías dicen que Build 42 lo
exige; comprobado que no) y **respetando los espacios** cuando los llevan dentro.

---

## Frameworks y dependencias

No se juegan: los exigen otros mods de la lista y van los primeros.

| Nombre | Mod ID | Workshop | Qué hace |
| --- | --- | --- | --- |
| Take A Bath And Shower: DepthMap fix | `ATakeABathAndShowerDepthMap` | 3592172476 | Arregla los mapas de profundidad de bañeras y duchas. Su autor pide que vaya **el primero de toda la lista** |
| NeatUI Framework | `NeatUI_Framework` | 3508537032 | Base de interfaz compartida por toda la familia *Neat*. No se usa directamente |
| that DAMN Library | `damnlib` | 3171167894 | Framework que sostiene todos los mods de vehículos de KI5 |
| Target Square: On Load Commands | `TargetSquareOnLoad` | 2969455858 | Permite ejecutar funciones cuando se carga una casilla del mapa, sin que cada mod repita las mismas comprobaciones |
| Fluffy Hair | `FH` | 2447729538 | Modelos de pelo ajustados para casi todos los sombreros, para que el peinado no se deforme al llevar algo en la cabeza |
| Lua Digital Watch Framework | `LuaDigitalWatchUI` | 3676456221 | Reconstruye en Lua la interfaz del reloj digital para que otros mods puedan modificarla |

## Interfaz e inventario

| Nombre | Mod ID | Workshop | Qué hace |
| --- | --- | --- | --- |
| Nested Containers | `nm_nested_containers` | 3410947298 | Ver dentro de bolsas y cajas guardadas en otro inventario, sin sacarlas. **Debe ir antes que Proximity Inventory** |
| Proximity Inventory | `ProximityInventory` | 2847184718 | Saquear a la vez todo lo que tienes alrededor, en lugar de contenedor por contenedor y cadáver por cadáver |
| CleanUI | `CleanUI` | 3437629766 | Rehace los paneles de inventario y saqueo: más compactos, rápidos y legibles, manteniendo el flujo original |
| Manage Containers | `manageContainers` | 2650547917 | Asignas categorías a cada contenedor de la base y el juego reparte el botín solo |
| Better Sorting | `BetterSortCC` | 2313387159 | Reorganiza por completo las categorías de objetos y ajusta muchos nombres. Incluye objetos de otros mods |
| Modern Status | `ModernStatus` | 3451167732 | Sustituye los indicadores de estado del personaje por círculos, barras y matrices configurables, con avisos y acciones rápidas |
| Split Items | `SplitItems` | 3147428398 | Dividir pilas de objetos en el inventario |

## Construcción, artesanía y cocina

| Nombre | Mod ID | Workshop | Qué hace |
| --- | --- | --- | --- |
| Neat Crafting | `Neat_Crafting` | 3502080466 | Menú de artesanía más claro y compacto: mejores categorías, navegación entre recetas encadenadas y manejo decente de listas largas con mods |
| Neat Building (solo interfaz) | `Neat_Building_UIOnly` | 3536052310 | Menú de construcción reorganizado por categorías, con mejores iconos y filtros. **Variante solo interfaz a propósito**: no añade objetos construibles, y por eso se puede quitar más adelante sin arriesgar el mundo |
| Project Cook | `Project_Cook` | 3490188370 | Interfaz dedicada de cocina, centrada en las recetas evolutivas (sopas, guisos, ensaladas, salteados) |

## Supervivencia y realismo

| Nombre | Mod ID | Workshop | Qué hace |
| --- | --- | --- | --- |
| Realistic Temperature | `RC_RealisticColdMod` | 3600401184 | Rehace la temperatura del aire, también en interiores. En invierno hay que abrigarse, buscar calefacción y cerrar puertas y ventanas; en verano se puede sufrir un golpe de calor por ir demasiado tapado |
| Starving Zombies | `StarvingZombies` | 3396867685 | Los zombis se sienten atraídos por los cadáveres (también de animales) y se los comen. Simula el olor que emites tú, la sangre encima y la de los objetos que llevas, y usa el viento para propagarlo |
| Comfy Sleeping | `ComfySleeping` | 2998737588 | La calidad del sueño depende de la ropa, el estado mental y la limpieza. Dormir con ropa voluminosa o la mochila puesta se paga |
| Take A Bath And Shower | `TakeABathAndShowerNew` | 3592172476 | Bañarse y ducharse de verdad, con mecánicas propias y un papel real en el día a día |
| Beds Have Blankets | `blankets` | 3028528478 | Las camas del mundo pueden aparecer con mantas. Se puede activar a mitad de partida, pero solo afecta a zonas nuevas |
| Cat's eye in the Dark | `CatseyeInTheDark` | 3402513620 | Mejora el rasgo *Cat's Eye*: visión tenue en la oscuridad |
| Replace Bandage | `ReplaceBandage` | 2944344655 | Cambiar un vendaje sucio por uno limpio en un solo paso, sin quitar y volver a poner |

## Combate y movilidad

| Nombre | Mod ID | Workshop | Qué hace |
| --- | --- | --- | --- |
| Buttstroke / Gun Stock Attack | `Buttstroke` | 3394044313 | Golpear a los zombis con la culata del arma |
| Run and Reload | `Run and Reload` | 3397207461 | Recargar mientras corres. **Ojo: su Mod ID lleva espacios** |
| Bicycle! | `BicycleMod` | 3461415167 | Bicicleta montable que aumenta la velocidad de movimiento. Se dirige con el botón derecho o Ctrl |
| Trailers! | `KI5trailers` | 3330403100 | Seis remolques enganchables, con piezas 3D que se pueden quitar y colocar, y extras que fabricar o encontrar (lonas, cajas de herramientas, bidones) |
| Throw your bag across | `throw-your-bag-across` | 3391902125 | Lanzar bolsas por ventanas y sobre vallas, o a cualquier casilla en un radio de 7 |

## Ropa y aspecto

| Nombre | Mod ID | Workshop | Qué hace |
| --- | --- | --- | --- |
| Improved Hair Menu | `improvedhairmenubuild42` | 3589548354 | Menú de peinados y barbas mucho más manejable, en la creación del personaje y en la pantalla de personaje |
| Spongie's Hair | `SpnHair` | 2463184726 | Peinados nuevos. Los que rompen la ambientación no aparecen en los zombis |
| Spongie's Hairstyle Unlocker | `SpnHairAPI` | 3041733782 | Permite elegir cualquier peinado de la misma longitud al cortarte el pelo. **Su autor exige que cargue DESPUÉS de Improved Hair Menu** |
| Right Click To Wear | `DELRAN_CLICK_TO_WEAR` | 3453580134 | Equipar ropa del suelo con clic derecho, sin recogerla primero |
| Equip Clothing While Moving | `EquipClothingWhileMoving` | 3446510982 | Ponerse ropa andando o apuntando. El juego base solo lo permite para algunas partes del cuerpo desde la 42.13; esto lo extiende al resto |

## Lectura y mapa

| Nombre | Mod ID | Workshop | Qué hace |
| --- | --- | --- | --- |
| Reading+ | `Reading+` | 3641697417 | Leer mientras caminas, leer más rápido sentado en un buen sofá, y encolar varios libros en lugar de ir uno a uno |
| Has Been Read | `P4HasBeenRead` | 2544353492 | Marca claramente los libros **no** leídos o a medias, para reconocerlos de un vistazo mientras saqueas |
| Map Symbol Size Slider | `MapSymbolSizeSlider` | 2734705913 | Control deslizante para cambiar el tamaño de símbolos y notas del mapa |
| Map Symbols Plus | `MapSymbolsPlusDeonHand` | 3399645148 | Símbolos de mapa dibujados a mano: chinchetas de "seguro", "desconocido" y "peligro", entre otros |

---

## Corrección pendiente en el orden de carga

**`SpnHairAPI` (Spongie's Hairstyle Unlocker) tiene que cargar DESPUÉS de
`improvedhairmenubuild42` (Improved Hair Menu).** Lo dice su autor en mayúsculas:
*"LOAD THIS MOD AFTER IMPROVED HAIR MENU OR IT WON'T WORK"*.

En la lista probada va casi al principio (posición 7) y Improved Hair Menu casi
al final (posición 35), así que está al revés. El servidor arranca igual —
por eso no salió en las pruebas— pero el desbloqueo de peinados no funcionará.
Hay que mover `SpnHairAPI` detrás de `improvedhairmenubuild42`.

## Restricciones de orden ya respetadas

- `ATakeABathAndShowerDepthMap` el primero de todo.
- `NeatUI_Framework` antes que CleanUI, Neat Crafting, Neat Building, Project
  Cook y Modern Status.
- `nm_nested_containers` antes que `ProximityInventory`.
- `damnlib` antes que `KI5trailers`.
- `TargetSquareOnLoad` antes que `blankets`.
- `FH` antes que `SpnHair`.
- `LuaDigitalWatchUI` antes que `RC_RealisticColdMod`.

## Zona de riesgo conocida

Seis mods tocan la interfaz de inventario y contenedores: CleanUI, Proximity
Inventory, Nested Containers, Manage Containers, Better Sorting y Split Items.
El autor de CleanUI avisa de que juntar varios mods de reforma de inventario es
propenso a conflictos. Cargan todos sin error, pero es la primera zona donde
mirar si algo se comporta raro en juego.

## Para los jugadores

Cada uno debe estar suscrito en Steam a **los 36 elementos**, o no podrá entrar.
Lo cómodo es montar una colección del Workshop con todos y compartir el enlace:
un botón de *Suscribirse a todo* y listo.
