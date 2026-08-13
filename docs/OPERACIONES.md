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

Ademas la rotacion es **por instancia**: produccion, staging y vanilla usan
prefijos distintos y ninguna puede borrar los backups de otra.

Los generan **produccion y vanilla**. Staging no: lleva
`BACKUP_INTERVAL_HOURS=0` y `BACKUP_ON_START=false` porque su mundo es
literalmente una copia que `stage.sh` rehace cuando quiere. Vanilla tenia esa
misma exencion y se le quito en cuanto dejo de ser cierto que fuera desechable:
se juega en el.

### Lo que se acumula sin limite

Los que no rotan crecen para siempre, y no son solo los que tecleas tu:

| Etiqueta | Cuando aparece | Ritmo real |
| --- | --- | --- |
| `manual` y las tuyas | `./scripts/backup.sh [etiqueta]` | cuando lo pides |
| `stage` | **cada** `./scripts/stage.sh` | el mas frecuente de los automaticos |
| `pre-update` | cada actualizacion del juego | unas pocas al ano |
| `pre-restore` | cada restauracion | raro |

Y hay uno **mas grande que todos, que no esta en `backups/`**: cada
restauracion aparta el mundo entero a una carpeta `.pre-restore-<fecha>`
**dentro del volumen de datos**. No son ~14 MB comprimidos, son los ~110 MB del
mundo sin comprimir, en el mismo disco, y nadie los borra. Una restauracion
cuesta unas ocho veces mas espacio que un backup.

Revision periodica, que son dos comandos:

```bash
du -sh backups/
docker compose run --rm --no-deps pz bash -c 'du -sh /home/steam/Zomboid/.pre-restore-* 2>/dev/null'
```

La parte acotada, en cambio, no preocupa. Con los tamanos de hoy —produccion
~14 MB comprimidos, vanilla ~26 MB— el techo son 40 ficheros por instancia:
~550 MB de produccion mas ~1 GB de vanilla, y ahi se queda.

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
  serializa incluso entre contenedores distintos, porque los tres comparten
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
./scripts/restore.sh pz-pombie-20260809-171751-manual.tar.zst
docker compose up -d
```

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
./scripts/stage.sh --from pz-vanilla   # copia el mundo VANILLA
./scripts/stage.sh --keep              # arranca sin recopiar (repite el --from)
./scripts/stage.sh --down              # para y borra los datos de staging
```

Staging usa **volumenes propios**, incluido el del juego. Comparte la carpeta
`config/`, asi que un cambio en la plantilla afecta a los dos al reiniciar; lo
que no comparte son los datos, que es lo que importa.

Se conecta en `localhost:16361`. El mundo original sigue sin enterarse.

`--from` existe porque staging comparte el **nombre de mundo** con su origen
—el nombre da nombre a la carpeta de guardado— y con mas de un mundo ya no
siempre es produccion. stage.sh averigua el nombre del origen y lo exporta;
sin `--from`, todo funciona como siempre.

### Ensayar un mod de via unica sobre el vanilla (procedimiento oleada 2)

1. En `.env`, poner en `STAGING_WORKSHOP_ITEMS` / `STAGING_MODS` la lista del
   vanilla **mas el candidato**, respetando su posicion de insercion
   ([MODS-LISTA.md](MODS-LISTA.md) seccion 0).
2. `./scripts/stage.sh --from pz-vanilla`
3. Probar en `localhost:16361` con la checklist de abajo, mas lo especifico
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

## Mundo vanilla: el mundo ligero

```bash
docker compose --profile vanilla up -d pz-vanilla     # levantar
docker compose --profile vanilla stop pz-vanilla      # parar
```

Se conecta al **puerto 16461**, no al 16261.

Es el mismo mapa (Knox Country), la misma semilla y los mismos ajustes de
partida que produccion, pero con el mundo generado desde cero y con **siete
mods de interfaz** en vez de los 33 de produccion.

Nacio literalmente sin ninguno, para responder una pregunta que sin el no tiene
respuesta: cuando algo se comporta raro en juego, si la causa son los mods o es
el juego base. **Esa funcion la ha perdido en parte**, y conviene saberlo: la
linea base de errores por hora de un B42.20 sano, que era el dato que faltaba
para calificar las cifras de la incidencia 004, ya no se puede medir aqui
limpiamente. Se cambio a peticion de quienes juegan en el.

Lo que sigue siendo cierto es que su lista es corta, conocida y **sin una sola
entidad**, asi que sigue sirviendo para descartar: si un fallo aparece aqui, no
lo causa ninguno de los 26 mods que este no lleva.

No confundir con staging, que es otra cosa: staging levanta una **copia del
mundo real CON todos sus mods** para ensayar un cambio antes de meterlo en
produccion. Este es un mundo aparte con lista propia.

### Su lista de mods: solo lo reversible

