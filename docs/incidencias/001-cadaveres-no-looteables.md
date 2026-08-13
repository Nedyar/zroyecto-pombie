# 001 — Los cadáveres no aparecen como contenedor y no se pueden registrar

**Estado:** **DIAGNÓSTICO REFUTADO** el 13/08/2026 · no retirar nada · síntoma abierto
**Componente:** ~~mod `StarvingZombies`~~ → sin identificar
**Detectada:** 11/08/2026, primera sesión con 4 jugadores

> **Lee esto antes que nada.** La causa que propone este documento es falsa. El
> síntoma sigue abierto, pero **no lo produce `StarvingZombies`** y retirarlo no
> habría arreglado nada. El desenlace está al final, en *La prueba en vanilla*.
> El resto se conserva sin tocar porque el razonamiento es correcto hasta donde
> llegaban los datos, y porque el error de método merece quedar a la vista.

## Síntoma

Descrito por los jugadores:

> Al matar un zombi, el cadáver se queda en el suelo, **parece que hace un
> movimiento con la cabeza**, y en el menú donde eliges entre suelo, muebles,
> superficies, etc., **no aparece la opción del cadáver**.

Importante: **no es que el cadáver esté vacío**, es que no se puede seleccionar
para registrarlo. Es un problema distinto del de que el loot se destruya.

## Evidencia

### En el log del servidor

```
ItemPickInfo -> cannot get ID for container: inventorymale      ← 326 veces
ItemPickInfo -> cannot get ID for container: inventoryfemale
```

`inventorymale` / `inventoryfemale` son los contenedores de cadáver. El mensaje
dice que el servidor no consigue asignarles identificador de red. Sin ID, el
cliente no puede referenciarlos, y por eso el cadáver no sale en la lista de
contenedores de la ventana de saqueo.

En la misma ventana, el mod convirtió cadáveres en esqueletos **167 veces**:

```
Lua((MOD:Starving Zombies)).createSkeleton> Spawning new Male Zed, Dressed in
No Outfit, isFallOnFront:false, isFakeDead:false, ...
```

### Asociación temporal

Los fallos de contenedor se concentran alrededor de las conversiones:

| | |
| --- | --- |
| Ventana analizada | 186.516 frames |
| Cubierto por ventanas de ±300 frames alrededor de una conversión | 28% |
| Fallos de contenedor que caen dentro de esas ventanas | **40%** |

Por azar se esperaría 28%. Hay exceso, así que la asociación es real. **Pero el
60% restante no cae cerca de ninguna conversión**, así que hay otra fuente que
no está identificada.

### Mecanismo, leído en el código del mod

`42.15/media/lua/server/RYUKU_StarvingZombies_Server.lua`, función
`createSkeleton`:

```lua
local zombie = addZombiesInOutfit(x, y, z, 1, nil, 0,
    false,                      -- crawler
    isoDeadBody:isFallOnFront(),
    false,                      -- fakeDead
    true,                       -- knockedDown   <-- zombi VIVO derribado
    false, false,
    1)                          -- setHealth = 1
zombie:setSkeleton(true)
zombie:getInventory():removeAllItems()

body = IsoDeadBody.new(zombie, false)      -- cadaver NUEVO
body:setContainer(isoDeadBody:getContainer())   -- contenedor del cadaver VIEJO
zombie:removeFromWorld()
sendCorpse(body)
removeBody(isoDeadBody)                     -- y se destruye el viejo
```

Dos consecuencias:

1. **El contenedor se re-parenta y su dueño original se destruye.** El ID de red
   de un contenedor se deriva de su objeto contenedor; si ese objeto ya no
   existe, no hay ID que dar. Encaja exactamente con `cannot get ID`.

2. **El "movimiento de cabeza" tiene explicación.** El mod no transforma el
   cadáver: genera un **zombi vivo derribado con 1 de vida**, lo marca como
   esqueleto y lo retira. Si esa secuencia queda a medias, en el suelo queda una
   entidad viva —que se mueve— y que no es un `IsoDeadBody`, así que no ofrece
   contenedor.

## Lo que NO está probado

- **El síntoma no está capturado de principio a fin.** No hay ninguna traza que
  una "el jugador intentó registrar este cadáver" con "falló". La correlación es
  del analista, no del log.
