# 005 — Teletransportes y muros de mapa sin cargar al conducir por ciudad

**Estado:** analizada · causa acotada · **no son los mods** · nada aplicado
**Componente:** estado de mundo cliente↔servidor. No los mods, y no una avería de red medible
**Detectada:** sesión del 12/08/2026 en el servidor vanilla (puerto 16461)

## Síntoma

Reportado por los jugadores:

> A un momento dado de la tarde, yendo en coche y por las ciudades con
> multitudes, los personajes se teletransportaban, o el coche se encontraba con
> un muro de mapa negro, sin cargar.

Dos síntomas distintos con la misma forma: **el cliente y el servidor no están
de acuerdo sobre qué hay en el mundo.**

## La ventana, localizada en el log

La sesión fue del 12-08 16:30 al 13-08 02:03. El servidor rechazó 163 paquetes
por inválidos, y **no están repartidos**:

| Hora | Paquetes rechazados |
| --- | ---: |
| 17h | **143** |
| 20h | 20 |
| resto de la sesión (18, 19, 21, 22, 23, 00, 01h) | **0** |

Al minuto, dos episodios limpios: **17:09–17:12** (108, con pico de 62 en un
solo minuto) y **17:21–17:24** (35). Encaja con "un momento dado de la tarde".

## Qué dice el log exactamente

Hay **dos** firmas, y conviene no confundirlas —esta primera versión del
documento las presentó como emparejadas y **era falso**, ver *Rectificación*—:

```
WARN : Multiplayer  PacketTypes$PacketType.onServerPacket> The packet ZombieHitThumpable is not valid.
LOG  : General      ERROR: IsoThumpable not found on square 10675,9906,0.
```

Un *thumpable* es un objeto destructible: puerta, ventana, barricada, valla. La
primera dice que el servidor descartó un paquete sobre uno de esos objetos; la
segunda, que buscó el objeto de una casilla y no estaba.

Las dos son desincronización de estado de mundo, que es la familia que produce
los dos síntomas: un objeto que el cliente cree que existe y el servidor no es
un obstáculo invisible, y una corrección de posición tras un desacuerdo es un
teletransporte.

### Rectificación: no van juntas

Al minuto, las dos firmas de la hora de las 17h resultan **casi disjuntas**:

| Minuto | Paquetes rechazados | `IsoThumpable not found` |
| --- | ---: | ---: |
| 17:02 | 0 | **28** |
| 17:03 | 0 | 4 |
| 17:04 | 0 | 1 |
| 17:05 | 0 | **62** |
| 17:09 | 2 | 0 |
| 17:10 | **33** | 0 |
| 17:11 | **62** | 0 |
| 17:12 | 11 | 1 |
| 17:21 | 4 | 0 |
| 17:23 | 13 | 0 |
| 17:24 | 18 | 0 |
| 17:45 | 0 | 18 |

**Son dos sucesos distintos en momentos distintos.** Emparejarlos fue un error de
lectura: se vieron cerca en un extracto y se dio por hecho el vínculo sin
comprobar la distribución. Las 186 casillas del total de la sesión tampoco
sostienen "desacuerdo general dentro de los episodios": dentro de V1 hay **una
sola casilla**, y 160 de las 186 aparecen **una única vez** en toda la sesión.

### Y tienen forma distinta

- **`IsoThumpable not found` llega a ráfagas instantáneas.** Las 28 líneas de
  17:02 caen en **6 milisegundos**, entre `17:02:55.487` y `.493`. Eso no es un
  goteo de fallos: es **una operación en bloque** en la que muchos objetos de una
  zona no se resuelven a la vez.
- **Los paquetes rechazados llegan a ritmo de reintento**, uno cada 2-3
  segundos. Es un cliente insistiendo sobre lo mismo.

La ráfaga en bloque encaja mucho mejor con el síntoma tal y como lo describieron
después los jugadores —**"a partir de una zona el mapa no cargaba y todo estaba
negro"**, no un muro contra el que chocar— que la hipótesis original. Una zona
entera cuyos objetos no se resuelven es exactamente eso.

Y llega **95 segundos después de la primera alarma** (17:01:20 → 17:02:55).

## Qué lo desencadenó: hordas, no mods

Las **cuatro** alarmas de toda la sesión están dentro de la ventana:

```
17:01:20  SendAlarm at [ 10633 , 9762 ]
17:12:20  SendAlarm at [ 10890 , 9930 ]
17:16:58  SendAlarm at [ 10875 , 9999 ]
17:37:51  SendAlarm at [ 10613 , 9907 ]
```

Una alarma atrae horda. Coordenadas de zona urbana. Y `IsoThumpable not found`
se concentra igual: **114 de 212 en la hora de las 17h**.

Es decir: alarma → horda → muchos zombis golpeando estructuras a la vez →
ráfaga de paquetes sobre objetos destructibles → el servidor rechaza los que no
le cuadran. **"Ciudades con multitudes" no es el escenario donde se notó el
problema: es el que lo provoca.**

## Descartado: los mods

La comparación que el servidor vanilla hace posible, en tasa por hora y no en
recuentos:

