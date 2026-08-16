#!/usr/bin/env bash
# Vigilancia de mods desfasados del Workshop, y reinicio automatico cuando el
# servidor esta vacio. Se carga con `source`, como ops.sh.
#
# El problema que resuelve: Steam actualiza los mods de los CLIENTES solo, sin
# preguntar. El servidor no (UPDATE_ON_START=false, y asi debe seguir: ver
# guard_buildid en ops.sh). En cuanto un autor publica, las versiones dejan de
# coincidir y nadie puede entrar con "La version del articulo de la workshop es
# diferente a la del servidor". Medido en docs/MODS-DESFASADOS.md: al menos 1,3
# publicaciones/dia sobre el conjunto instalado, o sea que pasa casi a diario.
#
# La solucion NO es actualizar el juego (eso lo sigue prohibiendo
# UPDATE_ON_START=false). Es simplemente REINICIAR: el propio servidor de PZ
# descarga los mods desfasados por su cuenta al arrancar (se ve en su log como
# GetItemState()=NeedsUpdate), y eso es un mecanismo totalmente independiente
# de app_update sobre el juego. Verificado tres veces en produccion: el buildid
# no cambia al reiniciar aunque los mods si se pongan al dia.
#
# Regla de oro, decision del grupo (15/08): NUNCA se reinicia con gente dentro.
# Se avisa por chat y se espera a que el servidor quede vacio solo.

# ============================================================= DETECCION ===

# Carpeta donde Steam deja los mods descargados. Los mods de PZ cuelgan del
# Workshop del juego BASE (108600), no del servidor dedicado (STEAM_APP_ID,
# 380870): por eso se prueban las dos rutas, igual que hace cmd_mods.
workshop_dir() {
    local wsdir="${PZ_DIR}/steamapps/workshop/content/380870"
    [[ -d "$wsdir" ]] || wsdir="${PZ_DIR}/steamapps/workshop/content/108600"
    printf '%s' "$wsdir"
}

# IDs realmente activos: interseccion de lo configurado (PZ_WORKSHOP_ITEMS,
# separado por ';') con lo que hay de verdad descargado en disco.
#
# A proposito NO se leen los IDs escaneando el .acf con una expresion regular:
# ese fichero tambien contiene numeros de manifiesto de 10 digitos que pueden
# coincidir con IDs de Workshop reales y colarse como falsos positivos (pasO
# de verdad al escribir cmd_mods). Los directorios de contenido no tienen esa
# ambiguedad: si esta ahi, es un Mod ID.
active_workshop_ids() {
    local wsdir; wsdir="$(workshop_dir)"
    [[ -d "$wsdir" ]] || return 0

    local -a raw
    IFS=';' read -ra raw <<< "${PZ_WORKSHOP_ITEMS:-}"

    local id
    for id in "${raw[@]}"; do
        id="${id//[^0-9]/}"
        [[ -n "$id" && -d "${wsdir}/${id}" ]] && printf '%s\n' "$id"
    done

    # Sin esto, el codigo de salida de la funcion queda al azar de si el
    # ULTIMO id de la lista resulto estar descargado o no (el && de arriba
    # devuelve 1 cuando no lo esta): un "no coincide" normal, no un error,
    # pero un llamador que use $(...) sin protegerlo (como una prueba, o un
    # futuro caso de uso que no sea el mapfile+process-substitution de
    # collect_mod_status) abortaria en seco por set -e sin ningun mensaje.
    return 0
}

