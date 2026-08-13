# Mods: estado y decisiones

Documento técnico. Para la lista en lenguaje llano que se pasa a los jugadores,
ver [MODS-ADOPTADOS.md](MODS-ADOPTADOS.md).

Punto de partida: 47 candidatos propuestos por el grupo. Los datos salieron de
la API pública del Workshop (`ISteamRemoteStorage/GetPublishedFileDetails`) y de
los `mod.info` realmente descargados, no de guías.

Referencia temporal: **Build 42 estable (42.20) salió el 29/07/2026.**

---

# 0. El mundo vanilla y las oleadas (14/08/2026)

El mundo activo pasó a ser **pombie-vanilla** y el grupo quiere ir añadiéndole
mods. Las cuatro investigaciones de `docs/incidencias/` (rama
`docs/incidencias-jugabilidad`) demostraron que los mods no causan los bugs
abiertos, así que no hay motivo técnico para frenarse. Lo que sí hay es una
asimetría que manda sobre todo lo demás: **sobre un mundo ya empezado, la
pregunta no es "¿este mod es bueno?" sino "¿puedo deshacerlo?"**.

## El criterio: reversibilidad medida, no leída

Se escaneó **lo realmente descargado** en el volumen de producción, no las
descripciones del Workshop: ficheros bajo `media/scripts/` (definiciones de
items, recetas, vehículos, entidades) y packs de tiles/sprites, agregando por
Mod ID real para esquivar las carpetas de variantes.

Resultado: **28 de los 35 mods de producción no declaran nada persistente**.
Se pueden quitar de un mundo jugado sin dejar referencias rotas. Los 7
restantes son de **vía única** — al quitarlos, lo que crearon queda huérfano:

| Mod | Declara | Gravedad al quitarlo |
| --- | --- | --- |
| `KI5trailers` (+su dependencia `damnlib`) | **66 vehículos** | La mayor: vehículos construidos quedan rotos |
| `RC_RealisticColdMod` | **estufas colocables** (`Mov_RC*Heater`) | Objetos puestos en el mundo persisten |
| `BicycleMod` | items + recetas | Bicis desaparecen de inventarios |
| `TakeABathAndShowerNew` | items + fluidos | Ídem |
| `BB_CommonSenseFix` | items + recetas | Ídem |
| `manageContainers` | un huevo de pascua (gorro + sonido) | Mínima, pero técnicamente persiste |

Dos matices que salieron de mirar el contenido y no solo contar ficheros:
`Buttstroke` declara únicamente un **sonido** (no persiste → reversible), y
ninguno de los 35 declara **construibles** (`entities`), que es el caso grave
documentado en la sección 5 — el que puede impedir que un mundo cargue.

## Las oleadas

| Oleada | Qué | Condición |
| --- | --- | --- |
| **1 — aplicada** | Los 17 reversibles de interfaz/QoL + `Tariq's Beards` (local, elegido por el grupo) | Ninguna: si molesta, se quita |
| **2 — preparada** | Common Sense, Take A Bath (+DepthMap), Manage Containers, Realistic Temperature (+LuaDigitalWatchUI) | **Solo tras probarse en staging sobre copia del vanilla.** Entran para quedarse |
| **Decisión de grupo** | `Trailers!` (KI5trailers+damnlib) | Irreversible de verdad; que se decida sabiéndolo |
| **Decisión de grupo** | `StarvingZombies` | Reversible y exonerado (incidencia 001), pero cambia jugabilidad, no interfaz |
| **Nunca** | `Bicycle!` | Defectuoso en 42.20 (incidencia 002) **e** irreversible: la peor combinación. Se reevalúa si el autor publica para 42.20 |

## Regla vigente desde el 15/08/2026: nada irreversible

Decisión del grupo: **no entra ningún mod que declare definiciones
persistentes**. Congela la oleada 2 entera y descarta Trailers!.