- **El 60% de los fallos de contenedor no se explica** con este mod. Hay una
  segunda fuente sin identificar.
- **No hay línea base.** Se desconoce si un B42.20 multijugador sin mods produce
  también `cannot get ID for container`, y en qué cantidad.
- No se ha comprobado si el mod se comporta igual en un solo jugador.

## Comprobacion previa que ahora si es posible

Desde que existe el **servidor vanilla** (mismo mapa, misma semilla, mismos
ajustes, cero mods, puerto 16461) hay una forma de acotar esto sin retirar nada
de produccion: reproducir el sintoma alli.

- Si en vanilla los cadaveres **tambien** fallan -> no es de los mods, y esta
  incidencia esta mal enfocada.
- Si en vanilla **funcionan** -> es de los mods, y la propuesta de abajo pasa de
  hipotesis razonada a candidata con respaldo.

Es mas barato que un ciclo de retirada, y no toca produccion.

## Propuesta ~~(anulada)~~

~~Retirar `StarvingZombies` (`3396867685`)~~ siguiendo el procedimiento de
[MODS.md](../MODS.md). Es el único candidato con mecanismo leído en código,
asociación estadística y correspondencia con la descripción de los jugadores,
incluido el detalle del movimiento.

~~Requiere reinicio. El mundo es reciente y ningún otro mod depende de este.~~

**No se aplica. Ver abajo.**

---

## La prueba en vanilla: el diagnóstico era falso

La sección anterior planteaba la comprobación y su criterio de decisión. Se hizo
el 13/08/2026, sobre los logs del servidor vanilla, y salió el resultado que
invalidaba la hipótesis.

`ItemPickInfo -> cannot get ID for container`, en tasa por hora:

| Servidor | `StarvingZombies` | Fallos/h |
| --- | --- | ---: |
| Producción, 10-08, 22,7 h | **sí** | 14,4 |
| Vanilla, 11-08, 2,4 h | **no** | **32,8** |
| Vanilla, 11-08, 6,7 h | **no** | **38,9** |
| Vanilla, 12-08, 18 h | no | 13,1 |

**Más del doble de frecuente sin el mod acusado que con él.** El servidor
vanilla no ha tenido `StarvingZombies` ni un solo minuto, y el síntoma está ahí
igual. La línea base que este documento echaba en falta ya existe, y dice que el
fenómeno es del juego base.

### Qué falló en el razonamiento

Nada de lo escrito arriba es incorrecto en sí: el mecanismo del código está bien
leído, la asociación temporal se calculó contra un modelo nulo y el exceso sobre
el 28% esperado era real. El error fue de **inferencia**: una asociación real
entre dos cosas no significa que una cause la otra, y el propio documento
señalaba que **el 60% de los fallos no caía cerca de ninguna conversión**. Ese
60% no era ruido pendiente de explicar: era la señal de que había una causa
mayor, y resultó ser la única.

La lección, que vale para la siguiente: **cuando tu hipótesis explica la minoría
de los casos, es candidata a ser un efecto colateral, no la causa.**

### Qué queda

El síntoma sigue abierto y sin causa. La diferencia es que ahora se sabe que hay
que buscarla en el juego base y no en la lista de mods. Ver
[005](005-desincronizacion-al-conducir.md), que documenta otra firma de
desincronización de estado de mundo con el mismo perfil: presente en todas las
sesiones, y **más frecuente sin mods**.

**Criterio de éxito:** que `cannot get ID for container` baje sustancialmente.
Si baja pero no desaparece, queda confirmada la segunda fuente y el log queda
mucho más limpio para buscarla.

## Efecto secundario, distinto de esta incidencia

Con la configuración actual el mod destruye loot **por diseño**:

```
AllowWornAttachedItems = false     -- la ropa y lo equipado se pierde siempre
ItemDestroyChance      = 50        -- cada objeto tiene 50% de destruirse
```

Eso explica cadáveres *vacíos*, que es otra queja posible y no la de este issue.
Si se decidiera conservar el mod, ajustar esos valores en
`config/SandboxVars.lua` es independiente de todo lo anterior.
