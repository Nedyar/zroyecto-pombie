# Zroyecto Pombie

Servidor dedicado de **Project Zomboid Build 42** en Docker, pensado para
configurarse en una maquina y desplegarse en otra sin rehacer el trabajo.

## Lo que hace distinto a este montaje

El requisito que manda sobre todos los demas es poder seguir tocando ajustes y
mods **despues** de que la gente tenga personajes y bases, sin miedo a romper
los guardados. Eso no se consigue teniendo cuidado, se consigue con estructura:

| Riesgo | Como se neutraliza |
| --- | --- |
| Un cambio de configuracion pisa datos del mundo | La config vive en `config/` y se renderiza hacia el contenedor en una sola direccion. El proceso no escribe nunca en `Saves/`. |
| Una actualizacion de Steam cambia el motor bajo un mundo vivo | El arranque **no** comprueba actualizaciones. Ademas se registra el `buildid` del mundo y el arranque se **detiene** si no coincide con el instalado. |
| Docker mata el servidor a media escritura | Apagado por RCON (`save` -> espera -> `quit` -> espera al JVM) con `stop_grace_period: 180s`. |
| Un mod nuevo corrompe contenedores o celdas | Entorno de **staging** que levanta una copia del mundo real en otros puertos. Se prueba ahi primero. |
| Algo sale mal igualmente | Backups automaticos antes de arrancar, antes de actualizar y antes de restaurar. Los criticos no se rotan nunca. |

## Puesta en marcha

```bash
cp .env.example .env        # y rellena las contrasenas
chmod +x scripts/*.sh       # en Linux; git no siempre conserva el bit
docker compose build
./scripts/bootstrap.sh      # instala el juego (~8 GB) y genera la config real
docker compose up -d
docker compose logs -f pz
```

En Linux, si no quieres meter tu usuario en el grupo `docker` —que equivale a
darle root sin contrasena— este montaje funciona tal cual con **Docker
rootless**. Requiere poner `PUID=0` en el `.env`; el porque esta en
[docs/OPERACIONES.md](docs/OPERACIONES.md).

Conexion: `<ip-del-host>:16261`, siempre **UDP** (no TCP: es el error mas comun).

Si se expone por Internet, hay que abrir 16261 y 16262 en el router. Si se
expone por **Tailscale**, que es como esta desplegado ahora, no se abre nada:
ver [docs/TAILSCALE.md](docs/TAILSCALE.md).

## Comandos

| Que quieres | Comando |
| --- | --- |
| Arrancar | `docker compose up -d` |
| Parar (guardado seguro) | `docker compose stop` |
| Ver logs | `docker compose logs -f pz` |
| Estado | `docker compose exec pz /docker/run.sh status` |
| Consola del servidor | `./scripts/rcon.sh players` |
| Backup manual | `./scripts/backup.sh [etiqueta]` |
| Restaurar | `./scripts/restore.sh [fichero]` |
| Actualizar el juego | `./scripts/update-server.sh` |
| Probar cambios sin riesgo | `./scripts/stage.sh` |
| Instalar un mod que no viene del Workshop | `./scripts/install-local-mods.sh <zip>` |
| Traer al repo los ajustes de sandbox de los mods | `./scripts/capture-sandbox.sh` |
| Traer al repo los ajustes tocados en la partida | `./scripts/capture-ini.sh` |
| Ver si algun mod se ha quedado atras frente a Steam | `./scripts/check-mods.sh` |

**Nunca** uses `docker compose kill` ni `docker kill`. Saltan el apagado seguro.

## Estructura

```
config/          fuente de verdad de la configuracion (versionada en git)
  reference/       lo que genera el juego instalado; sirve para ver que trae
                   cada actualizacion. Generado, no editar a mano.
docker/          scripts que corren dentro del contenedor (toda la logica)
scripts/         envoltorios finos para el dia a dia desde el host
backups/         tarballs; tambien el vehiculo para migrar de maquina
tailscale/       fragmento de ACL para dar acceso a los jugadores
docs/            runbook y decisiones de diseno
```

Los datos vivos (guardados, base de datos de jugadores, logs) **no** estan en
esta carpeta: viven en volumenes de Docker, por rendimiento. Se migran con
`backups/`. Ver [docs/OPERACIONES.md](docs/OPERACIONES.md).

## Documentacion

- [docs/HANDOFF.md](docs/HANDOFF.md) — **empieza aqui**: como esta desplegado ahora, que esta verificado y que queda pendiente.
- [AGENTS.md](AGENTS.md) — contexto para agentes de IA que trabajen en el repo.
- [docs/OPERACIONES.md](docs/OPERACIONES.md) — runbook: operar, actualizar, migrar, recuperarse de un desastre.
- [docs/TAILSCALE.md](docs/TAILSCALE.md) — como entran los jugadores: node sharing, ACL y diagnostico de red.
- [docs/MODS.md](docs/MODS.md) — procedimiento verificado para anadir mods sin arriesgar los guardados.
- [docs/MODS-ADOPTADOS.md](docs/MODS-ADOPTADOS.md) — que mods llevamos, en lenguaje llano. Pensado para pasarselo a los jugadores.
- [docs/MODS-LISTA.md](docs/MODS-LISTA.md) — el documento tecnico de los mods: que entro, que se descarto y por que, con la medicion detras.
- [docs/MODS-DESFASADOS.md](docs/MODS-DESFASADOS.md) — por que el servidor se rompia casi a diario, y el mecanismo que lo arregla solo.
- [docs/CHECKLIST-MODS.md](docs/CHECKLIST-MODS.md) — que comprobar en juego, mod por mod, para saber si funcionan de verdad.
- [docs/DECISIONES.md](docs/DECISIONES.md) — por que el montaje es asi.
- [docs/incidencias/](docs/incidencias/) — lo que esta roto: sintoma, evidencia y propuesta, sin aplicar.