No es un juicio sobre su calidad —los cuatro de la oleada 2 son buenos— sino
sobre la asimetría: en un mundo donde ya hay meses de partida, un mod que no
se puede sacar es una apuesta sin marcha atrás, y la marcha atrás es
precisamente lo que este montaje existe para conservar.

Lo que sigue vivo bajo la regla:

- **StarvingZombies**: reversible y exonerado por la incidencia 001. Solo
  pendiente de votación porque cambia jugabilidad, no por riesgo técnico.
- **Cualquier candidato nuevo**, si pasa la medición de reversibilidad. El
  procedimiento: meterlo en `STAGING_*`, `./scripts/stage.sh --from
  pz-vanilla`, y escanear lo descargado con el método de esta sección. Cero
  scripts = admisible.

Evaluado y descartado bajo esta regla el 15/08: los **mods-parche de
sincronización de vehículos**. Ninguno reunía atacar vehículos + estar
mantenido para 42.20 + distribuirse por Steam. Detalle en la incidencia 005.

## Reglas de inserción para la oleada 2

El orden de carga del vanilla se derivó **filtrando la cadena de producción**
(sección 1), que ya respeta las siete reglas de la sección 4. Al añadir los de
la oleada 2 hay que devolverlos a su posición relativa:

- `ATakeABathAndShowerDepthMap` → **primero de toda la lista**.
- `BB_CommonSenseFix` → **antes de `CleanUI`** (regla 3bis, se descubrió
  rompiendo la interfaz).
- `LuaDigitalWatchUI` → antes de `RC_RealisticColdMod`.
- `manageContainers` → entre `CleanUI` y `BetterSortCC` (posición original).

## Por qué la oleada 1 entró en bloque y no de uno en uno

La regla 4 de `AGENTS.md` («un mod se añade de uno en uno y pasando por
staging») existe para mods **sin historial**: si el mundo falla con tres
nuevos, no sabes cuál fue. Estos 18 llevan semanas corriendo **juntos** en
producción con el checklist en juego mayormente pasado: su compatibilidad
entre sí es un hecho observado, no una apuesta. Y son reversibles: el peor
caso es una molestia, no un daño. Un conjunto probado en otra instancia entra
como bloque; lo que entre sin ese historial sigue yendo de uno en uno.

---

# 1. Lo que está activo ahora

**Corriendo en producción**, sobre un mundo creado ya con esta lista. Verificado
contra el INI que el servidor tiene renderizado: 33 elementos del Workshop, 35
Mod ID, 0 `required mod not found`.

Hubo un mundo anterior, creado mientras las votaciones se cerraban y por tanto
con la lista antigua. Se borró junto con sus backups y se regeneró desde cero en
lugar de retirarle los mods en caliente: era un mundo recién creado y sin nadie
dentro, así que rehacerlo salía más barato y más limpio que arrastrarlo.

Queda pendiente la comprobación en juego, mod por mod: ver
[CHECKLIST-MODS.md](CHECKLIST-MODS.md).

**33 elementos del Workshop · 35 Mod ID.** La diferencia sale de que *Take A
Bath And Shower* aporta dos IDs, y de que *Tariq's Beards* no viene del Workshop
sino de una carpeta local.

## Copia de seguridad de la configuración

`.env` está fuera de git. Si se pierde, o al migrar de máquina, esto es lo que
hay que restaurar.

```
WorkshopItems=3508537032;3437629766;3536052310;3502080466;3490188370;3451167732;2847184718;2998737588;3394044313;3592172476;3147428398;2313387159;2734705913;2544353492;3041733782;3461415167;3600401184;3397207461;2650547917;3589548354;3396867685;2463184726;3641697417;3330403100;2944344655;3402513620;3410947298;3446510982;3399645148;3171167894;2447729538;3676456221;3717968421
```

