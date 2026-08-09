#!/usr/bin/env bash
# Helpers compartidos por los scripts que corren dentro del contenedor.
# Se carga con `source`, no se ejecuta directamente.

# ---------------------------------------------------------------- logging ---

log()  { printf '[pombie %s] %s\n'       "$(date -u +%H:%M:%S)" "$*"; }
warn() { printf '[pombie %s] AVISO: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
err()  { printf '[pombie %s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# Aborta con un mensaje enmarcado. Se usa para las condiciones que NUNCA deben
# resolverse arrancando igualmente: es preferible un servidor caido a un mundo
# corrupto, porque de lo primero se sale y de lo segundo no siempre.
die_loud() {
    printf '\n' >&2
    printf '  ##############################################################\n' >&2
    while IFS= read -r line; do printf '  # %s\n' "$line" >&2; done <<< "$1"
    printf '  ##############################################################\n' >&2
    printf '\n' >&2
    exit 1
}

# ------------------------------------------------------------------- misc ---

is_true() {
    case "${1,,}" in
        1|true|yes|y|on) return 0 ;;
        *)               return 1 ;;
    esac
}

# ---------------------------------------------------------------- buildid ---

# Version instalada del juego, leida del manifiesto que deja SteamCMD.
# Es un entero monotono que Steam incrementa en cada publicacion; nos vale
# como huella exacta de "que binario hay ahora mismo en el volumen".
installed_buildid() {
    local manifest="${PZ_DIR}/steamapps/appmanifest_${STEAM_APP_ID}.acf"
    [[ -f "$manifest" ]] || { echo ""; return 0; }
    grep -oP '"buildid"\s+"\K[0-9]+' "$manifest" 2>/dev/null | head -1
}

# Version con la que se creo/uso por ultima vez este mundo.
recorded_buildid() {
    local f="${DATA_DIR}/.pz-buildid"
    [[ -f "$f" ]] && cat "$f" || echo ""
}

record_buildid() {
    printf '%s\n' "$1" > "${DATA_DIR}/.pz-buildid"
}

# ------------------------------------------------------------------- rcon ---

# Devuelve 0 si el servidor responde por RCON. Es tambien nuestra senal de
# "el servidor ya ha terminado de arrancar y esta operativo".
rcon_ready() {
    rcon -a "127.0.0.1:${PZ_RCON_PORT}" -p "${PZ_RCON_PASSWORD}" -t rcon \
         "players" >/dev/null 2>&1
}

rcon_cmd() {
    rcon -a "127.0.0.1:${PZ_RCON_PORT}" -p "${PZ_RCON_PASSWORD}" -t rcon "$@" 2>&1
}

# Manda un comando por la consola del servidor a traves del FIFO de stdin.
# Es la via de respaldo para cuando RCON no responde (mal configurado, o el
# servidor aun no ha abierto el puerto). Tener dos caminos independientes hacia
# `save` y `quit` es deliberado: el apagado limpio es demasiado importante para
# depender de un unico mecanismo.
console_cmd() {
    [[ -p "$PZ_STDIN_FIFO" ]] || return 1
    printf '%s\n' "$*" > "$PZ_STDIN_FIFO" 2>/dev/null
}

# --------------------------------------------------------------- procesos ---

# PID del JVM real del servidor. Ojo: start-server.sh es solo un lanzador, el
# proceso que de verdad escribe los guardados es su hijo. Esperar al lanzador
# en vez de al JVM es un fallo sutil que deja el mundo a medio guardar.
zomboid_pids() {
    pgrep -f 'ProjectZomboid64|zombie.network.GameServer' 2>/dev/null || true
}

zomboid_running() {
    [[ -n "$(zomboid_pids)" ]]
}

# Espera a que el JVM desaparezca. Devuelve 1 si se agota el plazo.
wait_for_exit() {
    local timeout="$1" waited=0
    while zomboid_running; do
        (( waited >= timeout )) && return 1
        sleep 2
        waited=$(( waited + 2 ))
    done
    return 0
}
