# Runbook de operaciones

Todo lo que hay que saber para operar Zroyecto Pombie sin romper nada.

Los comandos asumen que estas en la raiz del proyecto. En Windows usa **Git
Bash**, no PowerShell: los scripts son bash.

---

## Reglas que no se saltan

1. **Parar siempre con `docker compose stop`.** Nunca `kill`. El apagado seguro
   (guardar, esperar, cerrar, esperar al JVM) tarda entre 20 y 60 segundos y es
   lo que evita zombis sin trackear, inventarios a medias y celdas rotas.
2. **Nunca editar la configuracion dentro del contenedor.** Se edita en
   `config/` y en `.env`, y se reinicia. Lo que se toque dentro se pierde al
   siguiente arranque.
3. **Los cambios de riesgo se ensayan en staging primero.** Mods, mapas y
   actualizaciones del juego. Un cambio de ajuste normal no lo necesita.
4. **Antes de tocar nada delicado, `./scripts/backup.sh`.** Es gratis.
5. **Si tocas `docker/`, reconstruye la imagen.** Esos scripts se hornean con
   `COPY docker/ /docker/`: editarlos en el host no cambia nada hasta que hagas
   `docker compose build`. El fallo es silencioso —el contenedor sigue corriendo
   la version vieja— y se pierde un buen rato buscando por que un cambio "no
   hace nada". `config/` no tiene este problema: va montado, no horneado.

---

## Docker rootless

Este despliegue corre con **Docker rootless**: el daemon es del usuario, no de
root, y el socket vive en `/run/user/<uid>/docker.sock`. Se hizo asi para no
tener que meter al usuario en el grupo `docker`, que equivale a darle root sin
contrasena.

Los scripts del repo funcionan igual, sin cambios, siempre que el contexto este
activo:

```bash
docker context show      # debe decir: rootless
docker info --format '{{.SecurityOptions}}'   # debe incluir: name=rootless
```

Tres consecuencias que conviene tener presentes:

**`PUID=0` y `PGID=0` en el `.env`, y no es un descuido.** En rootless, el UID 0
de dentro del contenedor es tu usuario fuera. Con `PUID=1000` los ficheros que
el contenedor escribe en `config/` y `backups/` saldrian con un dueno del rango
subuid que tu usuario no puede editar ni commitear. Con 0 aterrizan a tu nombre.
Correr como root *dentro* de un contenedor rootless no da privilegios fuera.

**El daemon arranca con la sesion de usuario.** Para que sobreviva a un
reinicio sin que nadie inicie sesion hace falta `loginctl enable-linger <user>`,
ademas de `systemctl --user enable docker`.

**La IP de origen de los jugadores no es fiable.** El reenvio lo hace
RootlessKit en espacio de usuario y no conserva el origen, asi que parte de las
conexiones se registran con la IP del gateway del contenedor. Y hay un segundo
motivo que no tiene que ver con rootless: la mayoria de los jugadores entra por
el **relay de Steam**, y ahi se registra la direccion del retransmisor. En
ninguno de los dos casos identifica a nadie: **banear por Steam ID, no por IP.**
Los datos en [TAILSCALE.md](TAILSCALE.md).

---

## Dia a dia

| Que quieres | Comando |
| --- | --- |
| Arrancar | `docker compose up -d` |
| Parar (seguro) | `docker compose stop` |
| Reiniciar | `docker compose restart pz` |
| Logs en vivo | `docker compose logs -f pz` |
| Solo los mensajes del contenedor | `docker compose logs pz \| grep pombie` |
| Estado resumido | `docker compose exec pz /docker/run.sh status` |
| Quien esta conectado | `./scripts/rcon.sh players` |
| Mensaje a todos | `./scripts/rcon.sh servermsg '"texto"'` |
| Guardado manual | `./scripts/rcon.sh save` |
| Mods desfasados frente a Steam | `./scripts/check-mods.sh` |
| Guardar los ajustes tocados en la partida | `./scripts/capture-ini.sh [pz\|pz-staging]` |

Las comillas dobles dentro de comillas simples en `servermsg` no son un capricho:
el comando tiene que llegarle al servidor con el texto entrecomillado.

---

## Cambiar la configuracion

1. Edita `.env` (valores de la instancia) o `config/server.ini.tmpl` /
   `config/SandboxVars.lua` (partida).
2. `docker compose restart pz`
3. Comprueba que se aplico:
   `docker compose exec pz grep MaxPlayers /home/steam/Zomboid/Server/pombie.ini`
4. Commitea el cambio explicando **por que** ese valor.

Un cambio de configuracion **no puede** danar los guardados: el proceso de
renderizado escribe unicamente en `Server/*.ini` y `Server/*_SandboxVars.lua`,
nunca en `Saves/` ni en `db/`. Esta comprobado, no es una suposicion.

### Si el ajuste se toco DENTRO de la partida

Lo que se cambia desde el panel de administrador **no sobrevive al siguiente
arranque**: el render sobrescribe el INI de runtime con la plantilla, siempre.
Es la misma propiedad de una sola direccion de arriba, y es lo que garantiza
que un ajuste no pueda tocar los guardados.

Antes se notaba poco porque los reinicios eran manuales y raros. Desde que el
vigilante de mods reinicia solo, puede pasar a diario. Para que un ajuste hecho
en la partida se quede:

```bash
./scripts/capture-ini.sh                # el mundo de juego (pz)
git diff config/server.ini.tmpl         # revisa antes de commitear
```

`pz-staging` es el ensayo: capturar de ahi traeria al repo lo que se toco en
una copia desechable, y el render se lo aplicaria a la partida buena en el
siguiente arranque. Hasta el cambio de papeles (17/11/2026) era al reves, y
por eso las notas de esas fechas capturan de `pz-staging`.

Trae a la plantilla los valores que difieran, y **deja fuera dos categorias a
proposito**:

- **Las claves que en la plantilla son `${VARIABLES}`.** Su valor manda desde
  el `.env`, y dos son las contrasenas de RCON y del servidor: capturarlas
  las grabaria en un fichero versionado, y el historial de git es permanente.
- **`ResetID`, `ServerPlayerID` y `Seed`.** No son preferencias sino identidad
  del mundo, y produccion y staging comparten esta plantilla.