```
Mods=ATakeABathAndShowerDepthMap;NeatUI_Framework;damnlib;FH;LuaDigitalWatchUI;SpnHair;Tariq's Beards;nm_nested_containers;ProximityInventory;BB_CommonSenseFix;CleanUI;manageContainers;BetterSortCC;Neat_Crafting;Neat_Building_UIOnly;Project_Cook;ModernStatus;KI5trailers;BicycleMod;RC_RealisticColdMod;Run and Reload;StarvingZombies;TakeABathAndShowerNew;ComfySleeping;Buttstroke;ReplaceBandage;CatseyeInTheDark;EquipClothingWhileMoving;Reading+;SplitItems;P4HasBeenRead;improvedhairmenubuild42;SpnHairAPI;MapSymbolSizeSlider;MapSymbolsPlusDeonHand
```

El orden **es** el orden de carga. Los ID van sin prefijo `\` y respetando los
espacios cuando los llevan dentro (`Run and Reload`, `Tariq's Beards`).

## Mod local: Tariq's Beards

No sale del Workshop. Vive en `Zomboid/mods/` dentro del volumen del servidor, y
cada jugador necesita una copia en su propia carpeta `Zomboid/mods`.

**No está en el repositorio, y es deliberado.** Son assets de un tercero sin
licencia declarada ni respuesta del autor, y el historial de git es permanente:
si se commitean y luego Tariq dice que no, quitarlos del último commit no los
saca del historial. Viven en `workbench/`, que está en `.gitignore`.

Para instalarlos en cualquier máquina:

```bash
./scripts/install-local-mods.sh <ruta-al-zip> [pz|pz-staging]
```

Acepta un `.zip` o una carpeta, encuentra solo dónde está el `mod.info` y
resuelve los zips hechos con `Compress-Archive` de PowerShell, que usan barras
invertidas y no se descomprimen bien en Linux.

El fichero se distribuye por el canal privado del grupo, el mismo por el que los
jugadores reciben su copia.

## Pendiente

**Permiso de Tariq.** Se le ha escrito. Hasta que responda, el port no se publica
y solo circula entre el grupo.

---

# 2. Lo que se descartó

## Solo Build 41 (13, uno de ellos rescatado)

Sin etiqueta *Build 42*, o el autor los marca como exclusivos de B41.

| ID | Nombre | Últ. act. | Nota |
| --- | --- | --- | --- |
| 2487022075 | True Actions. Act 1 & 2 | 2023-01-01 | El título dice **[Only for B41]** |
| 2648779556 | True Actions. Act 3 - Dancing | 2022-01-20 | |
| 3236152598 | The Only Cure | 2025-10-05 | El título dice **[B41]** |
| 2903771337 | Reorder The Hotbar | 2024-12-18 | Además marcado DISCONTINUED |
| 2732804047 | Players On Map | 2024-10-20 | Sin etiqueta de Build 42 |
| 2659216714 | Just Throw Them Out The Window | 2023-07-10 | |
| 2962908954 | Tariqs Beards | 2023-07-05 | **Rescatado** reempaquetándolo — ver sección 1 |
| 2835829018 | Weapon Condition Indicator_ES | 2023-06-02 | Traducción del de abajo; cae con él |
| 2687798127 | Water Dispenser | 2022-08-09 | |
| 2631149521 | Eggon's Have I Found This Book??? | 2022-08-06 | Y requiere *Eggon's Modding Utils*, ausente |
| 2832401837 | Tuck and Roll | 2022-07-12 | |
| 2701170568 | Extra Map Symbols | 2022-02-27 | |
| 2619072426 | Weapon Condition Indicator | 2022-01-06 | Y requiere *Mod Options*, ausente |

## Descatalogados por su autor (2)

| ID | Nombre | Últ. act. | Nota |
| --- | --- | --- | --- |
| 2950902979 | Equipment UI - Paper Doll | 2025-12-24 | DISCONTINUED en el título |
| 2901962885 | Reorder Containers | 2025-12-28 | DISCONTINUED, y CleanUI declara que ya integra esa función |