# Fecha de la ultima actualizacion QUE TENEMOS INSTALADA, para un id concreto.
#
# El .acf tiene DOS secciones con pinta parecida: "WorkshopItemsInstalled" (lo
# que de verdad esta en disco) y "WorkshopItemDetails" (metadatos de la
# suscripcion, con SU PROPIO "timeupdated" ademas de un "latest_timeupdated").
# Verificado en el manifiesto real: 24 mods dan 72 apariciones de la cadena
# "timeupdated" (3 por mod: una de instalado + dos de la otra seccion), asi que
# un grep ingenuo sobre el fichero entero cuenta lo que no debe.
#
# Este awk evita la trampa por construccion, no por suerte: cuenta llaves para
# saber en que seccion y a que profundidad esta, y solo mira dentro del bloque
# de "WorkshopItemsInstalled". La comparacion de campo es por IGUALDAD exacta
# ($1 == '"timeupdated"'), no por substring, asi que tampoco pica con
# "latest_timeupdated". Sin expresiones regulares con captura (match() de 3
# argumentos es una extension de gawk; esta imagen no garantiza gawk), asi que
# se apoya solo en el troceo por espacios que hace awk de serie.
local_timeupdated() {
    local id="$1" acf
    # El '|| true' no es decorativo (leccion ya aprendida en cmd_mods, ver
    # run.sh): con set -e y pipefail, un glob de ls sin coincidencias hace
    # fallar la asignacion entera y aborta la funcion antes de llegar al
    # siguiente [[ ]], que es justo el que sabe manejar el caso "no hay acf".
    acf="$(ls "${PZ_DIR}"/steamapps/workshop/appworkshop_*.acf 2>/dev/null | head -1 || true)"
    [[ -n "$acf" && -f "$acf" ]] || return 0

    awk -v want="\"${id}\"" '
        /"WorkshopItemsInstalled"/ { in_installed = 1; depth = 0; next }
        in_installed && /^[\t ]*\{/ {
            depth++
            next
        }
        in_installed && /^[\t ]*\}/ {
            if (depth == 2) target = 0
            depth--
            if (depth <= 0) in_installed = 0
            next
        }
        in_installed && depth == 1 && $1 == want { target = 1; next }
        in_installed && target && depth == 2 && $1 == "\"timeupdated\"" {
            gsub(/"/, "", $2)
            print $2
            exit
        }
    ' "$acf"
}

# Un UNICO POST con todos los IDs a la API publica de Steam. Nada de una
# llamada por mod: con 24 mods serian 24 rondas de red por cada chequeo, y
# ademas WebFetch/curl contra esta API concreta responde con 429 bastante
# rapido si se abusa (aprendido investigando mods de sincronizacion).
remote_updates_json() {
    (( $# > 0 )) || return 0

    local -a data=(-d "itemcount=$#")
    local i=0 id
    for id in "$@"; do
        data+=(-d "publishedfileids[${i}]=${id}")
        i=$(( i + 1 ))
    done

    curl -fsS --max-time "${MODS_API_TIMEOUT:-30}" \
        -X POST 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' \
        "${data[@]}"
}

# Junta local + remoto en una tabla, una linea por mod activo:
#   id \t local_ts \t remote_ts \t titulo \t veredicto
# veredicto: ok | desfasado | sin-datos
#
# "sin-datos" (API caida, id retirado del Workshop, o timeupdated ilegible) NO
# es lo mismo que "ok": un fallo al medir nunca debe traducirse en "todo bien",
# el mismo principio que ya usa la guarda de espacio de los backups en ops.sh.
collect_mod_status() {
    local -a ids=()
    mapfile -t ids < <(active_workshop_ids)
    (( ${#ids[@]} > 0 )) || return 0

    local api_json="" api_rc=0
    api_json="$(remote_updates_json "${ids[@]}")" || api_rc=$?

    local id local_ts remote_ts title line verdict
    for id in "${ids[@]}"; do
        local_ts="$(local_timeupdated "$id" || true)"
        remote_ts="" title=""

        if (( api_rc == 0 )) && [[ -n "$api_json" ]]; then
            # El gsub del titulo no es cosmetico: el informe es TSV y los
            # titulos los escribe el autor del mod. Un tabulador dentro del
            # titulo desplazaria el veredicto a un sexto campo y los
            # `awk -F'\t' '$5=="desfasado"'` de todo el flujo dejarian de
            # contar ese mod desfasado, sin ningun error. Se aplasta a espacio
            # en origen y el problema no puede existir.
            line="$(printf '%s' "$api_json" | jq -r --arg id "$id" '
                .response.publishedfiledetails[]?
                | select(.publishedfileid == $id and .result == 1 and ((.time_updated // 0) != 0))
                | "\(.time_updated)\t\((.title // "?") | gsub("[\\t\\r\\n]+"; " "))"
            ' 2>/dev/null | head -1 || true)"
            if [[ -n "$line" ]]; then
                remote_ts="${line%%$'\t'*}"
                title="${line#*$'\t'}"
            fi
        fi

        # Gancho de pruebas: forzar el veredicto de un id sin depender de la
        # red, para el simulacro y para selftest-modwatch.sh.
        if [[ -n "${MODS_FORCE_STALE:-}" && ",${MODS_FORCE_STALE}," == *",${id},"* ]]; then
            verdict="desfasado"
        elif [[ -z "$local_ts" || -z "$remote_ts" ]]; then
            verdict="sin-datos"
        elif (( remote_ts > local_ts )); then
            verdict="desfasado"
        else
            verdict="ok"
        fi

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$id" "${local_ts:-0}" "${remote_ts:-0}" "${title:-<sin titulo>}" "$verdict"
    done
}

# ================================================================ ESTADO ===

# Se computa en cada uso, no una vez al cargar el fichero: DATA_DIR es fijo en
# produccion (ENV del Dockerfile), pero cachearlo en una variable global rompe
# el patron que ya usa el resto del proyecto (backup_prefix() en ops.sh) y es
# justo lo que habria hecho fragiles las pruebas, que reasignan DATA_DIR por
# caso. Coste de recalcularlo: un printf, nada.
mods_status_file() {
    printf '%s/.pz-mods-status' "${DATA_DIR}"
}

# Sobrescribe el resumen del ULTIMO chequeo, conservando la linea de auditoria
# del ultimo reinicio automatico si la habia (esa la escribe note_mods_restart,
# no esta funcion, y un chequeo cada 30 min no debe borrarla).
write_mods_status() {
    local report="$1" total stale prev_restart="" f
    f="$(mods_status_file)"

    total="$(printf '%s\n' "$report" | grep -c . || true)"
    stale="$(printf '%s\n' "$report" | awk -F'\t' '$5=="desfasado"' | grep -c . || true)"

    [[ -f "$f" ]] && \
        prev_restart="$(grep '^ultimo-reinicio-automatico:' "$f" 2>/dev/null || true)"

    {
        printf 'chequeo: %s UTC\n' "$(date -u +'%Y-%m-%d %H:%M:%S')"
        printf 'desfasados: %s de %s\n' "${stale:-0}" "${total:-0}"
        if (( ${stale:-0} > 0 )); then
            printf '%s\n' "$report" | awk -F'\t' '$5=="desfasado"{print "  - " $4 " (id " $1 ")"}'
        fi
        # 'if', no '[[ ]] &&': la ULTIMA linea del grupo decide su codigo de
        # salida, y sin reinicio previo que conservar (caso normal, no un
        # error) un '&&' suelto deja el grupo en 1 -> el '&& mv' de abajo se
        # salta en silencio y el fichero jamas se escribe. Detectado por
        # selftest-modwatch.sh, no a ojo.
        if [[ -n "$prev_restart" ]]; then
            printf '%s\n' "$prev_restart"
        fi
    } > "${f}.tmp.${BASHPID}" && mv "${f}.tmp.${BASHPID}" "$f"
}

# Registra (o reemplaza) la linea de auditoria del ultimo reinicio automatico,
# sin tocar el resto del fichero. Mismo patron leer-filtrar-reescribir que
# capture_sandbox en ops.sh.
#
# El sufijo BASHPID del temporal (aqui y en write_mods_status) existe porque
# escriben procesos DISTINTOS: el vigilante, el verificador post-reinicio (en
# segundo plano) y un check-mods manual pueden coincidir. Con un `.tmp` fijo,
# dos escritores concurrentes se pisan el temporal y el mv del segundo muere
# por set -e. Y es BASHPID, no $$: $$ vale lo mismo en todos los subshells
# hijos del mismo run.sh, o sea que no distinguiria justo a los que hay que
# distinguir.
note_mods_restart() {
    local text="$1" f
    f="$(mods_status_file)"
    {
        [[ -f "$f" ]] && grep -v '^ultimo-reinicio-automatico:' "$f"
        printf 'ultimo-reinicio-automatico: %s\n' "$text"
    } > "${f}.tmp.${BASHPID}" && mv "${f}.tmp.${BASHPID}" "$f"
}

# Para cmd_status: sin red, solo lee lo que ya se escribio.
mods_status_summary() {
    local f; f="$(mods_status_file)"
    [[ -f "$f" ]] || { printf 'sin comprobar todavia'; return 0; }
    cat "$f"
}

# ============================================================== VIGILANTE ===

# Cuantos jugadores hay conectados ahora mismo, o cadena vacia si no se puede
# saber (RCON no responde). Vacio NUNCA se trata como 0: un fallo de medicion
# no debe poder disparar un reinicio con gente dentro sin que lo sepamos.
player_count() {
    local out
    out="$(rcon_cmd players 2>/dev/null | head -1 || true)"
    [[ "$out" =~ \(([0-9]+)\) ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# Bucle de fondo, gemelo de periodic_backup_loop. Vive todo el contenedor:
# sigue vigilando aunque el propio bucle provoque un reinicio del mundo (no
# hace `return` al reiniciar, solo `continue`), igual que el bucle de backups
# periodicos no le importa que el servidor se haya reiniciado por su cuenta.
mods_watch_loop() {
    local mins="${MODS_CHECK_INTERVAL_MINUTES:-30}"
    local secs=$(( mins * 60 ))
    # Gancho para verificar el bucle sin esperar media hora de verdad.
    [[ -n "${MODS_CHECK_INTERVAL_SECONDS:-}" ]] && secs="$MODS_CHECK_INTERVAL_SECONDS"

    (( secs > 0 )) || { log "Vigilancia de mods desfasados desactivada."; return 0; }

    local empty_poll="${MODS_EMPTY_POLL_SECONDS:-120}"
    local pending=0 stale_key="" last_stale_key=""

    log "Vigilancia de mods cada ${secs}s. Si hay desfase, avisa y reinicia SOLO cuando el servidor quede vacio."

    while true; do
        if (( pending )); then sleep "$empty_poll"; else sleep "$secs"; fi
        (( STOPPING )) && break

        zomboid_running && rcon_ready || continue

        if (( ! pending )); then
            local report=""
            report="$(collect_mod_status 2>/dev/null || true)"
            [[ -n "$report" ]] || continue

            write_mods_status "$report"

            local stale=""
            stale="$(printf '%s\n' "$report" | awk -F'\t' '$5=="desfasado"{print $1}')"

            if [[ -z "$stale" ]]; then
                # Todo al dia: el backoff se LIMPIA aqui, y este reset no es
                # opcional. Sin el, la segunda actualizacion legitima del mismo
                # mod quedaria bloqueada para siempre: CleanUI publico dos veces
                # en 24 horas, asi que "el mismo conjunto otra vez" es el caso
                # MAS probable, no una rareza. (Fallo real cazado en revision:
                # la primera version no reseteaba nunca y la funcion se
                # autodesactivaba tras su primer uso.)
                #
                # Eso si: solo se resetea si la API respondio de verdad (algun
                # veredicto distinto de sin-datos). Un apagon de la API deja
                # todos los mods en sin-datos y "0 desfasados", y eso NO
                # significa que un conjunto atascado se haya curado.
                if printf '%s\n' "$report" | awk -F'\t' '$5!="sin-datos"{ok=1} END{exit !ok}'; then
                    last_stale_key=""
                fi
                continue
            fi

            # La clave del backoff lleva el timestamp REMOTO ademas del id:
            # distingue "el reinicio no consiguio sincronizarlo" (mismo id y
            # misma fecha publicada -> no insistir) de "el autor publico OTRA
            # version" (mismo id, fecha nueva -> intento legitimo nuevo, aunque
            # llegue antes de que el chequeo de curacion haya reseteado nada).
            stale_key="$(printf '%s\n' "$report" \
                | awk -F'\t' '$5=="desfasado"{print $1 ":" $3}' | sort | tr '\n' ',')"

            if [[ "$stale_key" == "$last_stale_key" ]]; then
                warn "Los mismos mods siguen desfasados tras el ultimo reinicio automatico."
                warn "  No reintento solo: probablemente un mod se retiro del Workshop o no"
                warn "  se puede sincronizar. Revisa a mano (./scripts/check-mods.sh)."
                continue
            fi

            pending=1
            local titulos=""
            titulos="$(printf '%s\n' "$report" \
                | awk -F'\t' '$5=="desfasado"{print $4}' \
                | tr -d '"' | tr '\n' ',' | sed 's/,/, /g; s/, $//')"
            log "Mods desfasados: ${titulos}. Esperando a que el servidor quede vacio para reiniciar."
            rcon_cmd servermsg \
                "\"Hay mods actualizados en Steam (${titulos}). El servidor se reiniciara solo en cuanto quede vacio; nadie nuevo podra entrar hasta entonces.\"" \
                >/dev/null 2>&1 || true
            continue
        fi

        local n; n="$(player_count || true)"
        [[ "$n" == "0" ]] || continue

        log "Servidor vacio con mods desfasados (${stale_key%,}): reinicio automatico."
        touch "$RESTART_FLAG"
        note_mods_restart "$(date -u +'%Y-%m-%d %H:%M:%S') UTC - solicitado (mods: ${stale_key%,})"
        last_stale_key="$stale_key"
        pending=0
        graceful_shutdown "$SHUTDOWN_TIMEOUT" || true
        # Deliberadamente NO se sale del bucle: se sigue vigilando despues del
        # reinicio, exactamente igual que antes de el.
    done
}

# Se llama UNA vez, en segundo plano, justo despues de relanzar el servidor
# tras un reinicio por mods. No bloquea el bucle principal (por eso quien la
# invoca la manda con `&`): tarda hasta wait_for_ready(600) y el contenedor
# debe seguir pudiendo atender una senal de parada real mientras tanto.
verify_after_mods_restart() {
    log "Verificando el arranque tras el reinicio automatico por mods..."

    # 600 y no menos, a proposito: este arranque es justo el que DESCARGA los
    # mods actualizados, y uno grande en una linea lenta tarda. Un plazo corto
    # escribiria "FALLO: no respondio" en la auditoria sobre un servidor que
    # arranca bien al cuarto minuto — un falso rojo en el peor sitio. Y no
    # retrasa la deteccion de un crash real: wait_for_ready corta solo en
    # cuanto ve que el proceso ya no existe.
    if ! wait_for_ready 600; then
        note_mods_restart "$(date -u +'%Y-%m-%d %H:%M:%S') UTC - FALLO: no respondio tras el reinicio. Backup de resguardo: $(latest_backup_name pre-mods)"
        warn "El servidor NO respondio tras el reinicio automatico de mods."
        warn "  Backup de resguardo mas reciente: $(latest_backup_name pre-mods)"
        warn "  Runbook: docs/OPERACIONES.md, 'un mod se actualizo a peor'."
        return 1
    fi

    local logf missing=0 errores=0
    logf="$(ls -t "${DATA_DIR}"/Logs/*_DebugLog-server.txt 2>/dev/null | head -1 || true)"
    if [[ -n "$logf" ]]; then
        missing="$(grep -c 'required mod not found' "$logf" 2>/dev/null || true)"
        # 'f:0' es el marcador de frame que ya usan docs/incidencias/*.md para
        # descartar el ruido de la carga (animaciones, saneado de nombres de
        # contenedor...): decenas de ERROR ahi son normales en CUALQUIER
        # arranque, con o sin mods de por medio. Contarlos todos sin distinguir
        # convertiria este numero en ruido constante en vez de senal; contado
        # asi, el criterio es el mismo "0 ERROR fuera del frame de carga" que
        # ya usa el resto del proyecto. Verificado con un reinicio real: 148
        # ERROR totales, 148 con 'f:0', 0 fuera de el.
        errores="$(grep 'ERROR' "$logf" 2>/dev/null | grep -vc 'f:0' || true)"
    fi

    if (( ${missing:-0} > 0 )); then
        note_mods_restart "$(date -u +'%Y-%m-%d %H:%M:%S') UTC - AVISO: ${missing} 'required mod not found' tras el reinicio. Backup de resguardo: $(latest_backup_name pre-mods)"
        warn "Tras el reinicio automatico hay ${missing} 'required mod not found' en el log."
        warn "  Puede ser un mod que cambio su cadena de dependencias al actualizar."
        warn "  Runbook: docs/OPERACIONES.md, 'un mod se actualizo a peor'."
    else
        note_mods_restart "$(date -u +'%Y-%m-%d %H:%M:%S') UTC - OK: operativo, 0 mods faltantes, ${errores:-0} ERROR fuera del frame de carga."
        log "Verificacion post-reinicio OK (0 mods faltantes, ${errores:-0} ERROR fuera del frame de carga)."
    fi
}

# Nombre del backup mas reciente con la etiqueta dada, o un texto honesto si
# no hay ninguno. Se usa en los avisos para senalar el punto de restauracion
# sin obligar a quien lea el log a construir el patron de nombre a mano.
latest_backup_name() {
    local label="$1" f
    f="$(ls -1t "${BACKUP_DIR}/$(backup_prefix)"-*-"${label}".tar.zst 2>/dev/null | head -1 || true)"
    [[ -n "$f" ]] && basename "$f" || printf '<no encontrado>'
}