| Sesión | Mods | `IsoThumpable`/h | `ItemPickInfo`/h | Ritmo |
| --- | ---: | ---: | ---: | ---: |
| Producción 10-08 (22,7 h) | 33 | 7,5 | 14,4 | 9,1 f/s |
| Vanilla 11-08 (2,4 h) | **0** | **65,1** | **32,8** | 8,8 f/s |
| Vanilla 11-08 (6,7 h) | **0** | 26,9 | **38,9** | 9,7 f/s |
| Vanilla 12-08 (18 h) | 7 | 11,8 | 13,1 | 9,6 f/s |

**La desincronización es varias veces más frecuente SIN un solo mod que con 33.**
Y el ritmo del servidor es el mismo —9-10 f/s— con 0, con 7 y con 33 mods, así
que los mods tampoco lo están frenando.

Los siete añadidos el 12-08 son además de interfaz pura, con cero `media/scripts`
verificados fichero a fichero: no pueden declarar ni modificar un thumpable.

## Descartado: avería de red

Ninguna de las capas sospechosas muestra un solo fallo durante esa sesión:

| Qué se midió | Resultado |
| --- | --- |
| Fragmentación IP del host (incidencia 003) | `FragOKs` **154**, idéntico al 11-08, con el host arrancado hace 6 días. **Cero fragmentación en toda la sesión.** |
| Socket UDP del contenedor | `InErrors 0`, `RcvbufErrors 0`, `SndbufErrors 0` sobre 3,1 M datagramas |
| Interfaz `tailscale0` | `errors 0`, `dropped 0` en RX y TX |
| Ritmo del servidor durante el episodio | plano, 9,4–10,1 f/s. **No hubo parón.** |
| CPU | sin límite declarado, 12 núcleos, carga 0,14 |

El desajuste de MTU de la incidencia 003 **sigue existiendo** (contenedor 1500,
`tailscale0` 1280) pero **no se disparó**: no hubo ni un datagrama fragmentado.

## Descartado: parón del servidor

Primera lectura, equivocada: en el minuto 17:11 hay 6 muestras por debajo de
5 f/s, y coincide con el pico de paquetes rechazados.

**Es sesgo de detección.** El ritmo solo se puede medir entre dos líneas de log
próximas, y ese minuto tiene 39 muestras precisamente porque está inundado de
avisos. En tasa, 17:11 da 15% de muestras lentas frente a un 3,1% de base — algo
elevado, pero **hay minutos sin ninguna queja que llegan al 29%, 33% y 40%**.
No destaca. La correlación se deshace al normalizar.

## Contraste con el cliente

Se pidió a un agente en la máquina de **uno** de los jugadores que analizara sus
logs sin conocer las conclusiones de aquí, con el encargo explícito de intentar
refutarlas. Su máquina está en la misma zona horaria, así que las horas son
directamente comparables.

**Lo que confirma:**

| | |
| --- | --- |
| Mods | `Lua((MOD:` aparece **0 veces** en toda la sesión del cliente |
| Red | 0 timeouts, 0 `connection lost`, 0 `resend`. Las 3 desconexiones son `message="exiting"`, voluntarias |
| Carga de horda | `removing stale zombie` a **×12 sobre la línea base** del día anterior, con picos en **17:03** y **20:49-20:52** |

El pico de 17:03 cae dentro de la ráfaga de `IsoThumpable` (17:02-17:05), lo que
refuerza el vínculo horda → fallo de resolución de objetos.

**Lo que NO confirma, y es lo importante:**

- **Cero fallos de carga de terreno.** Ni `LoadGridsquare`, ni `ChunkChecksum`,
  ni `getOrCreateGridSquare`, ni excepciones con `chunk` o `cell`. Las únicas
  apariciones de `WorldStreamer` y `CellLoader` son de nivel `LOG`, en `f:0`, y
  **el mismo número exacto en las tres sesiones analizadas**: son líneas de
  arranque, no sucesos de partida.
- **Cero correcciones de posición.** Ni `teleport`, ni `setX/setY`, ni
  `rubber`, ni `position mismatch`, ni `NetworkPlayerAI`.
- **V1 y V2 están limpias en ese cliente**, y son justo donde el servidor
  concentró 143 de sus 163 rechazos. El cliente estaba conectado en ambas.

**Y aporta un episodio que el servidor no vio:**

```
ERROR: General  at IsoDoor.syncIsoObject > expected IsoDoor index is invalid
  { "NetObject": { "objectId":1, "squareX":10664, "squareY":10409, "squareZ":0 } }
```

124 líneas, **una sola casilla**, de 20:50:01 a 20:52:57, exclusivo de esta
sesión (0 en la noche siguiente, 0 en la línea base). Comprobado aquí: **el
servidor no registró jamás la casilla `10664,10409`** —cero coincidencias— y sus
propios rechazos de esa franja cesan a las **20:50:36**, dos minutos antes de que
el cliente deje de insistir.

Es decir: **cliente y servidor están fallando sobre objetos distintos, en
momentos distintos.** El cliente se atasca en una puerta que el servidor no
menciona; el servidor rechaza paquetes sobre casillas que el cliente no menciona.