## Incompatible por declaración del autor (1)

| ID | Nombre | Motivo |
| --- | --- | --- |
| 2883633728 | I Might Need A Lighter | Su `mod.info` declara **`versionMax=42.12`** y estamos en 42.20. El juego lo rechaza por diseño |

## Retirados despues de probarlos (3)

| ID | Nombre | Motivo |
| --- | --- | --- |
| 3453580134 | Right Click To Wear | Funcionaba, pero Common Sense hace lo mismo con más alcance (armas y mochilas, no solo ropa). Ver sección 3bis |
| 3028528478 | Beds Have Blankets (y con el su dependencia `2969455858` TargetSquareOnLoad, que solo servia para el) | Las mantas salen dobladas sobre la cama en vez de puestas. Su codigo comprueba `getActivatedMods():contains("\TargetSquareOnLoad")`, con barra invertida, pero `getActivatedMods()` devuelve el ID canonico sin barra. La comprobacion no puede dar verdadero, se escriba como se escriba en `Mods=`: es un fallo del autor, no configurable. El mod era estetico |
| 3391902125 | Throw your bag across | **Roto en 42.20 y ademas peligroso.** La opcion sale en el menu, arranca la accion y no hace nada; la bolsa queda pegada a la mano. El log lo confirma: `no such function "ISThrowBag.new"` |

---

# 3. Dependencias que hubo que añadir

Ninguna estaba entre los 47 candidatos. Sin ellas, su mod no carga.

| Workshop ID | Mod ID | Lo exige |
| --- | --- | --- |
| 3508537032 | `NeatUI_Framework` | CleanUI, Neat Building, Neat Crafting, Project Cook, Modern Status |
| 3171167894 | `damnlib` | Trailers! |
| 2447729538 | `FH` (Fluffy Hair) | Spongie's Hair |
| 3676456221 | `LuaDigitalWatchUI` | Realistic Temperature |

---

# 3bis. Common Sense

Nunca estuvo entre los 47 candidatos: se uso como cobaya para probar el circuito
de mods y luego se adopto.

**Adoptado: `3717968421` — Common Sense B42.20 Community Compatibility Fix —
Mod ID `BB_CommonSenseFix`.** Actualizado el 09/08/2026, hecho para la 42.20
estable, **standalone** (no necesita el original) y etiquetado Multiplayer.

## Por que ese fork y no otro

| Fork | Descartado porque |
| --- | --- |
| `2875848298` original | Comprobado por nosotros: tumba el servidor en 42.20 con `require("recipecode") failed` |
| `3750253491` Common Sense [B42.20+] | 134k subs pero recalca *"FOR SINGLE PLAYER it works flawlessly"*. Mala senal para un servidor |
| `3667553980` Patch [B42.13+] | Parche sobre el original, no standalone. Va por 42.13 |
| `3586053117` Common Sense B42 Patch | Igual, parche sobre el original. Octubre 2025 |
| `3770106656` | Ya no existe; la API no devuelve nada |

## Consecuencias en la lista

**Se quito `DELRAN_CLICK_TO_WEAR` (Right Click To Wear, `3453580134`).** Common
Sense trae *"equip weapons, clothing and backpacks from the ground through the
context menu"*, que hace lo mismo con mas alcance.

**Recupera una funcion que se habia perdido.** Su interfaz de arma muestra
municion, estado y condicion, que es lo que hacia *Weapon Condition Indicator*,
descartado por ser solo Build 41.

## Orden de carga: antes de CleanUI

Se probo primero **despues** de CleanUI, razonando que el ultimo sobrescribe y
asi sus opciones de menu contextual quedarian encima. **Rompio la interfaz en
juego**: desaparecieron los botones y el menu.

Va **antes**, para que CleanUI reconstruya los paneles por encima. Ambos
reemplazan ficheros de interfaz, y el que debe ganar es el que de verdad los
dibuja.

