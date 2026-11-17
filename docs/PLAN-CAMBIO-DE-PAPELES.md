# Plan: que "producción" vuelva a ser el mundo en el que se juega

Redactado el 16/11/2026 y corregido el 17/11 tras dos revisiones
adversariales. Cada paso que cambia algo espera el sí del administrador.

**Estado:** pasos 0 y 2 hechos. Paso 1 en la rama
`refactor/produccion-es-el-mundo-de-juego`, todavía fuera del directorio vivo
del proyecto. Pasos 3 a 6 pendientes.

## Objetivo

Desde el 13/08 los papeles están invertidos:

| | Servicio | Volúmenes | Qué es de verdad |
| --- | --- | --- | --- |
| "Producción" | `pz` (`pombie-pz`, no existe ahora) | `pz-*-vanilla` | El mundo congelado el 16/08, en 42.20.3. Nadie juega |
| "Staging" | `pz-staging` (`pombie-staging`) | `pz-*-staging` | **El mundo en el que se juega**, 42.20.4, 36 mods |

Al terminar:

| | Servicio | Volúmenes | Qué es |
| --- | --- | --- | --- |
| Producción | `pz` (`pombie-pz`) | `pz-*-staging` (adoptados, sin mover un byte) | El mundo en el que se juega |
| Staging | `pz-staging` (`pombie-staging`) | `pz-*-ensayo` (nuevos) | Copia desechable para probar mods |
| Archivo | — | tarball verificado + forma de recuperar el motor 42.20.3 | El mundo del 16/08 |

Es la técnica del 13/08 (DECISIONES 6bis): **reasignar volúmenes en el
compose, no mover partidas**.

## Por qué: lo que provoca la inversión

Comprobado en el código el 16-17/11:

1. **`stage.sh` borraba el mundo de juego en sus dos modos**, no solo con
   `--down`: el modo normal quita `pombie-staging`, borra
   `pz-data-staging` y carga encima el mundo de agosto.
2. **Los scripts que trabajan sobre `pz` operan sobre el mundo de agosto sin
   dar error**: `backup`, `rcon`, `restore`, `update-server`, `bootstrap`,
   `install-local-mods` (que además apunta a `pz-data`, un volumen que no
   existe) y **`capture-ini`/`capture-sandbox`**. Estos dos son los peores:
   traen al repo los ajustes de agosto, y el render se los aplica a la
   partida buena en el siguiente arranque.
3. **La guía de migración** (OPERACIONES) se llevaría el mundo de agosto.
4. **El mundo de juego tiene la guarda de versión desactivada**
   (`ALLOW_BUILD_CHANGE: "true"` en `pz-staging`): es otra herencia de su vida
   como ensayo, como el `restart: "no"` del 20/08.
5. **No hay dónde probar un mod** antes de meterlo en la partida.

## Decisiones del administrador

| # | Pregunta | Decisión |
| --- | --- | --- |
| D1 | Puerto del mundo bueno | **16461/16462**, como hoy: jugadores y ACL sin cambios |
| D2 | Reinicio del staging nuevo | **`"no"`**: desechable |
| D3 | Reconstruir la imagen (aviso `guard_network`) | **Antes, en otra parada**. HECHO el 17/11: selftests en verde dentro de la imagen, servidor recreado y sano |
| D4 | Volúmenes viejos `pz-*-vanilla` (8,3 GB) | **Conservarlos** hasta resolver el paso 2b |
| D5 | ¿Conservar el mundo de agosto listo para arrancar? | **No** (17/11): el mundo de juego pasa a producción y basta con el archivo |
| D6 | **Tariq's Beards** (mod local) no está instalado en el mundo de juego: sus ficheros solo están en `pz-data-vanilla/mods`. El servidor lo pide (`required mod not found`) y no lo carga, seguramente desde el 16/08 | **Se queda como está** (17/11) |

D1-D4 se tomaron con la recomendación del plan; D5 y D6, por indicación
expresa del administrador el 17/11.

## Paso 0 — HECHO (16/11): bloquear lo que hoy hace daño

- `stage.sh` aborta en todos sus modos antes de hacer nada (comprobado con
  `""`, `--down`, `--keep`, `--from pz` y un argumento inválido).
- `refuse_frozen_pz` en `scripts/_common.sh`: los 8 scripts que operan sobre
  `pz` se niegan, y explican el comando equivalente para el mundo de juego.
- Los dos bloqueos son provisionales y se quitan en el paso 4.

## Paso 1 — EN BORRADOR: preparar el cambio