Si el servidor tiene claves que la plantilla no, las informa pero **no las
anade solas**: eso suele significar que una version nueva del juego las trajo,
y para eso esta `./scripts/bootstrap.sh` con su diff de `config/reference/`.

Hay dos guardas que abortan la captura sin tocar nada si algo saliera mal (que
cambie el numero de lineas con `${...}`, o que una clave sensible acabe con un
valor literal), y sus pruebas estan en `docker/selftest-capture-ini.sh`.

El equivalente para los ajustes de sandbox es `./scripts/capture-sandbox.sh`.

Aviso: buena parte de los `SandboxVars` solo tienen efecto **al crear el
mundo**. Cambiar el tamano del mapa o la distribucion inicial de zombis en un
mundo ya jugado no hace lo que esperas.

---

## Mapa y zonas de aparicion: no son lo mismo

Confunde porque el juego usa la misma palabra para las dos cosas.

**`PZ_MAP=Muldraugh, KY` es el mundo entero**, no una ciudad. Es Knox Country:
un territorio continuo que incluye Muldraugh, West Point, Rosewood, Riverside,
Louisville y todo lo demas. Se llama asi por herencia, porque Muldraugh fue la
primera zona que tuvo el juego. **Lo fija el servidor y el jugador no lo elige.**

**Lo que el jugador elige al crear personaje son las zonas de
`config/spawnregions.lua`**: en que pueblo empieza. Por defecto cuatro. Del
mismo mapa, asi que se puede ir andando de uno a otro sin pantalla de carga.

Para el jugador la pantalla se parece a "elegir mapa", y no lo es. Si alguien
pide "otro mapa", casi siempre lo que quiere es otra zona de inicio, y eso se
toca en `spawnregions.lua`. Un mapa de verdad distinto es un mod de mapa, con lo
que implica: entra en `PZ_MAP` y en la lista de mods, y se ensaya en staging.

---

## Backups

Se hacen solos antes de arrancar, cada 6 horas, y antes de actualizar o
restaurar. Manual:

```bash
./scripts/backup.sh                 # etiqueta "manual"
./scripts/backup.sh antes-de-mods   # etiqueta propia
```

La rotacion solo borra los automaticos (`prestart`, `periodic`), conservando
los ultimos `BACKUP_KEEP` **de cada tipo** — con el valor por defecto son 20
`periodic` y 20 `prestart`, no 20 en total. A 6 horas, eso son unos 5 dias de
historial. Todo lo demas **no se borra nunca**: son justo los que quieres tener
cuando algo ha salido mal.

Ademas la rotacion es **por instancia**: cada servicio firma con su prefijo y
ninguno puede borrar los backups de otro. Los generan los dos, produccion y
el ensayo, este solo mientras esta levantado.

### De que mundo es cada copia

El mismo mundo ha pasado por varios servicios. Desde el cambio de papeles
(17/11/2026) cada servicio firma con un prefijo propio que no comparte con
nadie (`BACKUP_NAME_PREFIX` en el compose), asi que el prefijo basta. Para
las copias anteriores, la ultima del mundo de juego con el reparto viejo es
`staging-*-antes-cambio-de-papeles`.

| Prefijo | Fecha | De que mundo es |
| --- | --- | --- |
| `produccion-` | desde el cambio | **El mundo de juego** (produccion, `pz`) |
| `staging-` | hasta el cambio | **El mundo de juego**, cuando se jugaba en `pz-staging` |
| `pz-pombie-vanilla-` | hasta el cambio | El mundo de agosto, congelado el 16/08 sin los mods irreversibles. Incluye el archivo `...-archivo-mundo-16-08` |
| `ensayo-` | siempre | El ensayo. **Nunca** para el mundo de juego |
| `vanilla-` | hasta el 13/08 | El mundo de juego cuando aun era la referencia sin mods |
| `pz-pombie-` sin `-vanilla` | hasta el 13/08 | El mundo original de 33 mods, retirado |

Consecuencia: **nadie rota ya las `staging-*` ni las `pz-pombie-vanilla-*`**
(la rotacion va por prefijo y ningun servicio los usa). No crecen, pero
tampoco menguan: las `staging-*` ocupan ~7,4 GB. Cuando haya copias
`produccion-*` de sobra, se pueden podar a mano dejando las etiquetadas. Y
ojo con los globs: `pz-pombie-*` casa tambien con `pz-pombie-vanilla-*`.

### Lo que se acumula sin limite

Los que no rotan crecen para siempre, y no son solo los que tecleas tu:

| Etiqueta | Cuando aparece | Ritmo real |
| --- | --- | --- |
| `manual` y las tuyas | `./scripts/backup.sh [etiqueta]` | cuando lo pides |
| `stage` | **cada** `./scripts/stage.sh` | el mas frecuente de los automaticos |
| `pre-update` | cada actualizacion del juego | unas pocas al ano |
| `pre-restore` | cada restauracion | raro |

`pre-mods` **no esta en esta lista a proposito**: a diferencia de las de
arriba, si rota (ver seccion siguiente), asi que no se acumula sin limite.

Y hay uno **mas grande que todos, que no esta en `backups/`**: cada
restauracion aparta el mundo entero a una carpeta `.pre-restore-<fecha>`
**dentro del volumen de datos**. No es el tarball comprimido, es el mundo
entero sin comprimir (687 MB en noviembre de 2026), en el mismo disco, y nadie
lo borra. Una restauracion cuesta varias veces mas espacio que un backup.

Revision periodica, que son dos comandos:

```bash
du -sh backups/
docker compose run --rm --no-deps pz bash -c 'du -sh /home/steam/Zomboid/.pre-restore-* 2>/dev/null'
```

La parte acotada tiene techo: 20 ficheros por etiqueta rotativa (`prestart`,
`periodic`, `pre-mods`) y por instancia. Con el mundo de juego en ~106 MB
comprimidos (noviembre de 2026), son unos 6 GB de produccion como mucho, mas
lo que deje el ensayo con su prefijo, y ahi se queda.

### Que pasa si no hay espacio