---

# 4. Reglas de orden de carga

Declaradas por los autores. Todas respetadas salvo la última.

- `ATakeABathAndShowerDepthMap` el primero de toda la lista.
- `NeatUI_Framework` antes que CleanUI, Neat Crafting, Neat Building, Project
  Cook y Modern Status.
- `nm_nested_containers` antes que `ProximityInventory`, o no detecta los
  contenedores anidados.
- `BB_CommonSenseFix` **antes** que `CleanUI`. No lo declara ningún autor: se
  descubrió rompiendo la interfaz en juego. Ver sección 3bis.
- `damnlib` antes que `KI5trailers`.
- `FH` antes que `SpnHair`; `LuaDigitalWatchUI` antes que
  `RC_RealisticColdMod`.
- `improvedhairmenubuild42` antes que `SpnHairAPI`. Su autor lo dice en
  mayúsculas: *"LOAD THIS MOD AFTER IMPROVED HAIR MENU OR IT WON'T WORK"*. Es la
  única regla que el servidor **no** delata: arranca igual, y lo que falla en
  silencio es el desbloqueo de peinados.

El bloque de pelo y barba queda entonces así: `FH` y el contenido (`SpnHair`,
`Tariq's Beards`) al principio, el menú `improvedhairmenubuild42` casi al final,
y `SpnHairAPI` justo detrás de él.

## Zona de riesgo

Seis mods tocan la interfaz de inventario y contenedores: CleanUI, Proximity
Inventory, Nested Containers, Manage Containers, Better Sorting y Split Items.
El autor de CleanUI avisa de que juntar varios mods de reforma de inventario es
propenso a conflictos. Cargan todos sin error, pero es la primera zona donde
mirar si algo se comporta raro en juego.

Matiz: CleanUI declara compatibilidad con **Proximity Inventory `3669550831`**,
un fork distinto del que usamos (`2847184718`).

## Incompatibilidades con mods que NO tenemos

Se anotan por si alguien los propone más adelante.

- Take A Bath And Shower ↔ *Item Arrange*
- Better Containers ↔ Proximity Inventory
- Bicycle! ↔ *Gael's Gun Store* y otros mods de armas que alteran las mejoras
- Neat Building ↔ *Stairs East & South*
- NeatUI Hairstyler ↔ *Improved Hair Menu* (por eso no se adoptó)

---

# 5. Variantes dentro de un mismo elemento del Workshop

Varios elementos traen más de un Mod ID. No se activan todos.

## Neat Building (3536052310) — decisión de una sola dirección

| Mod ID | Qué es |
| --- | --- |
| `Neat_Building` | Completa: interfaz **+** construibles **+** barandillas |
| `Neat_Building_UIOnly` | **Solo la interfaz.** Ninguna entidad construible. ← **la elegida** |
| `Neat_Building_Buildables_SESCompat` | Construibles sin las barandillas que chocan con *Stairs East & South* |
| `Neat_Building_Railings` | Solo las barandillas |

El autor avisa de que en servidores multijugador, quitar una variante con
construibles de un mundo existente puede provocar errores de `WorldDictionary`
que impiden cargar el mundo; existe un mod aparte de *Safe Uninstall Support*
precisamente para eso.

Se eligió `Neat_Building_UIOnly` porque al no añadir entidades, quitarla más
adelante no puede romper nada.

## Otros

| Elemento | Variantes | Decisión |
| --- | --- | --- |
| Take A Bath (3592172476) | `TakeABathAndShowerNew`, `ATakeABathAndShowerDepthMap` | Las dos; el DepthMap va el primero de la lista |
| Project Cook (3490188370) | `Project_Cook`, `Project_Cook_Pixel_Icon_Pack` | Solo el principal; el pack de iconos es estético |
| Buttstroke (3394044313) | `Buttstroke`, `Buttstroke42.12.3` | Solo el primero. El segundo se llama internamente **"42.12.3 Buttstroke (DO NOT ENABLE)"** |
| Beds Have Blankets (3028528478) | `blankets`, `BeddingCovers-WithPillows`, `BeddingCovers-nopillows` | `blankets`; las otras son *Legacy* |
| Starving Zombies (3396867685) | `StarvingZombies`, `StarvingZombiesWIP` | El principal |

