# 004 — Tres síntomas reportados sin causa identificada

**Estado:** abierta · sin causa · **reproducida sin los mods sospechosos** · no confundir con [001](001-cadaveres-no-looteables.md)

## Síntomas

Reportados por los jugadores junto al de los cadáveres. Los tres tienen la misma
forma: **una acción empieza y nunca termina**, y el personaje se queda en ella.

1. El personaje se **queda atascado al cruzar una puerta**.
2. Se coge un objeto para meterlo al inventario y **se queda trasladándose
   indefinidamente**, sin guardarse.
3. Se pone una venda y **no se aplica nunca**.

## Reproducida el 12/08 en el mundo vanilla (actualización 13/08)

Los jugadores reportan que en la sesión del 12/08 —el mundo vanilla, que lleva
**siete mods de interfaz y ninguno de inventario ni de acciones**— ocurrieron
**los síntomas 1 y 2**, con menos intensidad y no todo el rato. El 3 no se pudo
comprobar.

Consecuencia directa: **los seis mods de inventario de producción quedan
exonerados del síntoma 2** (CleanUI, Proximity Inventory, Nested Containers,
Manage Containers, Better Sorting, Split Items). Eran los sospechosos naturales
por ser los que tocan contenedores, y el síntoma aparece en un mundo que no
lleva ninguno. Es el cuarto caso del patrón que documentan la
[001](001-cadaveres-no-looteables.md), la [002](002-bicycle-api-inexistente.md)
y la [005](005-desincronizacion-al-conducir.md): la familia entera de síntomas
es del **juego base**.

La firma asociada al síntoma 2 apunta igual. Del análisis de logs del cliente
hecho para la 005:

| Sesión | Mods | `ItemContainer dup id` |
| --- | --- | ---: |
| 11/08, vanilla | **0** | 77 casos — 0,21/min |
| 12/08, vanilla | 7 de interfaz | 131 casos — 0,48/min |

Ya estaba ahí **con cero mods**.

### Un candidato nuevo para el síntoma 1

La sesión del 12/08 dejó, en el cliente analizado, un episodio que encaja con
"atascado en una puerta" mejor que el único indicio anterior (aquel
`CloseWindowState` que además era una ventana):

```
ERROR: IsoDoor.syncIsoObject > expected IsoDoor index is invalid
```

**124 líneas sobre una única puerta** (casilla `10664,10409`), de 20:50 a 20:52,
a ritmo de reintento (~0,7/s). Un cliente insistiendo tres minutos sobre una
puerta cuyo estado no consigue sincronizar es, mecánicamente, un personaje que
no consigue terminar de cruzarla. El servidor, además, registró 15 paquetes
`Thump` inconsistentes esa tarde (19:47–22:36), la familia de golpear/forzar
puertas.

**Sin confirmar**: nadie anotó a qué hora se quedó atascado nadie, así que no se
puede afirmar que ese episodio sea uno de los atascos reportados. Es el mejor
candidato disponible, no una causa probada. Si un atasco coincidiera alguna vez
con esta firma, el síntoma 1 quedaría capturado de principio a fin, que es lo
que esta incidencia lleva pidiendo desde que se abrió.

## Lo que se descartó

La primera hipótesis fue que fallaba la cola de acciones temporizadas
(`ISTimedAction`): una excepción dentro de `complete()` dejaría la acción sin
terminar y el personaje bloqueado. Encaja perfectamente con la descripción.

**Refutada con los logs del cliente.** En 4 h 23 min de partida, buscando
explícitamente:

| Término | Excepciones encontradas |
| --- | --- |
| `ISBaseTimedAction`, `ISTimedActionQueue`, `NetTimedAction` | 0 |
| `ISInventoryTransferAction`, `ISGrabItemAction` | 0 |
| `ISApplyBandage`, `ISDisinfect` | 0 |
| `ISOpenCloseDoor`, `ISWalkToTimedAction` | 0 |
| `.complete(` / `.perform(` en traza | 0 |

**Cero.** El cliente no falla en la capa de acciones Lua. Las 33 apariciones de
`TimedAction` en el corpus son `require(...) failed` en frame 0, que es el
patrón normal de recarga de Lua en B42.

## Lo poco que hay por síntoma

| Síntoma | Único indicio | Valoración |
| --- | --- | --- |
| Atascado en puerta | `CloseWindowState.enter` NPE, `window is null` | **1 sola vez, y es una ventana, no una puerta.** Misma familia de estados, nada más |
| Objeto que no se guarda | `ItemContainer.AddItem: container already has id`, 54 casos. Aparece a los 70 min de sesión, crece, y **se resetea al reconectar** | El patrón de degradación encaja bien con la descripción, pero nadie ha capturado el síntoma con su error al lado |
| Venda | `ISDisinfect.lua:70` NPE en el **servidor**, 3 veces. En el cliente, cero | Débil. Además desinfectar no es exactamente vendar |

Ninguno de los tres tiene una traza que capture el síntoma de principio a fin.

## Qué haría falta

**Una marca de tiempo.** Ahora mismo hay ~60.000 líneas de log de cliente y
~10.000 de servidor sin ninguna referencia de dónde mirar. Si alguien anota la
hora aproximada la próxima vez que le ocurra —jugando normal, sin montar ninguna
prueba—, se pueden mirar esos segundos concretos en ambos lados en lugar de
rastrear horas a ciegas.

Con eso se pasaría de "mecanismos plausibles" a evidencia real.

## Nota sobre el volumen de errores

Se confirmó que el cliente registra **muchísimos más errores que el servidor**:

| | Errores | Tiempo | Por hora |
| --- | ---: | ---: | ---: |
| Servidor | 28 | 8 h · 4 jugadores | 3,5 |
| Cliente (solo `ERROR`, en partida) | 753 | 4 h 23 · 1 jugador | 172 |

Unas 49 veces más por hora, y con un jugador frente a cuatro. **Pero sin línea
base no se podía afirmar que fuera anormal**: se desconocía cuántos errores por
hora produce un B42.20 multijugador sano.

**Ese hueco probablemente ya está tapado sin saberlo.** El plan era jugar en el
vanilla limpio y contar errores por hora; pues **esa sesión ya se jugó**: la del
11/08, ~6 h en el vanilla con cero mods, y sus logs siguen en la máquina del
jugador analizado para la 005. Falta solo pedir el recuento total de `ERROR` por
hora de esa sesión, que el informe del cliente no llegó a dar. Ojo: el vanilla
lleva mods desde el 12/08, así que **la línea base es esa sesión archivada, no
una futura**.

Además, servidor y cliente fallan en cosas casi disjuntas: de las firmas del
servidor, solo `ReceiveEatBody` aparece también en el cliente (19 frente a 686).