El backup **se cancela antes de escribir nada** y avisa en el log. No es por
cuidar la copia, es por cuidar el mundo: `backups/` y los volumenes de datos
comparten sistema de ficheros, asi que un backup que llenara el disco dejaria
al servidor en marcha sin sitio donde guardar. Es preferible quedarse sin copia
de hoy.

Antes de rendirse **intenta rotar los antiguos** para hacer sitio. Importa
porque la rotacion normal vive al final del backup, o sea detras de la
cancelacion: sin ese intento, bajar `BACKUP_KEEP` en el `.env` no liberaria
nada, porque la limpieza estaria detras de un backup que ya no puede ocurrir.

Si no puede medir el espacio (un fallo de `du` o `df`), **sigue adelante
avisando** en vez de cancelar. Un fallo al medir no debe dejarte sin copias,
pero tampoco puede apagar la guarda en silencio.

### Como se decide que un backup vale

Cada backup se verifica con `zstd -t` nada mas crearlo, y si no pasa **se
borra**. La regla es que en `backups/` no llegue a quedarse nunca un archivo
roto con aspecto de bueno: se descubriria el dia de la restauracion, que es el
peor momento posible.

Ojo con una sutileza que costo un backup bueno: **`tar` sale con codigo 1
cuando un fichero cambia mientras lo lee** (`file changed as we read it`), y con
el servidor en marcha sobre ~22.000 ficheros eso es lo *normal*, no un fallo —
el archivo queda entero. Solo el codigo 2 es un error de verdad. Quien decide
si un archivo vale es siempre `zstd -t`, nunca el codigo de salida de `tar`.

Comprobar a mano un backup concreto (con `run`, que funciona este el servidor
levantado o parado; `exec` falla si el contenedor no esta corriendo):

```bash
docker compose run --rm --no-deps pz zstd -t /backups/<fichero>.tar.zst
```

### Detectar que han dejado de hacerse

Contar backups no sirve: los que no rotan sostienen la cifra, asi que un
servidor que lleva nueve dias sin copiar ensena el mismo numero que uno sano. Lo
que lo delata es la **edad**:

```bash
docker compose run --rm --no-deps pz status
```

La linea `Ultimo backup` da nombre y antiguedad, y marca `<-- REVISAR` si supera
el doble del intervalo configurado.

### Detalles de funcionamiento

- **Solo un backup a la vez.** Hay un cerrojo (`backups/.backup.lock`) que
  serializa incluso entre contenedores distintos, porque todos comparten
  `./backups`. Si el bucle periodico salta mientras haces uno a mano, el segundo
  espera y se salta si tarda demasiado.
- **El `prestart` se salta si ya hay uno reciente** (por defecto 60 min,
  `BACKUP_PRESTART_MIN_GAP_MINUTES`). Sin eso, un bucle de reinicios haria 20
  backups del estado roto y expulsaria por rotacion los 20 buenos.

Los backups viven en `backups/` en el disco del host, no dentro de un volumen
de Docker. Un `docker volume rm` accidental no se los lleva.

### Probar que todo esto funciona

Un mecanismo de seguridad que nunca se ha visto funcionar es una suposicion.
Las salvaguardas de arriba tienen pruebas propias, que no tocan nada real y se
pueden lanzar con el servidor en marcha:

```bash
./docker/selftest-backups.sh                                  # desde el host
docker compose run --rm --no-deps --entrypoint bash pz /docker/selftest-backups.sh
```

---

## Restaurar

```bash
./scripts/restore.sh                 # lista lo disponible
./scripts/restore.sh produccion-<fecha>-manual.tar.zst
docker compose up -d
```

Restaura siempre sobre `pz`, el mundo de juego, y **acepta cualquier fichero
de `backups/` sin mirar el prefijo**. Elige con la tabla de *De que mundo es
cada copia*: una `ensayo-*` lleva lo que se probo en el ensayo, y una
`pz-pombie-vanilla-*`, el mundo de agosto, que ademas es de un motor anterior
al instalado.

Pide confirmacion escribiendo `SI`, para el servidor si hacia falta, y por este
orden:

1. **Verifica el archivo con `zstd -t` antes de tocar nada.** Si esta roto,
   aborta con el mundo actual intacto. Comprobar al leer importa mas que al
   escribir: enterarse despues de haber apartado el mundo bueno te deja con dos
   copias inservibles y sin saber cual era cual.
2. Respalda el estado actual (`pre-restore`).
3. **Aparta** los datos anteriores en una carpeta `.pre-restore-<fecha>` dentro
   del volumen, en vez de borrarlos.

Si la extraccion falla, el mensaje dice exactamente donde quedo el mundo
anterior y como devolverlo a su sitio. **No arranques el servidor antes de
hacerlo.**

### Si el backup previo no se puede hacer

La restauracion **se cancela**. Suele ser falta de espacio, y es una situacion
incomoda: el disco lleno es justo el dia en que quieres restaurar. La salida,
que el propio mensaje te da:

```bash
FORCE_RESTORE=true ./scripts/restore.sh <fichero>.tar.zst
```

Aun asi el mundo actual no se borra: se aparta igualmente a `.pre-restore-*`.
Lo que pierdes es el tarball, no el mundo.

### Limpiar despues

Cuando hayas comprobado que el mundo restaurado carga bien, borra la carpeta
apartada. **Ocupa lo mismo que el mundo entero sin comprimir** y nadie la borra
por ti:

```bash
docker compose run --rm --no-deps pz bash -c 'rm -rf /home/steam/Zomboid/.pre-restore-*'
```

---

## Staging: probar sin arriesgar

```bash
./scripts/stage.sh                     # copia el mundo de PRODUCCION y lo levanta aparte
./scripts/stage.sh --from pz         # explicito, mismo efecto
./scripts/stage.sh --keep              # arranca sin recopiar (repite el --from)
./scripts/stage.sh --down              # para y borra los datos de staging
```

Staging usa **volumenes propios**, incluido el del juego (`pz-game-ensayo` y
`pz-data-ensayo`). Comparte la carpeta `config/`, asi que un cambio en la
plantilla afecta a los dos al reiniciar; lo que no comparte son los datos, que
es lo que importa.

Se conecta en los puertos `STAGING_GAME_PORT` / `STAGING_GAME_PORT_2` del
`.env` (**16361/16362**), con RCON del host en `STAGING_RCON_PORT` (27115). El
mundo de juego sigue en 16461 sin enterarse.

