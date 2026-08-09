#!/usr/bin/env bash
# Punto de entrada real (ya como usuario steam) y CLI del contenedor.
#
# Todos los comandos de operacion viven aqui dentro en lugar de en los scripts
# del host. Los de scripts/ son envoltorios finos que llaman a este. Asi la
# logica de backup, restauracion y apagado existe una sola vez, y funciona
# igual la lances desde Windows, desde Linux o desde dentro del contenedor.
set -Eeuo pipefail

source /docker/lib.sh
source /docker/lifecycle.sh
source /docker/ops.sh

# ================================================================ DEFAULTS ===

: "${PZ_SERVER_NAME:=pombie}"
: "${PZ_ADMIN_USERNAME:=admin}"
: "${PZ_ADMIN_PASSWORD:=}"
: "${PZ_RCON_PORT:=27015}"
: "${PZ_RCON_PASSWORD:=}"
: "${PZ_MEMORY:=8g}"
: "${PZ_MEMORY_MIN:=2g}"
: "${UPDATE_ON_START:=false}"
: "${ALLOW_BUILD_CHANGE:=false}"
: "${BACKUP_INTERVAL_HOURS:=6}"
: "${BACKUP_KEEP:=20}"
: "${BACKUP_ON_START:=true}"
: "${SHUTDOWN_TIMEOUT:=150}"

# En staging, si hay una lista de mods propia definida, se usa en lugar de la
# de produccion. Vacia = replicar produccion. Es lo que permite probar un mod
# nuevo sobre una copia del mundo real sin que produccion se entere.
if is_true "${PZ_USE_STAGING_MODS:-false}"; then
    if [[ -n "${STAGING_WORKSHOP_ITEMS:-}" || -n "${STAGING_MODS:-}" ]]; then
        PZ_WORKSHOP_ITEMS="${STAGING_WORKSHOP_ITEMS:-}"
        PZ_MODS="${STAGING_MODS:-}"
        log "STAGING: usando lista de mods propia (${PZ_WORKSHOP_ITEMS:-vacia})"
    else
        log "STAGING: sin lista propia; replico los mods de produccion."
    fi
fi

export PZ_SERVER_NAME PZ_ADMIN_USERNAME PZ_RCON_PORT PZ_RCON_PASSWORD
export PZ_WORKSHOP_ITEMS PZ_MODS

STOPPING=0
BACKUP_LOOP_PID=""

# ============================================================ VALIDACIONES ===

validate_env() {
    if [[ "$PZ_SERVER_NAME" =~ [^A-Za-z0-9_-] ]]; then
        die_loud \
"PZ_SERVER_NAME='${PZ_SERVER_NAME}' contiene caracteres no validos.
Usa solo letras, numeros, guion y guion bajo: da nombre a ficheros y
carpetas de guardado, y un espacio ahi rompe cosas de formas raras."
    fi

    if [[ -z "$PZ_ADMIN_PASSWORD" || "$PZ_ADMIN_PASSWORD" == "CAMBIAME" ]]; then
        die_loud \
"PZ_ADMIN_PASSWORD no esta configurada (o sigue con el valor de ejemplo).
Editala en el fichero .env antes de arrancar."
    fi

    if [[ -z "$PZ_RCON_PASSWORD" || "$PZ_RCON_PASSWORD" == "CAMBIAME" ]]; then
        die_loud \
"PZ_RCON_PASSWORD no esta configurada (o sigue con el valor de ejemplo).
Sin RCON no hay apagado seguro, asi que no es opcional.
Editala en el fichero .env antes de arrancar."
    fi
}

# ================================================================== BACKUP ===

