# Lista de mods candidatos — análisis

Investigación de los 47 candidatos propuestos por el grupo. Datos obtenidos de
la API pública del Workshop de Steam (`ISteamRemoteStorage/GetPublishedFileDetails`),
no de guías: título, etiquetas de Build, fecha de actualización y descripción
completa de cada uno.

Referencia temporal: **Build 42 estable (42.20) salió el 29/07/2026**. Análisis
hecho el 09/08/2026.

---

## Descartados: solo Build 41 (13)

No tienen etiqueta *Build 42* o el propio autor los marca como exclusivos de
Build 41. No van a funcionar en 42.20.

| ID | Nombre | Últ. act. | Nota |
| --- | --- | --- | --- |
| 2487022075 | True Actions. Act 1 & 2 - Sitting & Lying | 2023-01-01 | El título dice literalmente **[Only for B41]** |
| 2648779556 | True Actions. Act 3 - Dancing | 2022-01-20 | Solo B41 |
| 3236152598 | The Only Cure | 2025-10-05 | El título dice **[B41]** |
| 2903771337 | Reorder The Hotbar | 2024-12-18 | Solo B41 **y** marcado DISCONTINUED |
| 2732804047 | Players On Map | 2024-10-20 | Sin etiqueta de Build 42 |
| 2659216714 | Just Throw Them Out The Window | 2023-07-10 | Solo B41 |
| 2962908954 | Tariqs Beards | 2023-07-05 | Solo B41 |
| 2835829018 | Weapon Condition Indicator_ES | 2023-06-02 | Traducción del de abajo; cae con él |
| 2687798127 | Water Dispenser | 2022-08-09 | Solo B41 |
| 2631149521 | Eggon's Have I Found This Book??? | 2022-08-06 | Solo B41 **y** requiere *Eggon's Modding Utils*, que no está en la lista |
| 2832401837 | Tuck and Roll | 2022-07-12 | Solo B41 |
| 2701170568 | Extra Map Symbols | 2022-02-27 | Solo B41 |
| 2619072426 | Weapon Condition Indicator | 2022-01-06 | Solo B41 **y** requiere *Mod Options*, que no está en la lista |

## Descartados: descatalogados por su autor (2)

Tienen etiqueta Build 42 pero el autor los abandonó, y llevan sin tocarse desde
antes de la estable.

| ID | Nombre | Últ. act. | Nota |
| --- | --- | --- | --- |
| 2950902979 | Equipment UI - Paper Doll | 2025-12-24 | DISCONTINUED en el título |
| 2901962885 | Reorder Containers | 2025-12-28 | DISCONTINUED, **y CleanUI dice expresamente que su función ya está integrada** |

---

## Dependencia crítica que faltaba

**NeatUI Framework — `3508537032` — Mod ID `NeatUI_Framework`**

Lo exigen **cinco** mods de la lista: CleanUI, Neat Building, Neat Crafting,
Project Cook y Modern Status. No estaba entre los candidatos. Sin él, esos
cinco no cargan.

Actualizado 08/08/2026, soporte declarado *B42.0.2 a B42.20.x*, 853k
suscriptores. Debe cargar **antes** que cualquiera que dependa de él, y hay que
añadirlo también a la suscripción de cada jugador.

---

## Lista activa en produccion

Copia versionada de lo que hay en `.env`, que esta fuera de git. Si se pierde
el `.env` (o al migrar de maquina), esto es lo que hay que restaurar.

```
PZ_WORKSHOP_ITEMS=3508537032;3437629766;3536052310;3502080466;3490188370;3451167732;2847184718;2998737588;3394044313;3592172476;3147428398;2313387159;2734705913;2544353492;3041733782

PZ_MODS=ATakeABathAndShowerDepthMap;NeatUI_Framework;SpnHairAPI;ProximityInventory;CleanUI;Neat_Crafting;Neat_Building_UIOnly;Project_Cook;ModernStatus;SplitItems;BetterSortCC;ComfySleeping;Buttstroke;TakeABathAndShowerNew;P4HasBeenRead;MapSymbolSizeSlider
```

Son 15 elementos del Workshop y 16 Mod ID: *Take A Bath And Shower* aporta dos
(el mod y su arreglo de DepthMap, que va el primero de la lista).