**Dónde:** los borradores viven fuera del directorio del proyecto, en el
espacio temporal de la sesión. **El compose nuevo NO entra en el directorio
vivo hasta la parada.** El compose fija `name: zroyecto-pombie`, así que
cualquier `docker compose up` con el fichero nuevo, desde aquí o desde otro
checkout, actuaría sobre el proyecto vivo: un `up -d` crearía `pombie-pz`
sobre `pz-data-staging` con `pombie-staging` todavía en marcha. Serían dos
servidores sobre el mismo mundo. Hasta el paso 4 la rama solo se valida con
`docker compose --project-directory . -f <borrador> config -q`.

Cambios, uno por uno:

- **`docker-compose.yml`** (borrador validado):
  - `pz` adopta `pz-game-staging` y `pz-data-staging`, con un comentario que
    explica por qué el nombre miente.
  - Puertos de `pz` 1:1 con `PZ_PORT`/`PZ_UDP_PORT`. El mapeo actual
    (`HOST_GAME_PORT:16261`) rompe la conexión si el puerto de fuera no es
    16261.
  - `pz-staging`: volúmenes `pz-*-ensayo`, `restart: "no"` y
    **`BACKUP_NAME_PREFIX: "ensayo"`**. No puede ser `staging`: las copias
    `staging-*` son la historia del mundo de juego (las 20 `periodic` y 20
    `pre-mods` buenas) y la rotación va por prefijo y etiqueta. Un ensayo que
    firmase `staging-*` las iría borrando, y un procedimiento como "restaurar
    el último `*-pre-mods`" podría coger una copia del ensayo y restaurarla
    sobre el mundo bueno.
  - `pz` firma sus copias como **`produccion-*`** (`BACKUP_NAME_PREFIX`):
    sin él saldría `pz-pombie-vanilla-*`, el mismo prefijo que las copias de
    agosto.
  - `pz-staging` con **`mem_limit: 4g` y heap 3g**, para que el ensayo quepa
    junto a producción sin arriesgar un OOM en el JVM bueno.
  - Fuera los volúmenes `pz-game`/`pz-data`, que no existen desde el 13/08.
- **`.env`** (script probado con un `.env` inventado; copia los valores clave
  a clave sin imprimirlos):
  - `PZ_WORKSHOP_ITEMS`/`PZ_MODS` ← `STAGING_*`, es decir, 34/36 elementos.
  - `PZ_PORT`/`PZ_UDP_PORT` ← 16461/16462.
  - `STAGING_GAME_PORT`/`_2` ← 16361/16362.
  - `STAGING_*` vacíos, para que staging replique producción.
  - Fuera `HOST_GAME_PORT`/`_2`.
  - Sin tocar: **puerto RCON del host**. Producción usa 27015 y staging 27115,
    así que el mundo de juego pasa de 27115 a 27015. Solo importa a quien lo
    use desde fuera del contenedor (¿el monitor de disponibilidad?).
- **`scripts/stage.sh`** (borrador probado sin efectos):
  - Quitar el bloque DESACTIVADO.
  - El volumen que borra **sale del compose**, el mismo donde escribirá la
    restauración, en vez de un nombre escrito a mano.
  - Antes de tocar nada, en todos los modos, y otra vez justo antes del
    `volume rm`, aborta si:
    - `pz` y `pz-staging` montan el mismo volumen;
    - algún contenedor que no sea `pombie-staging` lo monta (también parado);
    - `pombie-staging` monta otro;
    - el volumen no es `*_pz-data-ensayo`. Este último es el control
      semántico: los otros no saben cuál de los dos mundos es el bueno, y con
      los papeles invertidos habrían dado por bueno borrar el de juego.
  - Probado contra el compose actual, el borrador en el estado de hoy y un
    compose roto: aborta en los tres. El caso bueno solo se puede probar
    después del cambio.
- **`scripts/install-local-mods.sh`** (borrador):
  - `pz` → `pz-data-staging`, `pz-staging` → `pz-data-ensayo`, fuera
    `pz-vanilla`.
  - Falla si el volumen no existe: `docker run -v` lo crearía vacío sin avisar.
- **`scripts/_common.sh`**: quitar `refuse_frozen_pz` y sus 8 llamadas.
- **`.env.example`** (borrador): puertos 1:1 y fuera `HOST_GAME_PORT*`.
- **Documentación**:
  - Lo que cambia de papel: AGENTS.md, HANDOFF, OPERACIONES, DECISIONES (nueva
    6ter), MODS.md, MODS-LISTA.md, README.md, `config/server.ini.tmpl:15` y
    la cabecera de `update-server.sh`.
  - El fragmento de ACL (`tailscale/acl-fragment.hujson`) pasa a 16461/16462,
    que es lo que ya permite la ACL real.
  - OPERACIONES, runbook "un mod se actualizó a peor" (~l.671): el
    `ls -t backups/*-pre-mods.tar.zst | head -1` tiene que filtrar por el
    prefijo del destino.
  - Dejar escrito que **las copias `staging-*` hasta la fecha del cambio son
    del mundo de juego**.
  - Corregir "37/35" en OPERACIONES (~l.444): son 36/34. El "25 mods" de
    producción es correcto para el mundo de agosto (su INI tiene 25/24); lo
    que pasa es que el `.env` ya no lo reproduce (23/23).