**Es desechable, y esta configurado como tal**: `restart: "no"` (tras un
reinicio de la maquina no vuelve solo), acepta cambios de version
(`ALLOW_BUILD_CHANGE`, para poder ensayarlos) y firma sus copias `ensayo-*`.
**No se juega en el.** Del 13/08 al 17/11/2026 si se jugo aqui, y costo una
caida de 14 horas y varias trampas silenciosas (DECISIONES.md 6ter).

**Antes de borrar nada, `stage.sh` se asegura de que borra el ensayo**: saca
el volumen de datos del compose —el mismo donde escribira la restauracion— y
aborta sin tocar nada si `pz` y `pz-staging` montan el mismo, si lo monta
cualquier contenedor que no sea `pombie-staging` (tambien parado), si
`pombie-staging` monta otro, o si no se llama `*_pz-data-ensayo`. Si alguna
vez se niega, no lo fuerces: el compose esta mal o alguien ha vuelto a jugar
en staging.

**Pendiente antes de estrenarlo** (paso 5 de
[PLAN-CAMBIO-DE-PAPELES.md](PLAN-CAMBIO-DE-PAPELES.md)):

- **El motor.** Con `pz-game-ensayo` vacio, el primer arranque descarga el
  juego mas reciente, y el ensayo ya no probaria sobre el mismo motor que
  produccion. Mejor sembrarlo antes copiando `pz-game-staging` (el motor de
  produccion), con el origen en solo lectura.
- **La memoria.** Los dos servicios llevan el mismo heap y `mem_limit` 10g, y
  la maquina no da para los dos holgados: o se le baja la memoria al ensayo, o
  se usa solo con el mundo de juego vacio.

`--from` existe porque staging comparte el **nombre de mundo** con su origen
—el nombre da nombre a la carpeta de guardado— y con mas de un mundo ya no
siempre es produccion. stage.sh averigua el nombre del origen y lo exporta;
sin `--from`, todo funciona como siempre.

### Ensayar un mod de via unica (procedimiento de la oleada 2)

1. En `.env`, poner en `STAGING_WORKSHOP_ITEMS` / `STAGING_MODS` la lista de
   produccion (`PZ_WORKSHOP_ITEMS` / `PZ_MODS`) **mas el candidato**,
   respetando su posicion de insercion ([MODS-LISTA.md](MODS-LISTA.md)
   seccion 0). Con `STAGING_*` vacios, staging replica produccion tal cual.
2. `./scripts/stage.sh`
3. Probar en el puerto de staging con la checklist de abajo, mas lo especifico
   del candidato.
4. `./scripts/stage.sh --down`, y decidir: si entra, entra sabiendo que es
   para quedarse.