**Cada jugador debe estar suscrito a los 15.** Lo comodo es montar una
coleccion de Steam con ellos y compartir el enlace: un boton y listo.

---

## Lote A — confirmados y probados (15)

Autor declara soporte hasta 42.20, o actualizados después de la estable.
**Probados juntos en staging: los 15 cargan y el servidor arranca.**

| Orden | ID | Mod ID | Nombre |
| --- | --- | --- | --- |
| 1 | 3508537032 | `NeatUI_Framework` | NeatUI Framework — *dependencia, va primero* |
| 2 | 3041733782 | `SpnHairAPI` | Spongie's Hairstyle Unlocker |
| 3 | 2847184718 | `ProximityInventory` | Proximity Inventory B42.20+ |
| 4 | 3437629766 | `CleanUI` | CleanUI |
| 5 | 3502080466 | `Neat_Crafting` | Neat Crafting |
| 6 | 3536052310 | `Neat_Building` | Neat Building |
| 7 | 3490188370 | `Project_Cook` | Project Cook |
| 8 | 3451167732 | `ModernStatus` | Modern Status |
| 9 | 3147428398 | `SplitItems` | Split Items |
| 10 | 2313387159 | `BetterSortCC` | Better Sorting |
| 11 | 2998737588 | `ComfySleeping` | Comfy Sleeping |
| 12 | 3394044313 | `Buttstroke` | Buttstroke / Gun Stock Attack |
| 13 | 3592172476 | `TakeABathAndShowerNew` | Take A Bath And Shower |
| 14 | 2544353492 | `P4HasBeenRead` | Has Been Read |
| 15 | 2734705913 | `MapSymbolSizeSlider` | Map Symbol Size Slider |

**Pendiente de comprobar en juego:** con los mods cargados aparecen 6 avisos
`require(...) failed` en ficheros Lua del juego base (`corpseStorageCheck`,
`ISCampingMenu`, `ISInventoryTransferUtil`). **No aparecen en producción sin
mods**, así que los provocan los mods — casi seguro los de interfaz de
inventario. No impiden arrancar, pero hay que verificar en juego que los menús
contextuales, el traslado de objetos y el campamento funcionan.

## Lote B — sin confirmación explícita para 42.20 (18)

Tienen etiqueta Build 42 pero no se han tocado desde antes de la estable, o
declaran soporte para una versión anterior. Se prueban en una segunda tanda,
sobre la base ya validada del lote A.

| ID | Mod ID | Nombre | Últ. act. |
| --- | --- | --- | --- |
| 3028528478 | `blankets` (+2 variantes) | Beds Have Blankets | 2026-08-07 |
| 3461415167 | `BicycleMod` | Bicycle! [B42.15+] | 2026-07-10 |
| 3600401184 | `RC_RealisticColdMod` | Realistic Temperature [B42.18+] | 2026-06-10 |
| 3397207461 | `Run and Reload` | Run and Reload | 2026-05-31 |
| 2650547917 | `manageContainers` | Manage Containers | 2026-05-27 |
| 3589548354 | `improvedhairmenubuild42` | Improved Hair Menu | 2026-05-05 |
| 3396867685 | `StarvingZombies` | Starving Zombies | 2026-04-24 |
| 2463184726 | `SpnHair` | Spongie's Hair | 2026-03-12 |
| 3641697417 | `Reading+` | Reading+ [B42.13] | 2026-02-13 |
| 3330403100 | `KI5trailers` | Trailers! | 2026-01-29 |
| 2944344655 | `ReplaceBandage` | Replace Bandage | 2026-01-02 |
| 2883633728 | `IMightNeedALighter` | I Might Need A Lighter 42.12 | 2025-12-15 |
| 3402513620 | `CatseyeInTheDark` | Cat's eye in the Dark | 2025-12-14 |
| 3410947298 | `nm_nested_containers` | Nested Containers | 2025-12-13 |
| 3446510982 | `EquipClothingWhileMoving` | Equip Clothing While Moving | 2025-12-13 |
| 3391902125 | `throw-your-bag-across` | Throw your bag across | 2025-08-08 |
| 3453580134 | *(por determinar)* | Right Click To Wear | 2025-05-20 |
| 3399645148 | `MapSymbolsPlusDeonHand` | Map Symbols Plus | 2025-01-04 |

