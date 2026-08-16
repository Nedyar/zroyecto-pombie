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
source /docker/modwatch.sh

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

# Vigilancia de mods desfasados del Workshop (docker/modwatch.sh). A 0 se
# desactiva: el servidor sigue funcionando exactamente como antes de esta
# funcionalidad, solo que sin el aviso ni el reinicio automatico.
: "${MODS_CHECK_INTERVAL_MINUTES:=30}"
: "${MODS_EMPTY_POLL_SECONDS:=120}"

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
MODS_WATCH_PID=""

# Bandera de "reabre el mundo, no me des por muerto por accidente". La
# escribe modwatch.sh ANTES de apagar el servidor, para que cmd_serve pueda
# distinguir un reinicio pedido por el vigilante de una caida real del JVM.
# Vive en DATA_DIR (no en /tmp) porque es el unico sitio que ambos procesos
# —el bucle principal y el vigilante en segundo plano— tienen garantizado
# como comun, y sobrevive si el propio bash del PID 1 tuviera que recrearse.
RESTART_FLAG="${DATA_DIR}/.pz-restart-requested"

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
    if [[ -n "$MODS_WATCH_PID" ]]; then
        kill "$MODS_WATCH_PID" 2>/dev/null || true
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

    patch_memory
    trap on_signal TERM INT
    rm -f "$RESTART_FLAG"

    # A partir de aqui, todo lo que sigue se repite en CADA apertura del
    # mundo, no solo en el arranque del contenedor: un reinicio automatico por
    # mods desfasados (docker/modwatch.sh) reabre el mundo sin salir de este
    # bucle ni recrear el contenedor. guard_buildid y render_config son
    # idempotentes por diseno, asi que repetirlos en cada vuelta no cambia el
    # comportamiento de hoy; solo lo hace mas seguro (la guarda de version se
    # revalida en cada apertura, no solo la primera vez).
    local pending_mods_verify=0
    while true; do
        guard_buildid
        render_config

        if (( pending_mods_verify )); then
            log "Reabriendo el mundo tras actualizar mods (backup 'pre-mods' ya tomado)."
        elif is_true "$BACKUP_ON_START" && [[ -d "${DATA_DIR}/Saves" ]]; then
            # Backup antes de abrir el mundo. Es el que te salva si el
            # arranque de hoy resulta ser el que rompe algo.
            #
            # Con una salvedad importante: si el contenedor entra en bucle de
            # reinicios —`restart: unless-stopped` relanzando un arranque que
            # falla— cada intento haria su prestart, y en veinte intentos la
            # rotacion expulsaria los veinte prestart buenos para sustituirlos
            # por veinte copias del estado roto. La rotacion cuenta ficheros,
            # no sabe distinguir "veinte puntos repartidos en semanas" de
            # "veinte fotos del mismo minuto".
            #
            # Por eso se salta si ya hay uno reciente: entre dos arranques
            # seguidos el mundo apenas ha cambiado, asi que no se pierde nada
            # util.
            local gap="${BACKUP_PRESTART_MIN_GAP_MINUTES:-60}"
            if (( gap > 0 )) && recent_backup_exists "prestart" "$gap"; then
                log "Ya hay un backup de arranque de hace menos de ${gap} min; me lo salto."
                log "  Protege el historial de un bucle de reinicios."
            else
                do_backup "prestart" || warn "El backup de arranque fallo; continuo igualmente."
            fi
        fi

        launch_server "$PZ_SERVER_NAME"

        # Los bucles de fondo se arrancan UNA sola vez y sobreviven a
        # reaperturas del mundo: no les importa que el JVM de debajo se haya
        # reiniciado, igual que el de backups no le importaba ya antes.
        if [[ -z "$BACKUP_LOOP_PID" ]]; then
            periodic_backup_loop &
            BACKUP_LOOP_PID=$!
        fi
        if [[ -z "$MODS_WATCH_PID" ]]; then
            mods_watch_loop &
            MODS_WATCH_PID=$!
        fi

        if (( pending_mods_verify )); then
            pending_mods_verify=0
            # En segundo plano: puede tardar hasta wait_for_ready(180), y el
            # bucle principal debe entrar cuanto antes en el `wait` de abajo
            # para poder atender una senal de parada real mientras tanto.
            verify_after_mods_restart &
        fi

        # El trap se ejecuta al interrumpirse este wait. Si el servidor se
        # muere por su cuenta, salimos con su codigo y `restart: unless-stopped`
        # decide.
        set +e
        wait "$SERVER_LAUNCHER_PID"
        local rc=$?
        set -e

        (( STOPPING )) && exit 0

        if [[ -f "$RESTART_FLAG" ]]; then
            log "El vigilante de mods detecto el servidor vacio y pidio reiniciar."
            rm -f "$RESTART_FLAG"
            # Casi siempre ya esta muerto: graceful_shutdown, llamada por el
            # propio vigilante, ya esperO a que el JVM terminara antes de
            # devolvernos el control. Este margen corto es solo por si el
            # lanzador tarda un instante mas en salir que su hijo.
            wait_for_exit 30 || true
            do_backup "pre-mods" || \
                warn "El backup 'pre-mods' fallo; reinicio la partida igualmente (ver docs/DECISIONES.md, 'aceptar lo que publique el autor')."
            pending_mods_verify=1
            continue
        fi

        warn "El servidor termino por su cuenta (codigo ${rc})."
        [[ -n "$BACKUP_LOOP_PID" ]] && kill "$BACKUP_LOOP_PID" 2>/dev/null || true
        [[ -n "$MODS_WATCH_PID" ]]  && kill "$MODS_WATCH_PID"  2>/dev/null || true
        exit "$rc"
    done
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

    # Aqui si es correcto abortar si el backup falla —actualizar sin copia es
    # justo lo que no queremos— pero tiene que abortar DICIENDOLO. La llamada
    # desnuda moria por `set -e` sin una sola linea que explicara el motivo.
    do_backup "pre-update" || die_loud \
