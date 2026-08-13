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

Las dos firmas van emparejadas:

```
WARN : Multiplayer  PacketTypes$PacketType.onServerPacket> The packet ZombieHitThumpable is not valid.
LOG  : General      ERROR: IsoThumpable not found on square 10675,9906,0.
```

Un *thumpable* es un objeto destructible: puerta, ventana, barricada, valla. El
cliente le dice al servidor "un zombi ha golpeado el objeto de esta casilla" y
**el servidor no tiene ese objeto ahí**, así que descarta el paquete.

Eso es desincronización de estado de mundo, y es la misma familia que produce
los dos síntomas: un objeto que el cliente cree que existe y el servidor no es,
literalmente, un obstáculo invisible; y una corrección de posición tras un
desacuerdo es, literalmente, un teletransporte.

**No es un objeto roto que se repite**: son **186 casillas distintas**. El
desacuerdo es general, no un caso puntual.

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

## Causa

**Desincronización de estado de mundo bajo carga de horda, propia de Build 42 en
multijugador**, no de este despliegue ni de los mods.

El mecanismo que encaja con los dos síntomas: el servidor simula a ~10 ticks por
segundo. Un coche a velocidad recorre mucha distancia entre dos actualizaciones,
así que el cliente extrapola; cuando llega la corrección, el personaje salta.
Y si en ese momento hay una horda modificando decenas de objetos destructibles,
los dos modelos de mundo divergen más rápido de lo que se reconcilian.

## Lo que NO está probado

- **Que el muro de mapa negro tenga que ver con esto.** El servidor **no registra
  ni un error de carga de celdas** en toda la sesión: solo dos
  `CellLoader.LoadCellBinaryChunk start`. Es un síntoma que solo deja rastro en
  el cliente, y esos logs están en las máquinas de los jugadores, no aquí.
- **Que los episodios del log sean los momentos que sufrieron los jugadores.**
  La ventana coincide con "por la tarde", pero nadie anotó una hora. Es la misma
  carencia que ya pedía la [incidencia 004](004-sintomas-sin-diagnosticar.md).
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
anote la hora aproximada. Con eso se cruzan los segundos concretos del log del
servidor con el del cliente, en vez de rastrear 7.000 líneas a ciegas.

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
