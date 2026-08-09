#!/usr/bin/env bash
# PID 1 del contenedor. Corre como root, ajusta identidades y permisos, y
# entrega el control a run.sh como usuario `steam`.
#
# El unico motivo de existir de este fichero es que los volumenes acaben con
# ficheros propiedad de un UID que tambien exista en la maquina destino. Al
# migrar de Windows (donde el UID da igual) a Linux (donde no), un volumen
# lleno de ficheros de root es un problema tedioso de deshacer.
set -Eeuo pipefail

source /docker/lib.sh

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

current_uid="$(id -u steam)"
current_gid="$(id -g steam)"

if [[ "$current_gid" != "$PGID" ]]; then
    log "Ajustando GID de steam: ${current_gid} -> ${PGID}"
    groupmod -o -g "$PGID" steam
fi

if [[ "$current_uid" != "$PUID" ]]; then
    log "Ajustando UID de steam: ${current_uid} -> ${PUID}"
    usermod -o -u "$PUID" steam
fi

# chown recursivo solo cuando hace falta. El volumen del juego son ~8 GB y
# recorrerlo en cada arranque anadiria un minuto largo de espera a cada
# reinicio sin ganar nada.
for dir in "$PZ_DIR" "$DATA_DIR" "$BACKUP_DIR"; do
    [[ -d "$dir" ]] || mkdir -p "$dir"
    owner="$(stat -c '%u:%g' "$dir")"
    if [[ "$owner" != "${PUID}:${PGID}" ]]; then
        log "Corrigiendo propietario de ${dir} (era ${owner})"
        chown -R "${PUID}:${PGID}" "$dir"
    fi
done

# /config puede venir montado de solo lectura; no es un fallo.
if [[ -d "$CONFIG_DIR" ]] && [[ -w "$CONFIG_DIR" ]]; then
    chown -R "${PUID}:${PGID}" "$CONFIG_DIR" 2>/dev/null || true
fi

log "Cediendo el control a steam (${PUID}:${PGID})"

# exec para que run.sh herede el PID 1 y reciba directamente el SIGTERM que
# manda `docker stop`. Sin esto las senales se pierden y el apagado seguro
# nunca llega a ejecutarse.
exec gosu steam /docker/run.sh "$@"