- **Fuera de este cambio** (requiere reconstruir la imagen; va con D3):
  - El mensaje de `docker/ops.sh` (~l.962) que recomienda `docker compose
    down`.
  - `guard_network` elige `pz`/`pz-staging` para su mensaje según
    `PZ_USE_STAGING_MODS`. Sigue acertando mientras solo el ensayo lo lleve.
- **Revisión por otro agente antes del commit.**

## Paso 2 — HECHO (16/11): archivar el mundo de agosto

`backups/pz-pombie-vanilla-20261116-225421-archivo-mundo-16-08.tar.zst`
(57 MB). Verificación:

- Extraído aparte y comparado por md5 fichero a fichero con
  `pz-data-vanilla`: **90.029 ficheros idénticos**.
- La revisión lo repitió con `tar -d`: solo difieren UID y GID, por el mapeo
  de rootless.
- Buildid 24574884 (42.20.3), último guardado del 16/08. Son 257 MB de
  contenido y 393 MB en disco.
- La etiqueta `archivo-mundo-16-08` no rota.

Sacarlo de la máquina deja de ser imprescindible con D5 = no.

### Paso 2b — pendiente: el motor 42.20.3

**El archivo solo no es un punto de retorno.** La guarda de versión impide
abrir el mundo de agosto con un motor más nuevo, que es justo lo que el repo
prohíbe por diseño, y `pz-game-vanilla` es la única instalación 42.20.3 que
queda. Antes de borrarla hay dos opciones:

- **Apuntar cómo recuperarla de Steam** (con `download_depot` de SteamCMD).
  Datos de su `appmanifest_380870.acf`: app 380870, buildid 24574884, depots
  y manifiestos `380871` → `2587362105419356756`, `380873` →
  `4894029153115054997` y `1006` → `6403079453713498174`. **No está probado**
  que Steam siga sirviendo esos manifiestos.
- **Archivar también la instalación** (~7 GB en disco).

## Paso 3 — HECHO (17/11): D5

El administrador decidió que el mundo de juego pasa a producción y que no
hace falta conservar el de agosto listo para arrancar.

## Paso 4 — la parada (con el servidor vacío)

Unos 15 minutos. Antes, D3 hecho en otra parada. Desde la carpeta del
proyecto. Cada comprobación **aborta** el procedimiento si no da lo esperado.

```bash
# a. nadie dentro
docker compose --profile staging exec -T pz-staging /docker/run.sh rcon players

# b. apagado seguro, y COMPROBAR que fue limpio (codigo 0, no un SIGKILL a los 180 s)
docker compose stop pz-staging
docker inspect pombie-staging -f '{{.State.ExitCode}}'          # 0

# c. copia en frío del mundo de juego, con el compose VIEJO
docker compose --profile staging run --rm --no-deps pz-staging backup antes-cambio-de-papeles

# d. copia local del .env (la ignora .gitignore, regla `.env.*`)
cp -p .env .env.antes-cambio-de-papeles

# e. .env, con el script del paso 1 (no imprime valores; enseña los recuentos 34/36)
python3 -I <ruta>/cambiar-env.py .env

# f. traer el commit del paso 1 al directorio vivo (la rama está abierta en
#    otro worktree, así que merge y no switch), y validar
git merge --ff-only refactor/produccion-es-el-mundo-de-juego
docker compose config -q

# g. a qué volumen apunta cada servicio, SIN volcar secretos. Esperado:
#    pz -> pz-game-staging + pz-data-staging; pz-staging -> pz-*-ensayo
docker compose --profile staging config | grep -E "^  [a-z-]+:$|source: pz-|target: /(opt|home)"

# h. quitar SOLO el contenedor viejo (sin -v: los volúmenes no se tocan)
docker rm pombie-staging

# i. COMPROBACIÓN: nadie monta ya el mundo de juego. Tiene que salir vacío
docker ps -a --filter volume=zroyecto-pombie_pz-data-staging --format '{{.Names}}'

# j. COMPROBACIÓN: el .env nuevo lleva la lista del mundo de juego y su puerto.
#    Si el paso e falló o se saltó, pz abriría el mundo con la lista de agosto
#    (23 mods en vez de 36): quitar los irreversibles al cargar es daño
#    permanente, y la verificación de abajo llegaría tarde.
cmp <(sed -n 's/^PZ_MODS=//p' .env) <(sed -n 's/^STAGING_MODS=//p' .env.antes-cambio-de-papeles)
cmp <(sed -n 's/^PZ_WORKSHOP_ITEMS=//p' .env) <(sed -n 's/^STAGING_WORKSHOP_ITEMS=//p' .env.antes-cambio-de-papeles)
[ "$(sed -n 's/^PZ_PORT=//p' .env)" = 16461 ]

# k. levantar producción sobre el mundo de juego
docker compose up -d pz
```