## Nota sobre `[B42.12]`, `[B42.13]`, `[Legacy]`

Al inspeccionar los mods descargados aparecen entradas con esas etiquetas. **No
son variantes a elegir**: son las carpetas versionadas de Build 42, comparten Mod
ID con la principal y el juego escoge sola la que corresponde.

---

# 6. Lo que se aprendió

## Correcciones de Mod ID

Todas salieron de leer los `mod.info` descargados, no las descripciones.

| Mod | ID correcto | Nota |
| --- | --- | --- |
| Run and Reload | `Run and Reload` | **Con espacios.** La descripción del Workshop lo decía bien |
| Right Click To Wear | `DELRAN_CLICK_TO_WEAR` | No estaba documentado |
| Nested Containers | `nm_nested_containers` | |
| Common Sense (descartado) | `BB_CommonSense` | La carpeta se llama `CommonSense` |

## Qué hace que Build 42 indexe un mod

Lo determinante, comprobado por comparación: **B42 solo indexa mods que traen una
carpeta de versión** (`42/`, `42.13/`…).

| Mod | Carpeta de versión | Carga |
| --- | --- | --- |
| Better Sorting | `42/` | sí |
| Has Been Read | `42.13/` | sí |
| Replace Bandage | `42.13/` | sí |
| Tariqs Beards (original) | ninguna | **no** |

Los tres primeros están etiquetados como Build 41 igual que Tariq y funcionan
porque su autor los reempaquetó. Esto es lo que permitió arreglar Tariq's Beards:
añadir una carpeta `42/` con copia de `mod.info` y `media/`, sin tocar contenido.

**Verificado en juego:** las 47 barbas aparecen y se ven correctamente. Los
modelos de 2023 encajan sin problema con el personaje de Build 42, así que el
arreglo era efectivamente solo de empaquetado.

## Hipótesis que se probaron y resultaron falsas

Se anotan para no volver a perder tiempo con ellas.

- *"Build 42 exige prefijo `\` en `Mods=`"*. **Falso.** Varias guías lo repiten
  como "la causa más común de que los mods no carguen". Con `Mods=BB_CommonSense`
  el servidor responde `Mod: loading BB_CommonSense`.
- *"Un mod sin `mod.info` en la raíz no carga"*. **Falso.** Hay 20 así (CleanUI,
  NeatUI_Framework, Neat_Crafting, Reading+…) y cargan.
- *"Las carpetas con espacios en el nombre no cargan"*. **Falso.** Take A Bath
  And Shower New, Map Symbol Size Slider y Spongie Hair las tienen y funcionan.
- *"Es una carrera entre la descarga de Steam y el indexado"*. **Falso.** Fallaban
  igual tras reiniciar.

La causa real siempre estuvo en el `mod.info`: un ID mal leído, una dependencia
declarada solo dentro de `42/`, o un límite de versión.

## Fallos propios que costaron tiempo

- La herramienta `/docker/run.sh mods` leía los ID con `tr -d " \r"`, que borra
  los espacios **dentro** del ID. Convertía `Run and Reload` en `RunandReload` y
  el log solo decía `required mod not found`, que parece un problema del servidor
  y no un dato mal leído.
- Esa misma herramienta buscaba `require=` solo en el `mod.info` de la raíz, así
  que se escapaban las dependencias declaradas dentro de `42/`. Así pasó
  desapercibido `LuaDigitalWatchUI`.

Ambos arreglados. Ahora muestra además `versionMin`/`versionMax`, que es la razón
más silenciosa de que un mod no cargue.