---

## Restricciones de orden y solapamientos

**Órdenes de carga obligatorios (declarados por los autores):**

- `NeatUI_Framework` antes que CleanUI, Neat Crafting, Neat Building, Project
  Cook y Modern Status.
- `nm_nested_containers` **antes** que `ProximityInventory`, o no detecta los
  contenedores anidados.

**Zona de riesgo: cinco mods tocan la interfaz de inventario y contenedores.**

CleanUI, Proximity Inventory, Nested Containers, Manage Containers y Better
Sorting. El autor de CleanUI avisa explícitamente: *"usar varios mods de
reforma de la UI de inventario juntos es más propenso a causar conflictos"*.

Matiz importante: CleanUI declara compatibilidad con **Proximity Inventory
`3669550831`**, que es un **fork distinto** del que hay en la lista
(`2847184718`). Cargan juntos, pero la compatibilidad no está declarada para
esa combinación concreta y hay que verificarla en juego.

**Solapamientos menores:**

- Cabello: `SpnHair` + `SpnHairAPI` + `improvedhairmenubuild42` son
  complementarios, pero el API va antes.
- Símbolos de mapa: `MapSymbolSizeSlider` + `MapSymbolsPlusDeonHand` conviven,
  pero el segundo es de enero de 2025.

**Incompatibilidades declaradas con mods que NO están en la lista** (sin
problema, se anotan por si alguien los propone más adelante):

- Take A Bath And Shower ↔ *Item Arrange*
- Better Containers ↔ Proximity Inventory
- Bicycle! ↔ *Gael's Gun Store* y otros mods de armas que alteran las mejoras
- Neat Building ↔ *Stairs East & South* (hay una variante de compatibilidad)

---

## Variantes dentro de un mismo elemento del Workshop

Varios elementos traen más de un Mod ID. **No se activan todos**: son
alternativas o complementos, y elegir mal tiene consecuencias.

### Neat Building (3536052310) — 4 variantes, decisión de una sola dirección

| Mod ID | Qué es |
| --- | --- |
| `Neat_Building` | Completa (legacy): la interfaz **más** todos los construibles **y** las barandillas metálicas |
| `Neat_Building_UIOnly` | **Solo la interfaz.** No añade ninguna entidad construible |
| `Neat_Building_Buildables_SESCompat` | Los construibles **sin** las barandillas metálicas que chocan con *Stairs East & South* |
| `Neat_Building_Railings` | Solo las barandillas metálicas |

La completa **no** se combina con las modulares: o una o las otras.

**Esto es lo importante.** El autor avisa de que en servidores multijugador,
quitar una variante con construibles de un mundo existente puede provocar
errores de `WorldDictionary` **que impiden cargar el mundo**. Existe incluso un
mod aparte de "Safe Uninstall Support" para mundos que la quitaron. Su
recomendación es mantener la misma variante una vez que el mundo la ha usado.

Es exactamente el escenario de corrupción que este proyecto intenta evitar, así
que la variante se elige **antes** de crear el mundo definitivo y no se toca.

`Neat_Building_UIOnly` es la opción segura: al no añadir entidades, quitarla
más adelante no puede romper el `WorldDictionary`. El propio autor dice que esta
variante no necesita el Safe Uninstall Support. Las que traen construibles son
un compromiso deliberado a cambio de más piezas de construcción.

No tenemos *Stairs East & South*, así que la variante SESCompat no aporta nada.

### Take A Bath And Shower (3592172476) — 2, complementarias

| Mod ID | Qué es |
| --- | --- |
| `TakeABathAndShowerNew` | El mod principal |
| `ATakeABathAndShowerDepthMap` | Arreglo de mapas de profundidad de bañeras y duchas. **Debe ir el primero de toda la lista** (por eso la `A` inicial: es para que ordene alfabéticamente arriba) |

Se activan las dos.

### Project Cook (3490188370) — 1 principal + 1 opcional estético

| Mod ID | Qué es |
| --- | --- |
| `Project_Cook` | El mod principal |
| `Project_Cook_Pixel_Icon_Pack` | Opcional: sustituye algunos iconos del panel de cocina por versiones en pixel-art. Debe cargar **después** de Project Cook |