**Verificación**, antes de dar acceso:

- `docker inspect pombie-pz`: monta `pz-data-staging` y `pz-game-staging`, y
  tiene red (no `Networks={}`).
- En el log:
  - `SERVER STARTED`;
  - `Version verificada: buildid 24909836`, ahora con la guarda de versión
    activa;
  - ningún `required mod not found` salvo Tariq's Beards (D6).
- INI renderizado: 36 Mod ID / 34 WorkshopItems.
- Un solo mundo en `Saves/Multiplayer`, con ficheros posteriores a la parada.
- `ss -ulpn | grep 1646`: 16461/16462 en la IP de Tailscale.
- `./scripts/rcon.sh players` responde. Ya apunta al mundo de juego.
- `./scripts/backup.sh verificacion-cambio` produce
  `produccion-<fecha>-verificacion-cambio.tar.zst` de ~106 MB. El mundo de
  agosto pesa 57 MB: el tamaño delata si se respalda el mundo equivocado.
- `healthy`, 0 reinicios.

## Marcha atrás

Los volúmenes no se tocan en ningún momento, así que volver es exacto. Se
vuelve con `git revert` del commit del paso 1, no con un checkout de ficheros:
un checkout deja el árbol sucio, y un `git checkout .` o `git stash` posterior
traería de vuelta el compose nuevo con el `.env` viejo, que es el caso del
paso j.

```bash
docker compose stop pz
docker rm pombie-pz
git revert --no-edit <commit del paso 1>      # vuelve a 41ee74f en compose y scripts, bloqueos incluidos
cp -p .env.antes-cambio-de-papeles .env
# COMPROBACIONES: nadie monta el mundo, y el .env es el de antes
docker ps -a --filter volume=zroyecto-pombie_pz-data-staging --format '{{.Names}}'   # vacío
cmp .env .env.antes-cambio-de-papeles
docker compose --profile staging up -d pz-staging
```

## Paso 5 — pendiente: estrenar el staging nuevo

- **La memoria, resuelta en el paso 1:** el ensayo lleva `mem_limit: 4g` y
  heap 3g (`STAGING_MEMORY`), para que 10 + 4 quepa en la máquina.
- **El motor.** `./scripts/stage.sh` copia el mundo de juego a `pz-*-ensayo`.
  Pero si `pz-game-ensayo` está vacío, el primer arranque descarga el juego más
  reciente, y entonces el ensayo no probaría los mods sobre el mismo motor que
  producción. Mejor **sembrar `pz-game-ensayo` copiando `pz-game-staging`**,
  con el origen en solo lectura.
- **La conexión.** Probar el ensayo en 16361/16362 desde otro dispositivo
  puede necesitar una regla en la ACL. La ACL real no la he visto. Sería una
  decisión aparte.
- **Comprobar después:** `stage.sh --down` borra solo `pz-data-ensayo`;
  `pz-data-staging` sigue ahí y `pombie-pz` sigue jugando.

## Paso 6 — pendiente: los volúmenes viejos (D4)

Condiciones previas:

- Sacar antes `pz-data-vanilla/mods/TariqsBeardsB42`: es la **única copia del
  mod en la máquina**, y no va en el archivo, que solo lleva `Saves`, `db`,
  `Server` y `.pz-buildid`.
- Con D5 = no, el paso 2b y sacar el archivo de la máquina dejan de ser
  imprescindibles: nadie piensa volver al mundo de agosto.

Lo que se borraría:

- `pz-game-vanilla` (7 GB) es la instalación 42.20.3.
- `pz-data-vanilla` (1,3 GB) es el mundo de agosto.

Es irreversible: se decide aparte.

## Lo que no se toca

- La ACL de Tailscale: con D1, los puertos no cambian.
- Los otros contenedores, el Docker de root y `tailscale serve`.
- Los ficheros de la partida: solo se reasignan volúmenes.

## A coordinar con la sesión de Tailscale/Portainer

- El contenedor del mundo de juego pasa a llamarse `pombie-pz`, y
  `pombie-staging` será la copia de pruebas, normalmente parada.
- Si el monitor de disponibilidad vigila `pombie-staging` por nombre o el
  RCON del host en 27115, hay que cambiarlo: si no, avisará de caídas falsas
  y callará las de verdad.