**Ojo con los mods locales** (Tariq's Beards): la instantanea solo lleva
`Saves/db/Server`, los mods locales **no viajan**. O se excluyen de
`STAGING_MODS` (lo normal: no afectan a lo que se ensaya), o se instalan a
mano en staging tras el paso 2 con `install-local-mods.sh <src> pz-staging`.

Que mirar antes de dar por bueno un cambio:

- El mundo carga sin errores en el log.
- Tu personaje existe, con su inventario.
- Las construcciones y los contenedores de tu base estan intactos.
- Puedes recorrer zona ya explorada sin celdas rotas ni huecos.

---

## Como esta repartido hoy: produccion y ensayo (17/11/2026)

| | Servicio | Puertos | Volumenes | Que es |
| --- | --- | --- | --- | --- |
| **Produccion** | `pz` (`pombie-pz`) | 16461/16462 | `pz-*-staging` | **El mundo de juego.** `unless-stopped`, guarda de version activa |
| **Staging** | `pz-staging` (`pombie-staging`) | 16361/16362 | `pz-*-ensayo` | Copia desechable para ensayar. `restart: "no"` |
| Archivo | — | — | `pz-*-vanilla`, sin servicio | El mundo congelado el 16/08 |

**Del 13/08 al 17/11/2026 fue al reves**: se jugaba en `pz-staging`, y `pz`
guardaba, parado, el mundo de antes de los 5 irreversibles como punto de
retorno que arrancaba. Nadie volvio, y el cambio de papeles lo deshizo
reasignando volumenes en el compose, sin mover un byte (DECISIONES.md 6ter).
Lo que queda de aquella epoca:

- **Los nombres de volumen mienten.** El mundo de juego vive en
  `pz-data-staging`. Un `docker volume rm` o un `docker run -v` escrito a mano
  con "staging" en el nombre va a la partida buena. Para tocar los datos de un
  servicio, pasa por el compose (`docker compose run ... pz`): el volumen sale
  de ahi y no se equivoca.
- **Las copias de esas fechas** cambian de mundo segun el prefijo y la fecha:
  ver *De que mundo es cada copia*, en Backups.
- **El mundo de agosto ya no es un punto de retorno que arranque.** Queda el
  archivo `backups/pz-pombie-vanilla-20261116-225421-archivo-mundo-16-08.tar.zst`,
  que solo abre con un motor 42.20.3 (DECISIONES.md 6ter), y sus volumenes,
  que nadie monta, hasta decidir si se borran. Volver a el costaria todo lo
  jugado desde el 16/08.

---

## El mundo unico, y por que se llama "vanilla"

Desde el 13/08/2026 **hay un solo mundo de juego**: `pombie-vanilla`. Hoy lo
sirve produccion en el puerto **16461**. Del 16/08 al 17/11 existio ademas su
foto congelada de agosto, que hoy solo queda archivada.

El nombre es herencia. Ese mundo nacio como referencia SIN mods para distinguir
"esto lo rompe un mod" de "esto es asi en Build 42" —y cumplio: respondio
cuatro veces y las cuatro dijo que no eran los mods (ver `docs/incidencias/`)—.
Despues la gente empezo a jugar ahi, pidio interfaz, acabo con 25 mods y
resulto ser mejor mundo que el original de 33. Asi que paso a ser produccion.

**Produccion lo adopto tal cual, sin moverlo**: se reasignaron los volumenes
`pz-data-vanilla` y `pz-game-vanilla` al servicio `pz` en el compose. Reasignar
un volumen no toca ni un byte; copiar o restaurar 285 MB de partida jugada, si.
Por eso el mundo conserva el sufijo `-vanilla` aunque ya no describa nada. El
porque completo, en [DECISIONES.md](DECISIONES.md) 6bis. En el cambio de
papeles de noviembre se repitio el truco con los volumenes de staging (6ter),
y por eso hoy produccion monta `pz-*-staging` y no `pz-*-vanilla`.

El servicio `pz-vanilla` se elimino a la vez. **Dos servicios sobre el mismo
volumen es la forma mas directa de corromper un mundo**, y despues de la
adopcion habrian apuntado los dos a `pz-data-vanilla`.

### Su lista de mods

**Produccion, que es donde se juega** (`PZ_WORKSHOP_ITEMS` / `PZ_MODS` del
`.env`): **36 Mod ID / 34 WorkshopItems**. Los 25 con los que se congelo el
mundo de agosto, mas los 5 irreversibles del 16/08 con sus dependencias, mas
los 4 de contenido del 29/08 (Bandits NPC, LG Extended Plumbing, ClassicBows y
Horse Mod), menos Run and Reload, retirado por incompatibilidad con Horse Mod.
Hasta el cambio de papeles esta lista vivia en `STAGING_*`. Tariq's Beards
esta en ella pero no instalado en este mundo, por decision del administrador.

**Staging** (`STAGING_WORKSHOP_ITEMS` / `STAGING_MODS`): vacios, asi que
replica la lista de produccion. Solo se rellenan para ensayar un candidato.

El criterio, con su medicion y las oleadas siguientes, esta en
[MODS-LISTA.md](MODS-LISTA.md) seccion 0. Empezo siendo que sobre un mundo
empezado solo entrara lo que **no declara nada persistente** —ni items, ni
recetas, ni vehiculos, ni entidades—; se levanto el 16/08 para la oleada 2 y
Trailers!, y desde el 29/08 la reversibilidad es un dato mas, no un veto. Ya
no todo lo que hay se puede quitar sin danos: Horse Mod declara `entity`.

### Ya no hay mundo de referencia limpio

Consecuencia de la promocion que conviene no olvidar: **no queda ninguna
instancia sin mods**. Para descartar mods de via unica sirve staging sobre una
copia; para medir la linea base del juego base, lo que vale es la sesion
archivada del 11/08 (incidencia 004). Si hiciera falta una referencia limpia
otra vez, hay que crear una instancia nueva.

### Regenerar el mundo desde cero

Con el servicio parado:

```bash
docker compose run --rm --no-deps --entrypoint bash pz \
  -c 'rm -rf /home/steam/Zomboid/Saves/* /home/steam/Zomboid/db/* /home/steam/Zomboid/Server/*'
```

Por el compose y no con `docker run -v <volumen>`: los nombres de volumen
mienten (el mundo de juego vive en `pz-data-staging`), y este comando estuvo
escrito contra `pz-data-vanilla`, que hoy es el mundo de agosto y no lo monta
nadie. Asi el volumen lo elige el compose, el mismo que monta el servidor.

**Ese comando borra personajes y bases.** Haz antes una copia ETIQUETADA:

```bash
./scripts/backup.sh antes-de-regenerar
```

No vale fiarse del ultimo backup automatico: los automaticos rotan (20
`periodic` a una cada 6 h son unos cinco dias), y en cuanto el mundo nuevo
lleve unos dias, la rotacion se habra llevado todas las copias del viejo. Las
etiquetadas no rotan.

---

## Actualizar el juego

El arranque normal **no** comprueba actualizaciones, a proposito. La unica via
es:

```bash
./scripts/update-server.sh
```

Hace backup (`pre-update`), actualiza, registra la nueva version y regenera
`config/reference/`. Despues:

```bash
git diff config/reference/     # que ajustes nuevos trae esta version
docker compose up -d
```

Los jugadores tendran que actualizar su cliente en Steam o no podran conectarse.

### Cuando un SOLO jugador no puede entrar y le sale un fichero del juego base

Sintoma exacto (visto el 27/08/2026 con 42.20.4):

```
File doesn't match the one on the server:
media/lua/shared/timedactions/isreadabook.lua
C:\...\steamapps\common\ProjectZomboid\media\lua\shared\TimedActions\ISReadABook.lua
```

**La ruta lo dice todo**: `steamapps\common\ProjectZomboid\` es el JUEGO BASE.
Los mods viven en `steamapps\workshop\content\108600\`. Si la ruta es la
primera, **no es un mod** y borrar el Workshop no puede arreglarlo. Lo provoca
`DoLuaChecksum=true`, que expulsa a quien tenga ficheros del juego distintos.

Casi siempre significa que **ese jugador tiene una version del juego mas nueva
que el servidor** — tipicamente porque acaba de reinstalar o verificar, y Steam
le ha dado la ultima. Es el mismo desfase de siempre, pero al reves y con un
solo afectado, y por eso despista: los demas siguen en la version vieja, que es
la del servidor, y entran sin problema. **El que falla es el que esta bien.**

Diagnostico en un comando — comparar lo instalado con lo que Steam publica:

```bash
docker compose exec pz sh -c 'grep -oP "\"buildid\"\s+\"\K[0-9]+" \
  /opt/pz-server/steamapps/appmanifest_380870.acf | head -1'
curl -fsS 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=108600&count=3&maxlength=100' \
  | jq -r '.appnews.newsitems[] | "\(.date|strftime("%Y-%m-%d")) \(.title)"'
```

Si el buildid instalado es menor que el que anuncia Steam, hay hotfix
pendiente: actualizar (abajo) y avisar a TODOS de que cierren y reabran el
juego, porque tras actualizar el servidor los rezagados seran los demas.

### Actualizar el juego cuando SteamCMD se atasca en `state is 0x6`

`0x6` = instalado (4) + actualizacion requerida (2). SteamCMD reconoce que hay
version nueva y **se niega a bajarla**, normalmente porque el manifiesto lleva
un `ScheduledAutoUpdate` con hora futura. Ha pasado en los dos hotfixes
(17/08 y 27/08), asi que no es mala suerte.

Lo que NO basta: reintentar, `validate`, borrar `steamapps/downloading`, ni
editar `StateFlags` a mano.

Lo que SI funciona, las dos veces — retirar el manifiesto y reinstalar encima:

```bash
docker compose stop pz                    # apagado seguro primero
./scripts/backup.sh antes-de-actualizar   # este camino no hace la pre-update
docker compose run --rm --no-deps --entrypoint bash pz -c '
  mv /opt/pz-server/steamapps/appmanifest_380870.acf{,.atascado}
  rm -rf /opt/pz-server/steamapps/downloading /opt/pz-server/steamapps/temp
  steamcmd +force_install_dir /opt/pz-server +login anonymous \
           +app_info_update 1 +app_info_print 380870 +app_update 380870 +quit'
```

El `+app_info_print` no es decorativo: sin el, SteamCMD falla con un
`Missing configuration` que no significa lo que parece. Y no re-descarga los
7,5 GB: verifica lo que ya hay y baja solo lo que cambia.

**Ojo desde el cambio de papeles (17/11/2026)**: este arreglo se escribio
para `pz-staging`, que entonces era el mundo de juego y tenia la guarda de
version desactivada. En `pz` esta activa, y este camino no pasa por
`update-server.sh`, asi que no registra la version nueva: el siguiente
arranque se parara con "CAMBIO DE VERSION DETECTADO". Lanzar despues
`update-server.sh` no lo arregla, porque no encuentra nada que bajar y
entonces no registra nada. La via que la guarda deja abierta es arrancar UNA
vez con `ALLOW_BUILD_CHANGE=true` en el `.env` (`docker compose up -d
--force-recreate pz`): hace otra copia `pre-update`, registra la version y
arranca. En cuanto arranque, devuelve el `.env` a `false` y recrea otra vez.
**Sin probar**: comprueba en el log `Cambio de version aceptado
explicitamente` y que el `.env` queda en `false`.

**Verificacion imprescindible tras actualizar**, que en el hotfix del 17/08 se
omitio y costo diez dias de un jugador sin poder jugar:

```bash
# 1. el buildid del manifiesto es el que anuncia Steam
# 2. y los ficheros del juego se han reescrito de verdad:
docker compose exec pz sh -c \
  'find /opt/pz-server/media/lua -name "*.lua" -newermt "AAAA-MM-DD" | wc -l'
```

**Que el servidor diga `version=42.20.4` NO basta**: esa cadena sale del
binario, y el binario puede actualizarse mientras los scripts Lua se quedan
atras. Solo los ficheros con fecha nueva prueban que la actualizacion entro
entera. En 42.20.4 cambiaron exactamente 4 ficheros Lua, uno de ellos
`ISReadABook.lua` — el del error de arriba.

### Si el arranque se detiene con "CAMBIO DE VERSION DETECTADO"

Es la guarda haciendo su trabajo: el binario instalado no es el mismo con el
que se venia jugando. Significa que se colo una actualizacion sin supervisar.

- Si era intencionada: `./scripts/update-server.sh`
- Si no: restaura el ultimo backup y averigua que la disparo (normalmente
  `UPDATE_ON_START=true` en el `.env`).

---

## Mods desfasados: el servidor se actualiza y reinicia solo

Steam actualiza los mods de los **clientes** sola, sin preguntar. El servidor
no (a proposito: ver "Actualizar el juego" arriba). Cuando un autor publica,
las versiones dejan de coincidir y nadie puede entrar con *"La version del
articulo de la workshop es diferente a la del servidor"*. Medido: pasa casi a
diario. Historia completa y diseno en [MODS-DESFASADOS.md](MODS-DESFASADOS.md).

**Desde el 16/08/2026 esto se resuelve solo**, sin intervencion:

1. Cada 30 minutos (`MODS_CHECK_INTERVAL_MINUTES`) compara lo instalado
   contra la API publica del Workshop.
2. Si hay desfase, avisa **una vez** por chat y espera.
3. En cuanto el servidor queda vacio: backup, reinicia el JVM **dentro del
   mismo contenedor** (no hay recreacion, no hay downtime de Docker) y sigue
   vigilando.

**Nunca reinicia con gente dentro.** Quien ya este jugando sigue sin que nadie
lo interrumpa; quien intente entrar mientras tanto vera el error de siempre,
hasta que el servidor quede vacio y se ponga al dia solo.

### Comprobar a mano

```bash
./scripts/check-mods.sh              # el servicio que este corriendo
./scripts/check-mods.sh pz-staging   # uno concreto
```

Da una tabla con cada mod, su fecha local, la de Steam, y el veredicto
(`ok` / `desfasado` / `sin-datos`), mas el resumen `DESFASADOS: N de M`. Salida
`0` si esta todo al dia, `1` si hay desfase, `2` si no se pudo consultar la
API. De solo lectura: no reinicia nada.

El mismo resumen, sin red, esta en:

```bash
docker compose exec pz /docker/run.sh status
```

Linea `Mods (workshop)`: fecha del ultimo chequeo, cuantos desfasados, y el
desenlace del ultimo reinicio automatico si hubo alguno.

El chequeo lleva marcado **quien lo hizo**, y conviene mirarlo:

```
chequeo: 2026-08-16 11:54:34 UTC (automatico)   <- el vigilante, por su cuenta
chequeo: 2026-08-16 11:28:19 UTC (manual)       <- alguien lanzo check-mods
```

Sin esa marca, un `(manual)` reciente da la impresion de que el mecanismo esta
trabajando solo cuando a lo mejor solo lo ha mirado una persona. Si lo que
quieres saber es si la vigilancia esta viva, busca un `(automatico)` con menos
de `MODS_CHECK_INTERVAL_MINUTES` de antiguedad.

### El aviso de "no reintento solo"

Si el log dice `Los mismos mods siguen desfasados tras el ultimo reinicio
automatico`, es que **un mod no se pudo poner al dia**: puede que se haya
retirado del Workshop, o que su descarga este fallando. El vigilante no
insiste solo —evita reiniciar cada 30 minutos toda la noche sin arreglar
nada— y hace falta mirarlo a mano con `check-mods.sh`.

### Desactivar la vigilancia temporalmente

```bash
# En .env:
MODS_CHECK_INTERVAL_MINUTES=0
docker compose up -d pz   # recrea con el valor nuevo
```

El servidor vuelve a comportarse exactamente como antes de esta funcionalidad.

### Runbook: un mod se actualizo a peor

Si tras un reinicio automatico algo del juego deja de funcionar y se sospecha
del mod que se acaba de actualizar:

1. `docker compose exec pz /docker/run.sh status` — la linea `Mods (workshop)`
   dice que mod causo el ultimo reinicio y cuando.
2. Si hay datos danados (no solo un mod que se porta mal, sino algo escrito
   mal en el mundo), restaura el backup **`pre-mods`** mas reciente: es el
   punto justo antes de que el mod actualizado tocara el mundo.
   ```bash
   ls -lt backups/produccion-*-pre-mods.tar.zst | head -1
   docker compose stop pz
   ./scripts/restore.sh <ese-fichero>
   ```
   **El prefijo no es opcional.** Un `*-pre-mods` a secas tambien coge las
   `ensayo-*`, que son del ensayo, y las `pz-pombie-vanilla-*`, del mundo de
   agosto: ninguna vale para el mundo de juego. Si no sale ninguna
   `produccion-*` (o es demasiado reciente), las anteriores al cambio de
   papeles (17/11/2026) estan en `ls -lt backups/staging-*-pre-mods.tar.zst`.
   Tabla completa en *Backups*, "De que mundo es cada copia".
3. Quita el mod de `PZ_WORKSHOP_ITEMS` / `PZ_MODS` en `.env` y
   `docker compose up -d`. Los clientes se adaptan solos a la lista nueva.
   **Antes, mira si el mod es de via unica** ([MODS-LISTA.md](MODS-LISTA.md)
   seccion 0): desde el 16/08 los hay, y Horse Mod declara `entity`, que al
   quitarlo puede impedir que el mundo cargue. Si lo es, ensaya la retirada
   en staging antes de hacerla en produccion.

No hace falta avisar a los jugadores de que un mod se quito: el Workshop se
distribuye solo, igual que al anadirlo.

### Probar que la deteccion funciona

Mismo espiritu que las pruebas de backup: no tocan nada real.

```bash
./docker/selftest-modwatch.sh
docker compose run --rm --no-deps pz /docker/selftest-modwatch.sh
```

---

## Migrar a otra maquina

Los datos vivos estan en volumenes de Docker, no en esta carpeta. El vehiculo
de migracion es el tarball, que funciona igual entre Windows y Linux.

**En la maquina origen:**

```bash
docker compose stop            # apagado seguro, importante
./scripts/backup.sh migracion  # copia en frio del mundo de juego (pz)
```

Deja `backups/produccion-<fecha>-migracion.tar.zst`. Del 16/08 al
17/11/2026 este mismo comando se habria llevado el mundo de agosto, porque
`pz` era la foto congelada; desde el cambio de papeles vuelve a ser el bueno.
Comprueba el tamano: el mundo de juego comprimido ronda los 106 MB
(noviembre de 2026), el de agosto 57 MB.

**Copia a la maquina destino** tres cosas:

1. La carpeta del proyecto entera, **incluido `.env`**, que no esta en git y
   lleva las contrasenas y la lista de mods.
2. El `.tar.zst` recien creado dentro de `backups/`.
3. **Los mods locales**, si los hay. Tampoco estan en git: viven en
   `workbench/` y se distribuyen por el canal privado del grupo. Ahora mismo es
   `TariqsBeardsB42.zip`. La lista actual esta en
   [MODS-LISTA.md](MODS-LISTA.md), seccion 1. Ojo: hoy no esta instalado en
   el mundo de juego, por decision del administrador; instalarlo en la
   maquina nueva seria un cambio, no parte de la migracion.

**Y una pieza que no es una carpeta sino un ajuste del sistema**, que hay que
volver a crear a mano en la maquina destino (necesita sudo):

```bash
printf '# Zomboid: ver docs/DECISIONES.md decision 11 del repo del servidor\nnet.ipv4.ip_nonlocal_bind = 1\n' \
  | sudo tee /etc/sysctl.d/60-pz-tailscale.conf
sudo sysctl -w net.ipv4.ip_nonlocal_bind=1
```

Sin el, el juego vuelve a depender de que Tailscale arranque antes que
Docker, y perder esa carrera deja el contenedor sin red (seis semanas de
caida en octubre). El porque, en [DECISIONES.md](DECISIONES.md) decision 11.

Si se pierde el `.env`, se reconstruye desde `.env.example` mas los bloques
`WorkshopItems` y `Mods` de [MODS-LISTA.md](MODS-LISTA.md), que si estan
versionados (la lista del mundo de juego, copiada del `.env` el 17/11; el
resto de aquella seccion 1 es de un mundo anterior). Aun asi, que el `.env`
viaje: es la copia que manda.

**En la maquina destino:**

```bash
# En Linux, ajusta PUID/PGID en .env al usuario que sera dueno de los datos:
id -u && id -g

docker compose build
docker compose run --rm --no-deps pz restore produccion-<fecha>-migracion.tar.zst

# Mods locales, ANTES de arrancar. Uno por cada .zip que traigas:
./scripts/install-local-mods.sh <ruta>/TariqsBeardsB42.zip

docker compose up -d
docker compose logs -f pz
```

El primer arranque descarga los ~7,5 GB del juego y los mods del Workshop. El
mundo restaurado ya esta en su sitio antes de que el servidor arranque.

**Comprueba que no falta ningun mod local:** si el log dice
`required mod "X" not found`, es que ese mod no esta en `Zomboid/mods` de la
maquina nueva. Tariq's Beards ya sale asi en la maquina actual, mientras siga
sin instalar.

Abre en el router y el cortafuegos de la maquina destino los puertos
`PZ_PORT` y `PZ_UDP_PORT` del `.env` (**16461 y 16462** en este despliegue),
en **UDP**, no TCP. Por Tailscale no se abre nada, pero la regla de la ACL
tiene que nombrar esos dos ([TAILSCALE.md](TAILSCALE.md)).

---

## Diagnostico

**El contenedor reinicia en bucle**

```bash
docker compose logs pz --tail 60 | grep -B2 -A20 "#####"
```

Los errores fatales salen enmarcados y con una pausa de 30 s entre reintentos
para que el mensaje sea legible.

**No se puede conectar**

Si el acceso es por Tailscale, el diagnostico esta en
[TAILSCALE.md](TAILSCALE.md): tiene una tabla que distingue los fallos de share,
de ACL y de Tailnet Lock, que se parecen entre si y se arreglan de forma muy
distinta. Empieza por ahi y vuelve aqui solo si los paquetes llegan.

1. `docker compose ps` — el contenedor debe estar `healthy`.
2. `./scripts/rcon.sh players` — si responde, el servidor esta vivo y el
   problema es de red.
3. `ss -ulpn | grep 1646` — comprueba **en que interfaz** escucha. Lo fija
   `HOST_BIND_IP`: si esta en la IP de Tailscale, desde la LAN no se entra, y es
   a proposito.
4. Comprueba que las reglas del router son **UDP**. Una regla TCP se ve
   perfecta y no sirve de nada.
5. **Conectate al 16461, nunca al 16462** (los `PZ_PORT` / `PZ_UDP_PORT` del
   `.env`). El 16462 tiene que estar abierto pero no se teclea: lo usa el
   motor por su cuenta. El ensayo va en 16361/16362.
6. `PZ_PUBLIC=false` significa que no sale en la lista de servidores; hay que
   entrar por IP directa.

**La conexion completa y se pierde al minuto o dos**

Firma exacta: en el DebugLog aparece `Connected new client N ID # 0` (el
handshake SI completa) y en el log de conexiones, ~1-2 min despues,
`connection-lost` de RakNet sin que hubiera `player-connect`. El servidor esta
sano; es el CLIENTE el que, al comparar las versiones de mods con las del
servidor, se queda en su aviso hasta que la conexion caduca.