### Buttstroke (3394044313) — ojo, una de ellas no se toca

| Mod ID | Qué es |
| --- | --- |
| `Buttstroke` | El mod |
| `Buttstroke42.12.3` | Versión antigua para builds 42.12.x. Su propio nombre interno es **"42.12.3 Buttstroke (DO NOT ENABLE)"** |

### Pendientes de determinar

El autor no explica las variantes y aún no están descargadas. Se resolverán al
probar el lote B, mirando los `mod.info`:

- Starving Zombies (3396867685): `StarvingZombies`, `StarvingZombiesWIP`
- Beds Have Blankets (3028528478): `blankets`, `Bedding Covers-With Pillows`,
  `Bedding Covers-no pillows`

Better Sorting (2313387159) repite `BetterSortCC` dos veces en su descripción,
pero es un único mod: no hay variante que elegir.

### Nota sobre las etiquetas `[B42.12]`, `[B42.13]`, `[Legacy]`

Al inspeccionar los mods descargados aparecen entradas como *Neat Building
[B42.12]* o *Project Cook [Legacy]*. **No son variantes que haya que elegir**:
son las carpetas versionadas de Build 42, y el juego escoge sola la que
corresponde a la versión instalada. Comparten Mod ID con la principal.

---

## Resultado del lote B

**37 mods cargando, 0 errores criticos, servidor arrancado.**

### Cuatro dependencias mas que faltaban

Ninguna estaba en la lista y sin ellas su mod no carga:

| Workshop ID | Mod ID | Lo exige |
| --- | --- | --- |
| 3171167894 | `damnlib` | Trailers! (`KI5trailers`) |
| 2969455858 | `TargetSquareOnLoad` | Beds Have Blankets (`blankets`) |
| 2447729538 | `FH` (Fluffy Hair) | Spongie's Hair (`SpnHair`) |
| 3676456221 | `LuaDigitalWatchUI` | Realistic Temperature (`RC_RealisticColdMod`) |

### Descartado: I Might Need A Lighter (2883633728)

Su `mod.info` declara **`versionMax=42.12`**. Estamos en 42.20, asi que el juego
lo rechaza por diseno. No hay arreglo por nuestra parte; hace falta que el autor
lo actualice. El titulo del propio mod ya lo avisaba ("42.12").

### Correcciones de IDs

- **Run and Reload**: su Mod ID real es `Run and Reload`, **con espacios**. La
  descripcion del Workshop lo decia bien.
- **Right Click To Wear**: `DELRAN_CLICK_TO_WEAR`.
- **Beds Have Blankets**: `blankets` es la version actual; `BeddingCovers-*` son
  las *Legacy*.
- **Starving Zombies**: `StarvingZombies` (la `WIP` es la de desarrollo).

### Hipotesis que se probaron y resultaron FALSAS

Se anotan para no volver a perder tiempo con ellas:

- *"Un mod sin `mod.info` en la raiz no carga"*: falso. Hay 20 asi (CleanUI,
  NeatUI_Framework, Neat_Crafting, Reading+...) y cargan sin problema.
- *"Las carpetas con espacios en el nombre no cargan"*: falso. Take A Bath And
  Shower New, Map Symbol Size Slider y Spongie Hair las tienen y funcionan.
- *"Es una carrera entre la descarga de Steam y el indexado"*: falso. Fallaban
  igual tras reiniciar.

La causa real siempre estuvo en el `mod.info`: un ID mal leido, una dependencia
declarada solo dentro de `42/`, y un limite de version.

---

## Correccion pendiente en el orden de carga

**`SpnHairAPI` (Spongie's Hairstyle Unlocker) debe cargar DESPUES de
`improvedhairmenubuild42` (Improved Hair Menu).** Su autor lo dice en
mayusculas: *"LOAD THIS MOD AFTER IMPROVED HAIR MENU OR IT WON'T WORK"*.

En la lista validada va en la posicion 7 y Improved Hair Menu en la 35, o sea
al reves. El servidor arranca igual —por eso no salio en las pruebas— pero el
desbloqueo de peinados no funcionara.
