# Mods: estado y decisiones

Documento técnico. Para la lista en lenguaje llano que se pasa a los jugadores,
ver [MODS-ADOPTADOS.md](MODS-ADOPTADOS.md).

Punto de partida: 47 candidatos propuestos por el grupo. Los datos salieron de
la API pública del Workshop (`ISteamRemoteStorage/GetPublishedFileDetails`) y de
los `mod.info` realmente descargados, no de guías.

Referencia temporal: **Build 42 estable (42.20) salió el 29/07/2026.**

---

# 1. Lo que está activo ahora

**Corriendo en staging.** Producción está parada y con el mundo borrado, a la
espera de cerrar las votaciones pendientes.

**36 elementos del Workshop · 38 Mod ID.** La diferencia sale de que *Take A
Bath And Shower* aporta dos IDs, y de que *Tariq's Beards* no viene del Workshop
sino de una carpeta local.

## Copia de seguridad de la configuración

`.env` está fuera de git. Si se pierde, o al migrar de máquina, esto es lo que
hay que restaurar.

```
WorkshopItems=3508537032;3437629766;3536052310;3502080466;3490188370;3451167732;2847184718;2998737588;3394044313;3592172476;3147428398;2313387159;2734705913;2544353492;3041733782;3028528478;3461415167;3600401184;3397207461;2650547917;3589548354;3396867685;2463184726;3641697417;3330403100;2944344655;3402513620;3410947298;3446510982;3391902125;3453580134;3399645148;3171167894;2969455858;2447729538;3676456221
```

```
Mods=ATakeABathAndShowerDepthMap;NeatUI_Framework;damnlib;TargetSquareOnLoad;FH;LuaDigitalWatchUI;SpnHair;Tariq's Beards;nm_nested_containers;ProximityInventory;CleanUI;manageContainers;BetterSortCC;Neat_Crafting;Neat_Building_UIOnly;Project_Cook;ModernStatus;KI5trailers;BicycleMod;RC_RealisticColdMod;Run and Reload;StarvingZombies;blankets;TakeABathAndShowerNew;ComfySleeping;Buttstroke;ReplaceBandage;CatseyeInTheDark;EquipClothingWhileMoving;DELRAN_CLICK_TO_WEAR;throw-your-bag-across;Reading+;SplitItems;P4HasBeenRead;improvedhairmenubuild42;SpnHairAPI;MapSymbolSizeSlider;MapSymbolsPlusDeonHand
```

El orden **es** el orden de carga. Los ID van sin prefijo `\` y respetando los
espacios cuando los llevan dentro (`Run and Reload`, `Tariq's Beards`).

## Mod local: Tariq's Beards

No sale del Workshop. Vive en `Zomboid/mods/` dentro del volumen del servidor, y
cada jugador necesita una copia en su propia carpeta `Zomboid/mods`.

Los ficheros de trabajo están en `workbench/`, que **no se versiona**: son assets
de un tercero. El original (`2962908954`) no tiene licencia declarada ni
repositorio, y su autor menciona que parte de los modelos derivan de *Yaki's
Barbershop*.

## Pendiente

**Permiso de Tariq.** Se le ha escrito. Hasta que responda, el port no se publica
y solo circula entre el grupo.

---

# 2. Lo que se descartó

## Solo Build 41 (13)

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

---

# 3. Dependencias que hubo que añadir

Ninguna estaba entre los 47 candidatos. Sin ellas, su mod no carga.

| Workshop ID | Mod ID | Lo exige |
| --- | --- | --- |
| 3508537032 | `NeatUI_Framework` | CleanUI, Neat Building, Neat Crafting, Project Cook, Modern Status |
| 3171167894 | `damnlib` | Trailers! |
| 2969455858 | `TargetSquareOnLoad` | Beds Have Blankets |
| 2447729538 | `FH` (Fluffy Hair) | Spongie's Hair |
| 3676456221 | `LuaDigitalWatchUI` | Realistic Temperature |

---

# 4. Reglas de orden de carga

Declaradas por los autores. Todas respetadas salvo la última.

- `ATakeABathAndShowerDepthMap` el primero de toda la lista.
- `NeatUI_Framework` antes que CleanUI, Neat Crafting, Neat Building, Project
  Cook y Modern Status.
- `nm_nested_containers` antes que `ProximityInventory`, o no detecta los
  contenedores anidados.
- `damnlib` antes que `KI5trailers`.
- `TargetSquareOnLoad` antes que `blankets`; `FH` antes que `SpnHair`;
  `LuaDigitalWatchUI` antes que `RC_RealisticColdMod`.
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
