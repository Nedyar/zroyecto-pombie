# 001 — Los cadáveres no aparecen como contenedor y no se pueden registrar

**Estado:** diagnosticada · propuesta lista · **nada aplicado todavía**
**Componente:** mod `StarvingZombies` (Workshop `3396867685`)
**Detectada:** 11/08/2026, primera sesión con 4 jugadores

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

## Propuesta

Retirar `StarvingZombies` (`3396867685`) siguiendo el procedimiento de
[MODS.md](../MODS.md). Es el único candidato con mecanismo leído en código,
asociación estadística y correspondencia con la descripción de los jugadores,
incluido el detalle del movimiento.

Requiere reinicio. El mundo es reciente y ningún otro mod depende de este.

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
