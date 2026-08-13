# 002 — Bicycle! llama a una API que Build 42.20 eliminó

**Estado:** defecto confirmado · **impacto sin determinar** · nada aplicado
**Componente:** mod `BicycleMod` (Workshop `3461415167`)

## Síntoma

Ninguno reportado por los jugadores. Se encontró analizando logs: el mod lanza
un error **en cada conexión al servidor**, 5 de 5 registradas.

## Evidencia

En el log del cliente, al entrar en partida:

```
attempted index: CreateItem of non-table: null
  Lua((MOD:[B42.15+/MP] Bicycle!)).RegisterBicycleItems(InventoryItemFactory.lua:11)
  → zombie.gameStates.IngameState.enter(IngameState.java:774)
```

El código, en la carpeta de versión activa (`42.13`, la mayor que no supera
42.20):

```lua
require("Items/InventoryItemFactory")

local function RegisterBicycleItems()
    local itemNames = { "Bicycle.Bicycle", "Bicycle.Bicycle_RedStreet" }
    for _, itemName in ipairs(itemNames) do
        if InventoryItemFactory.CreateItem(itemName) then   -- linea 11
```

**`InventoryItemFactory` no existe en el juego base 42.20.** Comprobado
buscándolo en `/opt/pz-server/media/lua`: no hay ningún fichero con ese nombre.
Por eso el error no es "no se pudo crear el ítem" sino que el objeto sobre el
que se invoca es nulo.

El desajuste de versión se ve en el propio mod: sus carpetas son `42.12` y
`42.13`, y el servidor va por 42.20.

## Hipótesis sin confirmar

El mod trae su propio sistema de sincronización de objetos movibles
(`BicycleSyncServer.lua`, y **7 ficheros usan `transmitModData()`**), que es
justo lo que genera los paquetes `ObjectModDataPacket`.

En el cliente, el error más numeroso del corpus es:

```
ObjectModDataPacket.parse: object is null      ← 4.541 veces
  ({ "MovingObject": { "objectType": 1, "objectId": 1, ... } })
```

Todos con `objectType: 1` e identificadores del 1 al 4: **son cuatro objetos**
generando 4.541 líneas durante horas.

Es tentador unir ambas cosas —el registro de ítems falla, luego el cliente no
puede instanciar las bicicletas que el servidor le sincroniza— **pero no está
demostrado**. El log no nombra al emisor de esos paquetes, y `KI5trailers`
también crea objetos movibles.

### La hipótesis se debilita mucho (13/08/2026)

El análisis de logs de cliente para la [005](005-desincronizacion-al-conducir.md)
midió esa misma firma en el **servidor vanilla**, que el 11/08 no tenía **ni un
solo mod** —ni `BicycleMod`, ni `KI5trailers`, ni ningún otro—:

```
ObjectModDataPacket.parse: object is null    2.099 lineas    5,75/min
```

**La firma existe en abundancia sin Bicycle! y sin ningún mod que cree objetos
movibles.** No puede ser exclusiva de ellos, así que la hipótesis de arriba deja
de sostenerse como explicación completa.

Lo que sí queda en pie, con la reserva de que son sesiones distintas y de
distinta duración: en producción esa firma va **unas 3 veces más rápido** que en
el vanilla limpio. Puede que los mods de objetos movibles aporten su parte, pero
**la mayor parte del fenómeno es del juego base**.

Consecuencia práctica: dejar de usar esas 4.541 líneas como argumento para tocar
`BicycleMod`. Es el mismo patrón que tumbó la [001](001-cadaveres-no-looteables.md)
—una firma llamativa atribuida a un mod, que luego resulta más frecuente sin él—
y conviene reconocerlo antes de repetirlo por tercera vez.

## Lo que NO está probado

- Que el fallo de registro tenga **alguna** consecuencia observable. Se sabe que
  aborta; no se sabe qué queda sin registrar ni si algo depende de ello.
- Que Bicycle! sea el emisor de los `ObjectModDataPacket` huérfanos.
- Ningún jugador ha reportado problemas con la bicicleta. El
  [checklist](../CHECKLIST-MODS.md) la da por verificada, cesta incluida.

## Propuesta

**No retirarlo por ahora.** Es un defecto real pero sin impacto demostrado, y
los jugadores lo usan sin quejarse.

Lo razonable es comprobar si el autor ha publicado versión para 42.20 y, si la
hay, actualizar. Si no, dejarlo anotado y revisarlo cuando se aborde
[003](003-mtu-tailscale-fragmentacion.md) o el resto de la desincronización de
objetos, donde sí podría ser relevante.