La lista vive en el `.env` (`VANILLA_WORKSHOP_ITEMS` / `VANILLA_MODS`); el
default del compose es el minimo de 7 de interfaz pura para quien monte el
repo de cero. Desde el 13/08 lleva la **oleada 1**: 25 mods (24 del Workshop +
Tariq's Beards local).

El criterio, con su medicion y las oleadas siguientes, esta en
[MODS-LISTA.md](MODS-LISTA.md) seccion 0. El resumen: sobre un mundo empezado
solo entra directo lo que **no declara nada persistente** —ni items, ni
recetas, ni vehiculos, ni entidades— porque eso es lo que se puede quitar sin
dejar referencias rotas. Verificado fichero a fichero sobre lo descargado.

Los seis de inventario, que estuvieron fuera por la sospecha de la incidencia
004, entraron en la oleada 1: los sintomas de esa incidencia se reprodujeron el
12/08 en este mismo mundo **sin** ninguno de ellos, asi que quedaron exonerados
con datos.

Los de **via unica** (Common Sense, Take A Bath, Manage Containers, Realistic
Temperature) solo entran tras probarse en staging sobre una copia de este
mundo: `./scripts/stage.sh --from pz-vanilla`. Trailers! y StarvingZombies son
decisiones de grupo; Bicycle! esta vetado (defectuoso e irreversible).

Los 25 llevan semanas corriendo juntos en produccion y estan marcados como
comprobados en juego en [CHECKLIST-MODS.md](CHECKLIST-MODS.md).

Cuidado con la memoria: no conviene tener produccion y vanilla arriba a la vez
salvo que haga falta comparar en caliente. Miden ~4,5 GB y ~4,1 GB, asi que
caben en una maquina de 14 GB pero sin margen para picos. Comprueba antes con
`docker stats`.

**Tiene backups propios**, con prefijo `vanilla-`, igual que produccion: al
arrancar y cada 6 horas. No los tuvo al principio, cuando se concibio como
mundo de usar y tirar. Dejo de serlo en cuanto la gente empezo a jugar en el, y
un mundo con personajes dentro no es desechable por mucho que asi se pensara.

Para regenerar su mundo desde cero, con el servicio parado:

```bash
docker run --rm -v zroyecto-pombie_pz-data-vanilla:/data \
  --entrypoint bash zroyecto-pombie:latest \
  -c 'rm -rf /data/Saves/* /data/db/* /data/Server/*'
```

**Ese comando borra personajes y bases.** Cuando el vanilla era una referencia
vacia daba igual; ahora no. Haz antes `./scripts/backup.sh` sobre el, o
asegurate de que el ultimo backup automatico te sirve:

```bash
docker exec pombie-vanilla /docker/run.sh status | grep 'Ultimo backup'
```

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

### Si el arranque se detiene con "CAMBIO DE VERSION DETECTADO"

Es la guarda haciendo su trabajo: el binario instalado no es el mismo con el
que se venia jugando. Significa que se colo una actualizacion sin supervisar.

- Si era intencionada: `./scripts/update-server.sh`
- Si no: restaura el ultimo backup y averigua que la disparo (normalmente
  `UPDATE_ON_START=true` en el `.env`).

---

## Migrar a otra maquina

Los datos vivos estan en volumenes de Docker, no en esta carpeta. El vehiculo
de migracion es el tarball, que funciona igual entre Windows y Linux.

**En la maquina origen:**

```bash
docker compose stop            # apagado seguro, importante
./scripts/backup.sh migracion
```

**Copia a la maquina destino** tres cosas:

1. La carpeta del proyecto entera, **incluido `.env`**, que no esta en git y
   lleva las contrasenas y la lista de mods.
2. El `.tar.zst` recien creado dentro de `backups/`.
3. **Los mods locales**, si los hay. Tampoco estan en git: viven en
   `workbench/` y se distribuyen por el canal privado del grupo. Ahora mismo es
   `TariqsBeardsB42.zip`. La lista actual esta en
   [MODS-LISTA.md](MODS-LISTA.md), seccion 1.

Si se pierde el `.env`, se reconstruye desde `.env.example` mas los bloques
`WorkshopItems` y `Mods` de [MODS-LISTA.md](MODS-LISTA.md), que si estan
versionados.

**En la maquina destino:**

```bash
# En Linux, ajusta PUID/PGID en .env al usuario que sera dueno de los datos:
id -u && id -g

docker compose build
docker compose run --rm --no-deps pz restore pz-pombie-<fecha>-migracion.tar.zst

# Mods locales, ANTES de arrancar. Uno por cada .zip que traigas:
./scripts/install-local-mods.sh <ruta>/TariqsBeardsB42.zip

docker compose up -d
docker compose logs -f pz
```

El primer arranque descarga los ~7,5 GB del juego y los mods del Workshop. El
mundo restaurado ya esta en su sitio antes de que el servidor arranque.

**Comprueba que no falta ningun mod local:** si el log dice
`required mod "X" not found`, es que ese mod no esta en `Zomboid/mods` de la
maquina nueva.

Abre **16261 y 16262 en UDP** en el router y el cortafuegos de la maquina
destino. UDP, no TCP.

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
3. `ss -ulpn | grep 1626` — comprueba **en que interfaz** escucha. Lo fija
   `HOST_BIND_IP`: si esta en la IP de Tailscale, desde la LAN no se entra, y es
   a proposito.
4. Comprueba que las reglas del router son **UDP**. Una regla TCP se ve
   perfecta y no sirve de nada.
4. **Conectate al 16261, nunca al 16262.** El 16262 tiene que estar abierto
   pero no se teclea: lo usa el motor por su cuenta.
5. `PZ_PUBLIC=false` significa que no sale en la lista de servidores; hay que
   entrar por IP directa.

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
| `docker compose --profile staging down` | `down` derriba el proyecto ENTERO, produccion incluida. Para parar solo staging: `./scripts/stage.sh --down` |
| Poner `UPDATE_ON_START=true` | Cualquier reinicio podria cambiar el motor bajo un mundo vivo. |
| Editar `config/reference/` | Se regenera y pierdes los cambios. Edita `config/server.ini.tmpl`. |
| Cambiar `PZ_SERVER_NAME` con el mundo en marcha | Da nombre a la carpeta de guardado: equivale a empezar de cero. |
| Anadir varios mods a la vez | Si el mundo falla no sabras cual fue. De uno en uno. |