El agente descartó además, correctamente, el hallazgo de mayor volumen:
`ObjectModDataPacket.parse: object is null`, 1.763 líneas sobre 680 casillas, es
**indistinguible de la línea base** (6,44/min frente a 5,75/min). Es ruido de
fondo permanente de este servidor.

## Causa

**Desincronización de estado de mundo bajo carga de horda, propia de Build 42 en
multijugador**, no de este despliegue ni de los mods.

Con el matiz que impone el cliente: los dos extremos ven el desacuerdo, pero
**no ven el mismo desacuerdo**, y ninguno de los dos registra lo que el jugador
percibió. Es coherente con divergencia general de estado de mundo bajo carga, y
descarta que haya un único objeto o una única causa puntual.

El mecanismo que encaja con los dos síntomas: el servidor simula a ~10 ticks por
segundo. Un coche a velocidad recorre mucha distancia entre dos actualizaciones,
así que el cliente extrapola; cuando llega la corrección, el personaje salta.
Y si en ese momento hay una horda modificando decenas de objetos destructibles,
los dos modelos de mundo divergen más rápido de lo que se reconcilian.

## Lo que NO está probado

- **Que el mapa sin cargar deje rastro en algún sitio.** Ni el servidor ni el
  cliente registran un solo error de carga de celdas. Y no es que no ocurriera:
  **ninguno de los dos instrumenta la entrega de chunks.** Un chunk que nunca
  llega produce ausencia de datos, y la ausencia no genera excepción. Cero
  errores es igual de compatible con "no pasó" que con "pasó y no se registra".
  Este es el agujero principal y no se cierra con estos logs.
- **Que los episodios del log sean los momentos que sufrieron los jugadores.**
  Nadie anotó una hora. Es la misma carencia que ya pedía la
  [incidencia 004](004-sintomas-sin-diagnosticar.md), y ahora se nota más: el
  cliente analizado tiene su episodio a las 20:50 y está limpio en V1 y V2.
- **Que el cliente analizado sea representativo.** Es **uno de varios**. Los 163
  rechazos del servidor son la suma de todos los conectados, así que "V1 limpia
  en este cliente" es perfectamente compatible con que el desacuerdo de esos
  minutos lo generase otro jugador. Para cerrarlo hacen falta los `DebugLog` de
  los demás.
- **Que no fuera un tirón local.** El `DebugLog` del cliente **no instrumenta
  rendimiento**: sin FPS, sin tiempos de fotograma, sin pausas de GC, sin
  memoria. Es la vía por la que esta hipótesis podría caer sin que se vea.
- **Que el jugador analizado fuera en coche durante las ventanas.** No hay traza
  de posición ni de entrada/salida de vehículo.
- **Que ~10 f/s sea bajo.** Es constante en las cuatro sesiones y en producción,
  así que es el ritmo nominal de este servidor, pero no hay referencia externa
  de a cuánto va un B42.20 sano.
- **Que la capa de red no aporte nada.** No hay avería medible, pero tampoco hay
  medición de pérdida extremo a extremo: los contadores limpios del servidor no
  ven lo que se pierda entre el cliente y él. `--net=slirp` con
  `--port-driver=builtin` mete un salto en espacio de usuario que un Docker
  normal no tiene.

## Propuesta

**1. Cerrar el desajuste de MTU** (incidencia 003). No arregla esto —no se
disparó— pero elimina una variable de la siguiente investigación y es una línea.

**2. Pedir una hora, no una prueba.** Que la próxima vez que ocurra alguien
anote la hora aproximada. Es ahora la pieza más valiosa que falta: con dos logs
que señalan momentos distintos, sin una hora real no hay forma de saber cuál de
los dos —si alguno— corresponde a lo que se vivió.

**2 bis. Recoger los logs de los demás clientes.** Con uno solo no se puede
distinguir "este jugador no tuvo el problema" de "el problema fue de otro". Se
les pasa el mismo encargo y se cruzan.

**3. Medir pérdida extremo a extremo**, que es el único hueco real que queda:

```bash
tailscale ping --verbose <nodo-del-jugador>
```

**4. No tocar los mods por esto.** Sería la reacción natural y los datos dicen
lo contrario: sin ellos el fenómeno es más frecuente, no menos.

## Efecto colateral: la incidencia 001 queda refutada

Al comparar sesiones apareció un dato que invalida un diagnóstico anterior. La
[incidencia 001](001-cadaveres-no-looteables.md) atribuía los fallos de
`ItemPickInfo` —los cadáveres que no se pueden registrar— al mod
`StarvingZombies`.

```
Producción, CON StarvingZombies:   14,4 /h
Vanilla, sin NINGÚN mod:           32,8 /h  y  38,9 /h
```

**Más del doble de frecuente sin el mod acusado.** El servidor vanilla nunca ha
tenido `StarvingZombies` y el síntoma está ahí igual. La asociación temporal con
las conversiones a esqueleto que documentaba 001 era real, pero no era la causa:
el fenómeno existe sin ellas.

Retirar `StarvingZombies` —que era la propuesta de 001— **no habría arreglado
nada**. Es justo el caso para el que se levantó el servidor vanilla.