"NO HE PODIDO RESPALDAR ANTES DE ACTUALIZAR - ACTUALIZACION CANCELADA

El motivo esta en los AVISOS de aqui arriba; casi siempre es falta de
espacio en disco.

No se ha tocado ni el juego ni el mundo. Una actualizacion sin copia
previa no tiene marcha atras si el mundo deja de cargar, asi que prefiero
no empezarla. Libera espacio y repite."

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

        # El '|| true' de cada asignacion no es decorativo: con `set -e` y
        # `pipefail`, un grep sin coincidencias hace fallar la asignacion entera
        # y aborta la funcion en silencio. Y el caso de "este mod no declara
        # dependencias" es exactamente el que queremos poder informar.
        while IFS= read -r info; do
            # Solo se quita el retorno de carro, NUNCA los espacios: hay Mod ID
            # que los llevan dentro. 'Run and Reload' es literalmente su ID, y
            # convertirlo en 'RunandReload' produce un mod que no carga y un
            # 'required mod not found' que parece un problema del servidor.
            modid="$(grep -iE '^[[:space:]]*id[[:space:]]*=' "$info" | head -1 | cut -d= -f2- | tr -d '\r' || true)"
            modname="$(grep -iE '^[[:space:]]*name[[:space:]]*=' "$info" | head -1 | cut -d= -f2- | tr -d '\r' || true)"
            printf '    Mod ID : %s\n' "${modid:-<sin id>}"
            printf '    Nombre : %s\n' "${modname:- }"
            printf '    Ruta   : %s\n' "${info#$wid/}"

            # Dependencias declaradas por el autor. Es la fuente autoritativa
            # cuando existe, pero muchos autores no la rellenan y solo mencionan
            # las dependencias en la descripcion del Workshop: que esto salga
            # vacio NO significa que el mod no dependa de nada.
            # El require= puede estar en el mod.info de la raiz o SOLO dentro de
            # la carpeta versionada (42/). Al mirar unicamente la raiz se
            # escapan dependencias reales: asi se nos colo LuaDigitalWatchUI, que
            # solo aparece en 42/mod.info de Realistic Temperature.
            local reqs
            reqs="$(grep -iE '^[[:space:]]*require[[:space:]]*=' "$info" | head -1 | cut -d= -f2- | tr -d '\r' | sed 's/^[\\]//' || true)"
            if [[ -n "$reqs" ]]; then
                printf '    REQUIERE: %s   <- deben ir ANTES en Mods=\n' "$reqs"
            else
                printf '    Requiere: (sin declarar en este fichero)\n'
            fi

            # Limites de version declarados por el autor. Son la razon mas
            # silenciosa de que un mod no cargue: el juego lo descarta sin decir
            # por que, y en el log solo aparece "required mod not found".
            local vmin vmax
            vmin="$(grep -iE '^[[:space:]]*versionMin[[:space:]]*=' "$info" | head -1 | cut -d= -f2- | tr -d ' \r' || true)"
            vmax="$(grep -iE '^[[:space:]]*versionMax[[:space:]]*=' "$info" | head -1 | cut -d= -f2- | tr -d ' \r' || true)"
            if [[ -n "$vmin" || -n "$vmax" ]]; then
                printf '    VERSIONES: min=%s max=%s\n' "${vmin:--}" "${vmax:--}"
            fi

            # Cualquier otro campo que el autor haya puesto y que no mostremos
            # ya: a veces avisan de incompatibilidades o de version minima.
            grep -ivE '^[[:space:]]*(id|name|require|poster|icon|description)[[:space:]]*=' "$info" \
                | grep -E '=' | sed 's/^/    · /' || true
            printf '\n'
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
    printf 'Ultimo backup : %s\n' "$(last_backup_summary)"
    printf 'Mods (workshop):\n'
    mods_status_summary | sed 's/^/    /'
    printf '\n'
}