Causa tipica desde que el servidor se actualiza solo: el jugador tenia el
juego abierto desde antes de que el mod publicara, y conserva la version
vieja. Remedio (autoservicio): **cerrar Project Zomboid del todo y volver a
abrirlo** — Steam solo actualiza los mods del Workshop al arrancar el juego.
Detalle y porque en [MODS-DESFASADOS.md](MODS-DESFASADOS.md), "El caso
inverso".

**"Conexion erronea" y el log no da ningun motivo**

Sintoma exacto: el log registra `Steam client ... is initiating a connection`
y despues **nada**. Ni rechazo, ni contrasena incorrecta, ni aviso de mods. Al
cliente tampoco le llega la lista de mods, asi que ni siquiera sale el aviso de
suscribirse.

Casi siempre es que falta `~/.steam/sdk64/steamclient.so`. Sin ese enlace,
`SteamAPI_Init` no termina de inicializar: el servidor arranca, responde a RCON
y se marca `healthy`, pero **no puede autenticar a los clientes**.

```bash
docker compose exec pz bash -c 'ls -la ~/.steam/sdk64/'
```

Debe aparecer `steamclient.so -> /opt/pz-server/steamclient.so`. El entrypoint
lo rehace en cada arranque, asi que si falta, algo va mal con la instalacion.

