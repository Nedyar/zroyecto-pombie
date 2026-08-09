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

## Backups

Se hacen solos antes de arrancar, cada 6 horas, y antes de actualizar o
restaurar. Manual:

```bash
./scripts/backup.sh                 # etiqueta "manual"
./scripts/backup.sh antes-de-mods   # etiqueta propia
```

La rotacion solo borra los automaticos (`prestart`, `periodic`), conservando
los ultimos `BACKUP_KEEP`. Los `manual`, `pre-update` y `pre-restore` **no se
borran nunca**: son justo los que quieres tener cuando algo ha salido mal.

Los backups viven en `backups/` en el disco del host, no dentro de un volumen
de Docker. Un `docker volume rm` accidental no se los lleva.

---

## Restaurar

```bash
./scripts/restore.sh                 # lista lo disponible
./scripts/restore.sh pz-pombie-20260809-171751-manual.tar.zst
docker compose up -d
```

Pide confirmacion escribiendo `SI`, para el servidor si hacia falta, respalda
el estado actual (`pre-restore`) y **aparta** los datos anteriores en una
carpeta `.pre-restore-<fecha>` dentro del volumen en vez de borrarlos.

Cuando hayas comprobado que el mundo restaurado carga bien, esa carpeta se
puede borrar:

```bash
docker compose exec pz bash -c 'rm -rf /home/steam/Zomboid/.pre-restore-*'
```

---

## Staging: probar sin arriesgar

```bash
./scripts/stage.sh          # copia el mundo de produccion y lo levanta aparte
./scripts/stage.sh --keep   # arranca sin recopiar
./scripts/stage.sh --down   # para y borra los datos de staging
```

Staging usa **volumenes propios**, incluido el del juego. Comparte la carpeta
`config/`, asi que un cambio en la plantilla afecta a los dos al reiniciar; lo
que no comparte son los datos, que es lo que importa.

Se conecta en `localhost:16361`. Produccion sigue corriendo sin enterarse.

Que mirar antes de dar por bueno un cambio:

- El mundo carga sin errores en el log.
- Tu personaje existe, con su inventario.
- Las construcciones y los contenedores de tu base estan intactos.
- Puedes recorrer zona ya explorada sin celdas rotas ni huecos.

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

**Copia a la maquina destino:** la carpeta del proyecto entera (incluido
`.env`, que no esta en git) y el `.tar.zst` recien creado dentro de `backups/`.

**En la maquina destino:**

```bash
# En Linux, ajusta PUID/PGID en .env al usuario que sera dueno de los datos:
id -u && id -g

docker compose build
docker compose run --rm --no-deps pz restore pz-pombie-<fecha>-migracion.tar.zst
docker compose up -d
docker compose logs -f pz
```

El primer arranque descarga los ~7,5 GB del juego. El mundo restaurado ya esta
en su sitio antes de que el servidor arranque.

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

1. `docker compose ps` — el contenedor debe estar `healthy`.
2. `./scripts/rcon.sh players` — si responde, el servidor esta vivo y el
   problema es de red.
3. Comprueba que las reglas del router son **UDP**. Una regla TCP se ve
   perfecta y no sirve de nada.
4. `PZ_PUBLIC=false` significa que no sale en la lista de servidores; hay que
   entrar por IP directa.

**Va a tirones con varios jugadores**

Sube `PZ_MEMORY` en `.env` y reinicia. Build 42 movio el inventario al lado
servidor y consume mas que Build 41. Con 32 GB en la maquina, 12g o 16g es
razonable.

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