# Compara el manifiesto local de Steam contra la API publica del Workshop y
# dice que mods estan desfasados. Misma deteccion que usa mods_watch_loop: una
# sola implementacion para el chequeo manual y para el automatico.
#
# Salida: 0 sincronizado, 1 hay desfase, 2 no se pudo consultar la API (o no
# hay mods activos que comprobar). Pensada para poder scriptarse.
cmd_check_mods() {
    local report=""
    report="$(collect_mod_status 2>/dev/null || true)"

    if [[ -z "$report" ]]; then
        log "No hay mods activos que comprobar (o no pude leer el manifiesto de Steam)."
        return 2
    fi

    printf '\n%-12s %-13s %-13s %-10s  %s\n' "ID" "LOCAL" "STEAM" "ESTADO" "TITULO"
    printf '%s\n' "$report" | while IFS=$'\t' read -r id local_ts remote_ts title verdict; do
        printf '%-12s %-13s %-13s %-10s  %s\n' \
            "$id" \
            "$(date -u -d "@${local_ts}" +%Y-%m-%d 2>/dev/null || echo "$local_ts")" \
            "$(date -u -d "@${remote_ts}" +%Y-%m-%d 2>/dev/null || echo "$remote_ts")" \
            "$verdict" "$title"
    done

    write_mods_status "$report"

    local total stale api_fail
    total="$(printf '%s\n' "$report" | grep -c . || true)"
    stale="$(printf '%s\n' "$report" | awk -F'\t' '$5=="desfasado"' | grep -c . || true)"
    api_fail="$(printf '%s\n' "$report" | awk -F'\t' '$5=="sin-datos"' | grep -c . || true)"

    printf '\nDESFASADOS: %s de %s\n' "${stale:-0}" "${total:-0}"
    (( ${api_fail:-0} > 0 )) && printf 'SIN DATOS : %s (no se pudo consultar la API para estos)\n' "${api_fail:-0}"

    (( ${stale:-0} > 0 )) && return 1
    (( ${api_fail:-0} > 0 && ${api_fail:-0} == ${total:-0} )) && return 2
    return 0
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
    check-mods) cmd_check_mods ;;
    capture-sandbox) validate_env; capture_sandbox ;;
    status)     cmd_status ;;
    shell)      exec bash ;;
    *)          exec "$@" ;;
esac
