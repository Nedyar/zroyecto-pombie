#!/usr/bin/env bash
# Manda un comando a la consola del servidor. Uso: ./scripts/rcon.sh players
#
# Utiles:
#   players                          quien esta conectado
#   save                             forzar guardado
#   servermsg "texto"                mensaje a todo el mundo
#   quit                             guardar y cerrar (mejor: docker compose stop)
#   checkModsNeedUpdate              hay mods con actualizacion pendiente
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[[ $# -gt 0 ]] || die "Uso: ./scripts/rcon.sh <comando> [args]"

service_running pz || die "El servidor no esta corriendo."

"${DC[@]}" exec -T pz /docker/run.sh rcon "$@"
