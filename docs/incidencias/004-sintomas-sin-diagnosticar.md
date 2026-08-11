# 004 — Tres síntomas reportados sin causa identificada

**Estado:** abierta · sin causa · **no confundir con [001](001-cadaveres-no-looteables.md)**

## Síntomas

Reportados por los jugadores junto al de los cadáveres. Los tres tienen la misma
forma: **una acción empieza y nunca termina**, y el personaje se queda en ella.

1. El personaje se **queda atascado al cruzar una puerta**.
2. Se coge un objeto para meterlo al inventario y **se queda trasladándose
   indefinidamente**, sin guardarse.
3. Se pone una venda y **no se aplica nunca**.

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

**Ese hueco ya tiene cómo taparse.** Existe el servidor vanilla (puerto 16461):
mismo mapa, misma semilla, mismos ajustes y cero mods. Jugando un rato allí y
contando errores por hora se obtiene la referencia que falta, y con ella estas
cifras pasan a significar algo. Mientras no se haga, siguen sin significar nada.

Además, servidor y cliente fallan en cosas casi disjuntas: de las firmas del
servidor, solo `ReceiveEatBody` aparece también en el cliente (19 frente a 686).