periodic_backup_loop() {
    local secs=$(( BACKUP_INTERVAL_HOURS * 3600 ))

    # Gancho para poder verificar el bucle sin esperar horas. En operacion
    # normal no se usa: un mecanismo de seguridad que nunca se ha visto
    # funcionar es una suposicion, no una salvaguarda.
    [[ -n "${BACKUP_INTERVAL_SECONDS:-}" ]] && secs="$BACKUP_INTERVAL_SECONDS"

    (( secs > 0 )) || { log "Backups periodicos desactivados."; return 0; }

    log "Backups periodicos cada ${secs}s (conservando ${BACKUP_KEEP})."
    while true; do
        sleep "$secs"
        (( STOPPING )) && break
        do_backup "periodic" || warn "El backup periodico fallo; sigo."
    done
}

# ================================================================== SENALES ===

on_signal() {
    # Ignoramos senales posteriores: si alguien pulsa Ctrl-C dos veces no
    # queremos abortar el guardado que esta justo en marcha.
    trap '' TERM INT
    STOPPING=1

    log "Senal de parada recibida."

    if [[ -n "$BACKUP_LOOP_PID" ]]; then
        kill "$BACKUP_LOOP_PID" 2>/dev/null || true
    fi

    graceful_shutdown "$SHUTDOWN_TIMEOUT" || true
    log "Adios."
    exit 0
}

# =================================================================== SERVE ===

cmd_serve() {
    # Al servir, un error fatal debe pausar antes de salir: si no, la politica
    # de reinicio de Docker relanza el contenedor sin parar y el mensaje de
    # error se pierde entre miles de lineas repetidas.
    export FATAL_PAUSE_SECONDS="${FATAL_PAUSE_SECONDS:-30}"

    validate_env

    if ! game_installed; then
        log "No hay instalacion del juego en el volumen. Instalando..."
        install_game
    elif is_true "$UPDATE_ON_START"; then
        warn "UPDATE_ON_START esta activo: voy a comprobar actualizaciones."
        warn "Esto NO salta la guarda de version; si el build cambia, el arranque se detendra."
        install_game
    else
        log "Juego ya instalado; no compruebo actualizaciones (asi debe ser)."
    fi

    guard_buildid

    # Primera vez: capturamos la configuracion real de esta version y creamos
    # la plantilla a partir de ella.
    if [[ ! -f "${CONFIG_DIR}/server.ini.tmpl" ]]; then
        log "No hay plantilla de configuracion todavia."
        bootstrap_reference
        seed_template
    fi

    render_config
    patch_memory

    # Backup antes de abrir el mundo. Es el que te salva si el arranque de hoy
    # resulta ser el que rompe algo.
    if is_true "$BACKUP_ON_START" && [[ -d "${DATA_DIR}/Saves" ]]; then
        do_backup "prestart" || warn "El backup de arranque fallo; continuo igualmente."
    fi

    trap on_signal TERM INT

    launch_server "$PZ_SERVER_NAME"

    periodic_backup_loop &
    BACKUP_LOOP_PID=$!

    # El trap se ejecuta al interrumpirse este wait. Si el servidor se muere
    # por su cuenta, salimos con su codigo y `restart: unless-stopped` decide.
    set +e
    wait "$SERVER_LAUNCHER_PID"
    local rc=$?
    set -e

    (( STOPPING )) && exit 0

    warn "El servidor termino por su cuenta (codigo ${rc})."
    [[ -n "$BACKUP_LOOP_PID" ]] && kill "$BACKUP_LOOP_PID" 2>/dev/null || true
    exit "$rc"
}

# ============================================================ OTROS COMANDOS ===

cmd_bootstrap() {
    validate_env
    game_installed || install_game
    bootstrap_reference
    if [[ -f "${CONFIG_DIR}/server.ini.tmpl" ]]; then
        log "Ya existe config/server.ini.tmpl; no lo toco."
        log "Compara con config/reference/server.ini para ver que hay de nuevo."
    else
        seed_template
    fi
}

