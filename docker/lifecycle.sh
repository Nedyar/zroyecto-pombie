#!/usr/bin/env bash
# Ciclo de vida del proceso del servidor: arrancarlo y, sobre todo, pararlo
# bien. Se carga con `source`.
#
# Parar mal un servidor de Project Zomboid es el vector de corrupcion mas
# frecuente que existe. Un SIGKILL a media escritura deja zombis sin trackear
# (la gente aparece en su base rodeada), inventarios a medias y celdas del mapa
# inconsistentes. La secuencia correcta no es opcional: save, quit, y esperar a
# que el JVM termine por su cuenta.

PZ_STDIN_FIFO="${PZ_STDIN_FIFO:-/tmp/pz-stdin}"
SERVER_LAUNCHER_PID=""

# ================================================================ ARRANQUE ===

launch_server() {
    local servername="$1"

    # El servidor lee comandos de consola por stdin. Si stdin esta cerrado, el
    # bucle de lectura recibe EOF continuamente y algunas versiones se comen una
    # CPU entera girando en vacio. Un FIFO abierto en lectura-escritura nunca
    # produce EOF, asi que el servidor se queda esperando tranquilo.
    #
    # De regalo nos da un segundo canal para mandarle comandos, independiente
    # de RCON. Cuando lo que esta en juego es apagar limpiamente, tener dos
    # caminos separados hacia `save` merece la pena.
    rm -f "$PZ_STDIN_FIFO"
    mkfifo "$PZ_STDIN_FIFO"
    exec 3<> "$PZ_STDIN_FIFO"

    log "Arrancando servidor '${servername}' (RAM maxima ${PZ_MEMORY})"

    cd "$PZ_DIR"
    ./start-server.sh \
        -servername "$servername" \
        -adminusername "$PZ_ADMIN_USERNAME" \
        -adminpassword "$PZ_ADMIN_PASSWORD" \
        -cachedir="$DATA_DIR" \
        <&3 &

    SERVER_LAUNCHER_PID=$!
    log "Lanzador arrancado (pid ${SERVER_LAUNCHER_PID})"
}

# ================================================================== APAGADO ===

graceful_shutdown() {
    local timeout="${1:-150}"

    if ! zomboid_running; then
        log "No hay ningun proceso del servidor vivo; nada que apagar."
        return 0
    fi

    log "Iniciando apagado seguro (plazo ${timeout}s)"

    local rcon_ok=0
    rcon_ready && rcon_ok=1

    # Avisar a quien este dentro. Si no hay nadie, no hacemos esperar a nadie.
    if (( rcon_ok )); then
        local players
        players="$(rcon_cmd players 2>/dev/null | head -1 || true)"
        log "Jugadores conectados: ${players:-desconocido}"

        local warn_secs="${SHUTDOWN_WARNING_SECONDS:-15}"
        if [[ "$players" == *"(0)"* ]]; then
            warn_secs=0
            log "Servidor vacio; me salto el aviso."
        fi

        if (( warn_secs > 0 )); then
            rcon_cmd servermsg "\"El servidor se guarda y reinicia en ${warn_secs} segundos.\"" >/dev/null 2>&1 || true
            sleep "$warn_secs"
        fi
    else
        warn "RCON no responde; uso la consola del servidor como via alternativa."
    fi

    # ---- Paso 1: guardar ----
    log "Guardando el mundo..."
    if (( rcon_ok )); then
        rcon_cmd save 2>&1 | sed 's/^/    /' || warn "El 'save' por RCON no confirmo."
    else
        console_cmd save || warn "No pude mandar 'save' por la consola."
    fi

    # Dar tiempo real a que el guardado termine de escribir a disco. Este sleep
    # no es una supersticion: mandar 'quit' con el 'save' aun en vuelo es
    # exactamente lo que produce guardados a medias.
    sleep "${SAVE_SETTLE_SECONDS:-10}"

    # ---- Paso 2: salir ----
    log "Mandando 'quit'..."
    if (( rcon_ok )); then
        rcon_cmd quit >/dev/null 2>&1 || true
    fi
    console_cmd quit 2>/dev/null || true

    # ---- Paso 3: esperar de verdad al JVM ----
    # Esperar al lanzador no vale: start-server.sh es un envoltorio, y el
    # proceso que escribe los guardados es su hijo.
    log "Esperando a que el JVM termine..."
    if wait_for_exit "$timeout"; then
        log "Servidor apagado limpiamente."
        return 0
    fi

    # ---- Escalada ----
    warn "Sigue vivo tras ${timeout}s. Mando SIGTERM al JVM."
    local pid
    for pid in $(zomboid_pids); do kill -TERM "$pid" 2>/dev/null || true; done

    if wait_for_exit 60; then
        log "Servidor apagado tras SIGTERM."
        return 0
    fi

    warn "No responde a SIGTERM. Ultimo recurso: SIGKILL."
    warn "OJO: un SIGKILL puede haber dejado el guardado inconsistente."
    warn "Si al volver a arrancar ves cosas raras, restaura el ultimo backup."
    for pid in $(zomboid_pids); do kill -KILL "$pid" 2>/dev/null || true; done
    wait_for_exit 30 || true
    return 1
}

# Espera a que el servidor este operativo. Devuelve 1 si se agota el plazo.
wait_for_ready() {
    local timeout="${1:-600}" waited=0
    while (( waited < timeout )); do
        if rcon_ready; then
            log "Servidor operativo tras ${waited}s."
            return 0
        fi
        if ! zomboid_running && (( waited > 45 )); then
            return 1
        fi
        sleep 5
        waited=$(( waited + 5 ))
    done
    return 1
}
