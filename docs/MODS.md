# Mods

Procedimiento para añadir mods sin arriesgar los guardados. Todo lo que hay
aquí está comprobado sobre la 42.20 instalada, no copiado de guías.

---

## Lo que se verificó empíricamente

**El prefijo `\` en `Mods=` es un mito.** Varias guías afirman que Build 42
exige escribir `Mods=\ModID`. En la 42.20 no: con `Mods=BB_CommonSense` el
servidor responde `LOG: Mod > loading BB_CommonSense`. El ID va tal cual.

**El nombre de la carpeta no es el Mod ID.** El mod "Common Sense" se descarga
en `mods/CommonSense/` pero su ID real es `BB_CommonSense`. Poner el nombre de
la carpeta produce un mod que sencillamente no carga, sin ningún error claro
que lo explique. **Los IDs se sacan siempre de los `mod.info` descargados**, con:

```bash
docker compose exec pz /docker/run.sh mods
```

**Estructura de mods en Build 42.** Los mods portados traen carpetas versionadas:

```
<workshop_id>/mods/<Carpeta>/
    mod.info        <- el de compatibilidad general
    common/         <- recursos compartidos entre versiones
    42.0/           <- contenido especifico de Build 42
        mod.info
    media/
```

Un mod sin carpeta `42.x` es casi con seguridad de Build 41 y no va a funcionar.
Es la primera comprobación al valorar un candidato.

**Un mod incompatible tumba el servidor, pero no corrompe el mundo.** Probado:
Common Sense original (`2875848298`) falla en 42.20 con
`require("recipecode") failed` — ese módulo Lua desapareció en Build 42. El
error de script encadena en `WorldDictionaryException` y el servidor termina
durante la carga del mundo. Al quitar el mod, staging volvió a arrancar con el
mundo intacto: 57 ficheros y la base de datos de jugadores completa.

Que ese caso sea benigno **no generaliza**. Un mod que arranca bien y luego
escribe datos mal formados en contenedores o celdas sí puede dejar daño
persistente. Por eso el procedimiento es el que es.

---

## Procedimiento

**Regla: de uno en uno, y siempre primero en staging.** Añadir cinco mods a la
vez y que el mundo falle no te dice cuál fue.

### 1. Investigación previa — antes de descargar nada

Ningún mod se prueba a ciegas. Para cada candidato se revisa:

| Qué | Dónde | Qué descarta |
| --- | --- | --- |
| **Versión** | ¿La página dice **42 stable** o **42.20** explícitamente? "Build 42" a secas puede referirse a una unstable antigua | Mods de B41 disfrazados |
| **Fecha** | Última actualización posterior al 29/07/2026 | Ports abandonados a medias |
| **Comentarios** | Últimas páginas de comentarios del Workshop: es donde aparecen los bugs reales antes que en ningún otro sitio | Mods que "funcionan" pero rompen cosas |
| **Multijugador** | ¿Dice ser **MP friendly**? Muchos son solo para un jugador | Mods que fallan solo en servidor |
| **Dependencias** | Campo `require=` del `mod.info` **y** la descripción del Workshop | Fallos de carga por falta de una librería |
| **Incompatibilidades** | Mods que el autor declara incompatibles, y los que la comunidad reporta como conflictivos en los comentarios | Combinaciones que rompen el mundo |
| **Solapamiento** | ¿Hace lo mismo que otro que ya tenemos, o toca las mismas mecánicas? | Conflictos silenciosos y trabajo duplicado |
| **Orden de carga** | Dónde encaja según el bloque de más abajo | Sobrescrituras inesperadas |

**Dependencias e incompatibilidades son cosas distintas, y ninguna es lo mismo
que el solapamiento.** Dos mods pueden no compartir ni una mecánica y aun así
pisarse. Y un mod puede solapar con otro sin que ninguno lo declare.

Las dependencias son en parte automáticas: `/docker/run.sh mods` lee el campo
`require=` de cada `mod.info` descargado y avisa de qué debe ir antes en
`Mods=`. **Pero muchos autores no lo rellenan** — Common Sense, por ejemplo, no
declara nada. Que salga vacío no significa que el mod no dependa de nada: hay
que leer la descripción del Workshop igualmente.

Las incompatibilidades casi nunca están en el `mod.info`. Viven en la
descripción ("no usar junto a X") y sobre todo en los comentarios, que es donde
la gente reporta las combinaciones que le reventaron la partida.

Con una lista larga se investiga **entera** antes de tocar nada, y luego se
prueba agrupando: primero todos los que la comunidad o el Workshop confirmen
que funcionan, después los dudosos. Los que se sepa rotos o solapados se
descartan antes de gastar tiempo en ellos.

Aviso: las guías y los resultados de búsqueda sobre compatibilidad con B42 son
**poco fiables**. Common Sense (`2875848298`) aparecía como compatible con
42.20 en varias fuentes y tumba el servidor. La investigación previa sirve para
priorizar y descartar, no para dar nada por bueno: la única prueba que cuenta
es levantarlo en staging.

### 2. Probar en staging

```bash
# En .env, solo la lista de staging (produccion no se toca):
STAGING_WORKSHOP_ITEMS=2875848298
STAGING_MODS=