Una conexion que SI completa deja esta linea en el log:

```
LOG  : Network > Connected new client <numero> ID # 0
```

Si aparece `is initiating a connection` pero nunca `Connected new client`, el
handshake se esta muriendo por el camino.

Nota: `[S_API FAIL] Tried to access Steam interface SteamNetworkingUtils004
before SteamAPI_Init succeeded` aparece **siempre**, incluso con todo
funcionando. No es sintoma de nada.

**Que NO tocar cuando falla una conexion**

Circulan guias que recomiendan `DisableSteamRelay` o fijar `SteamPort=8766` en
el `.ini`. Estan **obsoletas** para Build 42: ahora se gestiona con la casilla
*Use Steam Relay* del propio juego y los puertos publicados. Esa casilla es un
recurso para redes que bloquean UDP entrante; en local y en LAN no hace falta.

**Va a tirones con varios jugadores**

Sube `PZ_MEMORY` en `.env` y reinicia. Build 42 movio el inventario al lado
servidor y consume mas que Build 41.

Dos avisos antes de subirlo: el heap **no** es el consumo total (metaspace,
pilas de hilos, buffers y GC se suman por encima), y el `mem_limit` del compose
tiene que quedar por encima del consumo real o el contenedor morira de golpe.
Mide antes de decidir:

```bash
docker stats --no-stream pombie-pz
```

Como referencia de este despliegue: con `PZ_MEMORY=6g` y nadie conectado, el
contenedor ronda los 7,1 GiB. Regla practica: deja al menos un 30% de margen
entre consumo observado y `mem_limit`, y no pongas `mem_limit` por encima de lo
que la maquina puede dar sin empezar a usar swap.

**El apagado tarda demasiado o se corta**

`SHUTDOWN_TIMEOUT` (por defecto 150s) tiene que ser **menor** que el
`stop_grace_period` del compose (180s). Si subes uno, sube el otro.

---

## Lo que no hay que hacer

| No hagas | Por que |
| --- | --- |
| `docker compose kill` / `docker kill` | Salta el guardado. Es el camino directo a un mundo corrupto. |
| `docker compose down -v` | La `-v` borra los volumenes. Ahi estan los guardados. |
| `docker compose --profile staging down` | `down` derriba el proyecto ENTERO, produccion incluida. Para parar solo staging: `docker compose stop pz-staging` (`stage.sh --down` ademas BORRA sus datos, los del ensayo y solo esos) |
| Escribir a mano un nombre de volumen | Mienten: el mundo de juego vive en `pz-data-staging`. Pasa por el compose (`docker compose run ... pz`), que elige el volumen bien |
| Poner `UPDATE_ON_START=true` | Cualquier reinicio podria cambiar el motor bajo un mundo vivo. |
| Editar `config/reference/` | Se regenera y pierdes los cambios. Edita `config/server.ini.tmpl`. |
| Cambiar `PZ_SERVER_NAME` con el mundo en marcha | Da nombre a la carpeta de guardado: equivale a empezar de cero. |
| Anadir varios mods a la vez | Si el mundo falla no sabras cual fue. De uno en uno. |
