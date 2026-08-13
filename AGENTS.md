# AGENTS.md

Contexto para agentes de IA que trabajen en este repositorio. Leelo entero antes
de tocar nada: buena parte de lo que aqui parece redundante o excesivo protege
datos que no se pueden recuperar.

## Que es esto

Servidor dedicado de **Project Zomboid Build 42** en Docker. No es una app: es
la infraestructura que aloja el mundo persistente de un grupo de amigos, con
personajes y bases que representan meses de juego.

## El requisito que manda sobre todos los demas

**Un guardado corrupto no tiene marcha atras.** Todo lo demas —rendimiento,
elegancia, brevedad del codigo— se subordina a eso.

La consecuencia practica: ante la duda, **es preferible un servidor caido a un
mundo danado**. De lo primero se sale reiniciando; de lo segundo no siempre. Si
escribes una guarda, que aborte, no que continue con un aviso.

## Reglas que no se negocian

1. **Nunca `docker kill`, `docker compose kill` ni `down -v`.** Lo primero salta
   el apagado seguro; `-v` borra los volumenes, que es donde vive el mundo.
2. **El flujo de configuracion es de una sola direccion**: `config/` -> el
   contenedor. Nada de lo que el servidor escriba en runtime vuelve al repo por
   su cuenta. El render escribe solo en `Server/*.ini` y `Server/*_SandboxVars.lua`,
   jamas en `Saves/` ni `db/`. No introduzcas nada que rompa esa propiedad.
3. **Si tocas `docker/`, hay que `docker compose build`.** Esos scripts se
   hornean en la imagen con `COPY`. Editarlos no surte efecto hasta reconstruir,
   y el fallo es silencioso.
4. **Un mod se anade de uno en uno y pasando por staging.** Si el mundo falla
   con tres mods nuevos, no sabras cual fue. Excepcion acotada: un conjunto que
   ya corrio JUNTO en otra instancia y es reversible (sin definiciones
   persistentes) puede entrar en bloque; el criterio esta en
   docs/MODS-LISTA.md, seccion 0.
5. **Los secretos no entran en git.** Viven en `.env`, que esta ignorado. Antes
   de escribir cualquier cosa en `config/reference/`, comprueba que el filtro de
   redaccion de `docker/ops.sh` la cubre.

## Donde esta cada cosa

```
docker/          TODA la logica real, corre dentro del contenedor
  entrypoint.sh    PID 1 como root: ajusta UID/GID y cede el control con gosu
  run.sh           dispatch de comandos (serve, bootstrap, backup, restore...)
  lifecycle.sh     arranque del servidor y APAGADO SEGURO
  ops.sh           instalar, renderizar config, backup y restore
  lib.sh           helpers: logging, rcon, buildid, procesos
scripts/         envoltorios finos del host; NO metas logica aqui
config/          fuente de verdad de la configuracion, versionada
tailscale/       fragmento de ACL para dar acceso a los jugadores
docs/            el porque de todo
```

La logica vive una sola vez, dentro del contenedor, para que se comporte igual
la lances desde Windows, desde Linux o desde dentro. Si te piden anadir una
operacion, va en `docker/run.sh` con un envoltorio en `scripts/`, no al reves.

## Convenciones

- **Todo en castellano**: comentarios, documentacion y mensajes de commit.
- **Sin tildes en el codigo** (`.sh`, `.yml`, `Dockerfile`). En los `.md` si.
- **Los comentarios explican el porque, no el que.** El repo esta lleno de
  comentarios que documentan una tarde perdida; respeta ese tono y esa densidad.
  Si quitas uno, asegurate de que el problema que describia ya no existe.
- **Commits**: una frase declarativa que explique la consecuencia, y cuerpo con
  el motivo. Historial lineal, sin merges.
- Ramas: `<tipo>/<descripcion-en-kebab>`, p. ej. `feat/despliegue-rootless-tailscale`.

## Como se verifica aqui

**No des por bueno lo que no hayas ejecutado.** Este repo tiene un sesgo fuerte
hacia comprobar en la maquina en lugar de razonar sobre el codigo. Ejemplos del
estilo que se espera:

```bash
docker compose config -q                       # valida sin volcar secretos
docker compose run --rm --no-deps pz status    # ejercita entrypoint y permisos
docker compose logs pz | grep "required mod"   # mods que faltan
./scripts/rcon.sh players                      # el servidor responde de verdad
ss -ulpn | grep 1626                           # escucha donde crees que escucha
./docker/selftest-backups.sh                   # salvaguardas de backup/restore
```

Las salvaguardas de backup y restauracion **tienen pruebas propias** en
`docker/selftest-backups.sh`: no tocan nada real y se pueden lanzar con el
servidor en marcha. Si tocas `do_backup`, `do_restore` o `rotate_backups`,
lanzalas, y si anades una salvaguarda anade tambien su caso. Se escribieron
despues de que una tanda de arreglos "obviamente correctos" introdujera dos
regresiones —borrar backups validos y bloquear la restauracion— que solo
aparecieron al ejecutarlas.

**Recuerda reconstruir la imagen** antes de comprobar cambios en `docker/`: esos
ficheros se copian dentro y el contenedor sigue corriendo los viejos hasta que
se recrea.

Cuidado con `docker compose config` sin `-q`: imprime el `PZ_RCON_PASSWORD` del
healthcheck por pantalla.

Si una comprobacion no es concluyente, dilo. Media verificacion presentada como
verificacion completa es peor que no comprobar nada.

## Trampas conocidas

Estas ya han costado tiempo. Estan documentadas en detalle en
[docs/DECISIONES.md](docs/DECISIONES.md), seccion final:

- Los puertos del juego son **UDP**. Una regla TCP se ve perfecta y no hace nada.
- La RAM del JVM se fija en `ProjectZomboid64.json`, no por linea de comandos.
- `rcon-cli` trata cada argumento como un comando independiente.
- Sin `~/.steam/sdk64/steamclient.so` el servidor arranca, responde a RCON, se
  marca `healthy` y **no puede autenticar a nadie**, sin dar ningun motivo.
- `[S_API FAIL] ... SteamNetworkingUtils004` aparece **siempre**. No es sintoma
  de nada.
- Los scripts de `scripts/` necesitan bit de ejecucion; llegaron sin el.

## Estado actual

Ver [docs/HANDOFF.md](docs/HANDOFF.md), que describe como esta desplegado ahora
mismo y que queda pendiente. Es lo primero que hay que leer para retomar.