./scripts/stage.sh                      # copia el mundo real y arranca
```

Con `STAGING_MODS` vacío, Steam descarga el mod pero el servidor no lo carga.
Eso permite sacar el ID real:

```bash
docker compose --profile staging exec pz-staging /docker/run.sh mods
```

Luego se pone el ID en `STAGING_MODS` y se recrea:

```bash
docker compose --profile staging up -d --force-recreate pz-staging
docker compose --profile staging logs -f pz-staging
```

### 3. Qué mirar en el log

```bash
# Que el servidor reconoce el mod:
docker compose --profile staging logs pz-staging | grep -i "loading "

# Errores de script, que son los que impiden cargar el mundo:
docker compose --profile staging logs pz-staging | grep -iE "script load error|require.*failed|WorldDictionaryException"
```

Si aparece `*** SERVER STARTED ****`, el mod al menos carga.

### 4. Comprobar dentro del juego

Conectarse a `localhost:16361` y verificar sobre la copia del mundo real:

- El personaje sigue existiendo, con su inventario.
- Las construcciones y los contenedores de la base están intactos.
- Se puede recorrer zona ya explorada sin celdas rotas.
- Lo que el mod promete, funciona.

### 5. Pasar a producción

```bash
./scripts/backup.sh antes-de-<nombre-del-mod>
```

Se mueven los IDs de `STAGING_*` a `PZ_WORKSHOP_ITEMS` / `PZ_MODS` en `.env`,
se vacían los de staging, y:

```bash
docker compose up -d --force-recreate pz
```

Commitear el cambio explicando qué mod, qué ID y por qué.

---

## Cómo llegan los mods a los jugadores

**Solos.** Al conectar al servidor, el cliente descarga del Workshop los mods
que le falten y se entra de inmediato. Comprobado en juego. No hay que
suscribirse a nada por adelantado ni reiniciar el juego después.

La excepción son los **mods locales**, los que no vienen del Workshop. Esos el
cliente no los puede descargar solo, así que cada jugador necesita una copia en
su carpeta `Zomboid/mods`. Ver el apartado correspondiente en
[MODS-ADOPTADOS.md](MODS-ADOPTADOS.md).

---

## Orden de carga

`Mods=` se evalúa en orden y los últimos sobrescriben a los anteriores:

1. Librerías y frameworks (dependencias de otros mods)
2. Mods de mapa
3. Contenido: objetos, armas, vehículos
4. Interfaz y calidad de vida

---

## Quitar un mod

Más delicado que añadirlo: los objetos que el mod introdujo desaparecen de los
inventarios y contenedores donde estuvieran, y las construcciones hechas con
sus piezas pueden quedar rotas.

Se prueba en staging igual que una adición. Backup obligatorio antes.

---

## Mapas: caso aparte

Añadir un mod de mapa a un mundo ya explorado es de las operaciones más
delicadas que existen: las celdas ya generadas no se regeneran, y el mod puede
querer colocar terreno donde ya hay datos.

**Se decide con el mundo recién creado, o no se hace.** Si entra un mapa, va
en `Mods=` antes que el resto de contenido, y hay que añadir su región a
`config/spawnregions.lua`.

---

## Congelar mods en producción

El servidor recomprueba los `WorkshopItems=` en cada arranque, así que una
actualización del autor entra sin avisar y puede romper el mundo un martes
cualquiera.

Cuando la lista esté estable, se puede copiar los mods ya validados a
`Zomboid/mods/` y quitarlos de `WorkshopItems=`, dejándolos inmunes a
actualizaciones no supervisadas. Es el mismo principio que aplicamos a la
versión del juego: que nada cambie sin que alguien lo decida.

---

## Diagnóstico

| Síntoma | Causa habitual |
| --- | --- |
| El servidor cae al cargar el mundo | Error de script de un mod. Buscar `require.*failed` en el log |
| El mod no hace nada | ID incorrecto en `Mods=`. Sacarlo de `/docker/run.sh mods` |
| No descarga del Workshop | Caché de Steam corrupta: parar, borrar `steamapps/workshop/`, arrancar |
| Los jugadores no pueden entrar | No están suscritos, o su versión del mod no coincide |
| Funcionaba y hoy no | El autor lo actualizó. Ver "Congelar mods" |