cmd_update() {
    validate_env

    if zomboid_running; then
        die_loud "El servidor esta corriendo. Paralo antes de actualizar."
    fi

    log "Actualizacion explicita del juego solicitada."
    do_backup "pre-update"

    local before; before="$(installed_buildid)"
    install_game
    local after; after="$(installed_buildid)"

    if [[ "$before" == "$after" ]]; then
        log "No habia actualizacion pendiente (buildid ${after})."
    else
        log "Actualizado: ${before} -> ${after}"
        record_buildid "$after"
        log "Los jugadores tendran que actualizar su cliente en Steam tambien."
        log "Regenera la referencia para ver que ajustes nuevos trae:"
        log "    ./scripts/bootstrap.sh"
    fi
}

cmd_rcon() {
    [[ $# -gt 0 ]] || die_loud "Uso: rcon <comando>"
    rcon_cmd "$@"
}

# Inspecciona lo que Steam ha descargado de verdad y saca los Mod ID reales de
# los mod.info. Los IDs NO se copian de guias: circula informacion contradictoria
# sobre el formato en Build 42 (con o sin prefijo '\'), y un ID mal escrito hace
# que el mod simplemente no cargue, sin error claro.
cmd_mods() {
    local wsdir="${PZ_DIR}/steamapps/workshop/content/380870"
    [[ -d "$wsdir" ]] || wsdir="${PZ_DIR}/steamapps/workshop/content/108600"

    if [[ ! -d "$wsdir" ]]; then
        log "No hay nada descargado del Workshop todavia."
        log "Anade IDs a PZ_WORKSHOP_ITEMS en .env y arranca el servidor."
        return 0
    fi

    printf '\nDescargado en: %s\n\n' "$wsdir"

    local wid info modid modname
    for wid in "$wsdir"/*; do
        [[ -d "$wid" ]] || continue
        printf '=== Workshop ID %s ===\n' "$(basename "$wid")"

        while IFS= read -r info; do
            modid="$(grep -iE '^[[:space:]]*id[[:space:]]*=' "$info" | head -1 | cut -d= -f2- | tr -d ' \r')"
            modname="$(grep -iE '^[[:space:]]*name[[:space:]]*=' "$info" | head -1 | cut -d= -f2- | tr -d '\r')"
            printf '    Mod ID : %s\n' "${modid:-<sin id>}"
            printf '    Nombre : %s\n' "${modname:- }"
            printf '    Ruta   : %s\n\n' "${info#$wid/}"
        done < <(find "$wid" -iname 'mod.info' 2>/dev/null | sort)
    done

    printf 'Estructura de carpetas (para deducir el formato correcto de Mods=):\n'
    find "$wsdir" -maxdepth 4 -type d 2>/dev/null | sed "s|$wsdir|  .|" | head -40

    printf '\nCargados ahora mismo segun la config:\n'
    printf '    WorkshopItems = %s\n' "${PZ_WORKSHOP_ITEMS:-<vacio>}"
    printf '    Mods          = %s\n' "${PZ_MODS:-<vacio>}"
}

cmd_status() {
    printf 'Servidor      : %s\n' "$PZ_SERVER_NAME"
    printf 'Instalado     : %s\n' "$(game_installed && echo si || echo no)"
    printf 'buildid disco : %s\n' "$(installed_buildid)"
    printf 'buildid mundo : %s\n' "$(recorded_buildid)"
    printf 'Proceso vivo  : %s\n' "$(zomboid_running && echo si || echo no)"
    printf 'RCON responde : %s\n' "$(rcon_ready && echo si || echo no)"
    printf 'RAM maxima    : %s\n' "$PZ_MEMORY"
    printf 'Backups       : %s\n' "$(ls -1 "${BACKUP_DIR}"/*.tar.zst 2>/dev/null | wc -l)"
}

# ================================================================ DISPATCH ===

case "${1:-serve}" in
    serve)      cmd_serve ;;
    bootstrap)  cmd_bootstrap ;;
    backup)     shift; validate_env; do_backup "${1:-manual}" ;;
    restore)    shift; validate_env; do_restore "${1:-}" ;;
    update)     cmd_update ;;
    rcon)       shift; cmd_rcon "$@" ;;
    mods)       cmd_mods ;;
    status)     cmd_status ;;
    shell)      exec bash ;;
    *)          exec "$@" ;;
esac
