#!/usr/bin/env bash
# Operaciones sobre la instalacion y los datos: instalar, renderizar config,
# parchear memoria, respaldar y restaurar. Se carga con `source`.

# ================================================================ INSTALL ===

install_game() {
    local first_install=1
    game_installed && first_install=0

    if (( first_install )); then
        log "Instalando Project Zomboid Dedicated Server (app ${STEAM_APP_ID})..."
        log "Son ~7,5 GB; la primera vez tarda un rato largo."
    else
        log "Comprobando/reparando la instalacion (app ${STEAM_APP_ID})..."
    fi

    # Dos detalles que cuestan una tarde si no se saben:
    #
    # 1. +force_install_dir tiene que ir ANTES de +login. Si va despues,
    #    SteamCMD avisa con "Please use force_install_dir before logon!" y te
    #    instala en ~/Steam en vez de donde le pediste.
    #
    # 2. `validate` sobre un directorio vacio falla con el mensaje enganoso
    #    "Failed to install app '380870' (Missing configuration)". No es un
    #    problema de permisos ni de red: SteamCMD no puede validar lo que aun
    #    no existe. Por eso solo validamos cuando ya hay una instalacion.
    local -a update_args=(+app_update "$STEAM_APP_ID")
    (( first_install )) || update_args+=(validate)

    steamcmd \
        +force_install_dir "$PZ_DIR" \
        +login anonymous \
        "${update_args[@]}" \
        +quit || warn "SteamCMD salio con error; compruebo el resultado igualmente."

    # Reintento unico: la primera conexion de SteamCMD a veces se queda sin
    # appinfo y falla de forma transitoria.
    if [[ ! -f "${PZ_DIR}/start-server.sh" ]]; then
        warn "La instalacion no aparecio a la primera. Reintento..."
        steamcmd \
            +force_install_dir "$PZ_DIR" \
            +login anonymous \
            +app_update "$STEAM_APP_ID" \
            +quit || true
    fi

    [[ -f "${PZ_DIR}/start-server.sh" ]] || die_loud \
"SteamCMD termino pero no existe ${PZ_DIR}/start-server.sh.
La instalacion no ha ido bien. Revisa el log de SteamCMD mas arriba."

    chmod +x "${PZ_DIR}"/*.sh "${PZ_DIR}/ProjectZomboid64" 2>/dev/null || true

    # La Steam API busca steamclient.so en ~/.steam/sdk64 ademas de en el
    # directorio de instalacion. Sin este enlace la integracion con Steam falla
    # de formas poco obvias: lo notaras en la fase 3, cuando el servidor no
    # consiga descargar los mods del Workshop.
    mkdir -p "${HOME}/.steam/sdk64"
    ln -sf "${PZ_DIR}/steamclient.so" "${HOME}/.steam/sdk64/steamclient.so" 2>/dev/null || true

    log "Instalado. buildid: $(installed_buildid)"
}

game_installed() {
    [[ -f "${PZ_DIR}/start-server.sh" ]]
}

# ========================================================== GUARDA VERSION ===

# El mecanismo antifallo central del proyecto.
#
# Escenario que evita: Steam publica 42.21 un martes, alguien reinicia el
# servidor el miercoles, el binario se actualiza sin que nadie lo decida y el
# mundo de 42.20 se abre con un motor distinto. Ese es el camino habitual hacia
# un guardado corrupto, y es silencioso: no falla nada visible hasta que faltan
# contenedores o el mapa tiene celdas rotas.
#
# Por eso el arranque normal ni siquiera llama a app_update, y ademas
# comprobamos que el binario presente sea el mismo con el que se venia jugando.
guard_buildid() {
    local installed recorded
    installed="$(installed_buildid)"
    recorded="$(recorded_buildid)"

    if [[ -z "$installed" ]]; then
        warn "No se pudo leer el buildid del manifiesto de Steam; sigo sin comprobacion."
        return 0
    fi

    if [[ -z "$recorded" ]]; then
        log "Primer arranque con este mundo. Fijando version de referencia: ${installed}"
        record_buildid "$installed"
        return 0
    fi

    if [[ "$installed" == "$recorded" ]]; then
        log "Version verificada: buildid ${installed}"
        return 0
    fi

    if is_true "${ALLOW_BUILD_CHANGE:-false}"; then
        warn "Cambio de version aceptado explicitamente: ${recorded} -> ${installed}"
        do_backup "pre-update"
        record_buildid "$installed"
        return 0
    fi

    die_loud \
"CAMBIO DE VERSION DEL JUEGO DETECTADO - ARRANQUE CANCELADO

El mundo guardado se venia usando con el buildid ${recorded}
pero la instalacion actual es el buildid ${installed}.

Abrir un mundo con un motor distinto al que lo creo es una de las
formas mas habituales de corromper un guardado, asi que no arranco.

Si el cambio es intencionado (has actualizado a proposito):
    ./scripts/update-server.sh
que hace backup antes de nada y luego autoriza el cambio.

Si NO lo es, probablemente se colo un app_update. Restaura la version
anterior o recupera el ultimo backup con ./scripts/restore.sh"
}

# ================================================================= CONFIG ===

# Genera la configuracion de referencia arrancando el servidor una vez con un
# nombre desechable. La gracia es partir de las claves REALES que escribe la
# 42.20 instalada, en lugar de una plantilla copiada de una guia de internet
# que puede estar desactualizada o ser directamente de Build 41.
#
# Usa el nombre `_bootstrap` para que el mundo de usar y tirar que se crea de
# paso no tenga nada que ver con el mundo de verdad.
bootstrap_reference() {
    local bname="_bootstrap"
    local sdir="${DATA_DIR}/Server"
    local ref="${CONFIG_DIR}/reference"

    if [[ ! -w "$CONFIG_DIR" ]]; then
        die_loud \
"Hace falta generar la configuracion de referencia, pero /config esta
montado de solo lectura. Monta ./config con permiso de escritura."
    fi

    log "Generando configuracion de referencia desde el servidor instalado..."
    mkdir -p "$sdir" "$ref"
    rm -f "${sdir}/${bname}"*

    # Sembramos RCON para poder hablar con el y apagarlo limpiamente. El
    # servidor rellenara todas las demas claves con sus valores por defecto,
    # que es justo lo que queremos capturar.
    cat > "${sdir}/${bname}.ini" <<EOF
RCONPort=${PZ_RCON_PORT}
RCONPassword=${PZ_RCON_PASSWORD}
EOF

    launch_server "$bname"

    log "Esperando a que el servidor de bootstrap termine de arrancar..."
    local waited=0
    while (( waited < 600 )); do
        if rcon_ready; then
            log "Servidor de bootstrap operativo tras ${waited}s."
            break
        fi
        if ! zomboid_running && (( waited > 30 )); then
            die_loud "El servidor de bootstrap murio durante el arranque. Revisa el log."
        fi
        sleep 5
        waited=$(( waited + 5 ))
    done

    if (( waited >= 600 )); then
        warn "El bootstrap no respondio por RCON en 10 min; intento apagarlo igualmente."
    fi

    graceful_shutdown 240

    # Capturamos lo que el juego escribio de verdad.
    [[ -f "${sdir}/${bname}.ini" ]] && cp "${sdir}/${bname}.ini" "${ref}/server.ini"
    [[ -f "${sdir}/${bname}_SandboxVars.lua" ]] && cp "${sdir}/${bname}_SandboxVars.lua" "${ref}/SandboxVars.lua"
    [[ -f "${sdir}/${bname}_spawnregions.lua" ]] && cp "${sdir}/${bname}_spawnregions.lua" "${ref}/spawnregions.lua"
    installed_buildid > "${ref}/buildid"

    cat > "${ref}/README.md" <<'EOF'
# config/reference

Ficheros **generados** por el propio servidor instalado. No los edites a mano:
se regeneran cada vez que se hace un bootstrap y perderias los cambios.

Sirven para dos cosas:

1. Ser el punto de partida honesto de `config/server.ini.tmpl` — son las claves
   reales de la version instalada, no las de una guia de internet.
2. Detectar que introduce cada actualizacion del juego. Tras actualizar, se
   regeneran y el `git diff` de esta carpeta muestra exactamente que ajustes
   nuevos hay que decidir.
EOF

    # El mundo de usar y tirar se va. Nunca ha tenido nada dentro.
    rm -rf "${DATA_DIR}/Saves/Multiplayer/${bname}" "${sdir}/${bname}"*
    rm -f "${DATA_DIR}/db/${bname}.db"

    log "Configuracion de referencia lista en config/reference/"
}

# Claves del INI que pasan a ser variables de entorno en la plantilla. El resto
# se queda con el valor por defecto del juego y se decidira en la fase 2.
declare -a TEMPLATED_KEYS=(
    "PublicName:PZ_PUBLIC_NAME"
    "PublicDescription:PZ_PUBLIC_DESCRIPTION"
    "Public:PZ_PUBLIC"
    "Password:PZ_SERVER_PASSWORD"
    "MaxPlayers:PZ_MAX_PLAYERS"
    "DefaultPort:PZ_PORT"
    "UDPPort:PZ_UDP_PORT"
    "RCONPort:PZ_RCON_PORT"
    "RCONPassword:PZ_RCON_PASSWORD"
    "Mods:PZ_MODS"
    "WorkshopItems:PZ_WORKSHOP_ITEMS"
    "Map:PZ_MAP"
    "PVP:PZ_PVP"
    "Open:PZ_OPEN"
    "ServerWelcomeMessage:PZ_WELCOME_MESSAGE"
)

# Crea config/server.ini.tmpl la primera vez, a partir de la referencia.
seed_template() {
    local ref="${CONFIG_DIR}/reference/server.ini"
    local tmpl="${CONFIG_DIR}/server.ini.tmpl"

    [[ -f "$ref" ]] || die_loud "Falta ${ref}; hay que hacer bootstrap primero."

    log "Creando ${tmpl} a partir de la referencia..."

    {
        cat <<'EOF'
# ============================================================================
# Zroyecto Pombie - plantilla de configuracion del servidor
# ============================================================================
#
# FUENTE DE VERDAD. Este fichero se renderiza dentro del contenedor en cada
# arranque hacia Zomboid/Server/<nombre>.ini. El flujo es de una sola direccion:
# repo -> contenedor. Nada de lo que el servidor escriba en runtime vuelve aqui.
#
# Los ${VALORES} se sustituyen con las variables del .env.
# El resto son los valores por defecto de la version instalada; se iran
# ajustando en la fase 2 de configuracion.
#
# Tras editar: docker compose restart pz
# Los cambios de ajustes NO tocan los guardados. Pero si el cambio es de
# riesgo (mods, mapas), pruebalo antes en staging: ./scripts/stage.sh
# ============================================================================

EOF
        # Sustituimos los valores de las claves elegidas por sus variables.
        local line key
        while IFS= read -r line; do
            if [[ "$line" =~ ^([A-Za-z0-9_]+)= ]]; then
                key="${BASH_REMATCH[1]}"
                local replaced=0 pair k v
                for pair in "${TEMPLATED_KEYS[@]}"; do
                    k="${pair%%:*}"; v="${pair##*:}"
                    if [[ "$key" == "$k" ]]; then
                        printf '%s=${%s}\n' "$key" "$v"
                        replaced=1
                        break
                    fi
                done
                (( replaced )) || printf '%s\n' "$line"
            else
                printf '%s\n' "$line"
            fi
        done < "$ref"
    } > "$tmpl"

    log "Plantilla creada. Revisala y commiteala."
}

# Renderiza repo -> runtime. Idempotente y unidireccional.
render_config() {
    local sdir="${DATA_DIR}/Server"
    local out="${sdir}/${PZ_SERVER_NAME}.ini"
    local tmpl="${CONFIG_DIR}/server.ini.tmpl"
    local last="${DATA_DIR}/.pz-last-render.ini"

    mkdir -p "$sdir"

    [[ -f "$tmpl" ]] || die_loud \
"No existe ${tmpl}.
Ejecuta primero el bootstrap:  ./scripts/bootstrap.sh"

    # Si el servidor toco el INI por su cuenta respecto a lo que renderizamos
    # (tipicamente porque una actualizacion del juego anadio claves nuevas),
    # queremos enterarnos antes de pisarlo. Perder ajustes en silencio es
    # justo lo que este proyecto intenta evitar.
    if [[ -f "$out" && -f "$last" ]] && ! diff -q "$out" "$last" >/dev/null 2>&1; then
        warn "El INI en runtime difiere de lo que renderizamos la ultima vez."
        warn "Suele significar que el juego anadio claves nuevas. Diferencias:"
        diff "$last" "$out" | sed 's/^/    /' >&2 || true
        warn "Incorpora lo que te interese a config/server.ini.tmpl."
        cp "$out" "${CONFIG_DIR}/reference/server.ini.runtime" 2>/dev/null || true
    fi

    # Lista explicita de variables a sustituir, para que envsubst no toque
    # ningun otro '$' que aparezca en el fichero.
    local varlist
    varlist="$(compgen -v | grep '^PZ_' | sed 's/^/$/' | tr '\n' ' ')"

    envsubst "$varlist" < "$tmpl" > "${out}.tmp"
    mv "${out}.tmp" "$out"
    cp "$out" "$last"

    # SandboxVars y spawnregions son Lua: se copian tal cual.
    if [[ -f "${CONFIG_DIR}/SandboxVars.lua" ]]; then
        cp "${CONFIG_DIR}/SandboxVars.lua" "${sdir}/${PZ_SERVER_NAME}_SandboxVars.lua"
    fi
    if [[ -f "${CONFIG_DIR}/spawnregions.lua" ]]; then
        cp "${CONFIG_DIR}/spawnregions.lua" "${sdir}/${PZ_SERVER_NAME}_spawnregions.lua"
    fi

    log "Configuracion renderizada -> Server/${PZ_SERVER_NAME}.ini"
}

# ================================================================= MEMORIA ===

# Pasar -Xmx por linea de comandos no sirve: el lanzador de PZ construye los
# argumentos del JVM a partir de este JSON e ignora lo que le llegue por fuera.
# Es un fallo silencioso clasico: crees que el servidor tiene 8 GB y esta
# corriendo con los 2 GB por defecto hasta que empieza a petar bajo carga.
patch_memory() {
    local f="${PZ_DIR}/ProjectZomboid64.json"

    if [[ ! -f "$f" ]]; then
        warn "No existe ${f}; no puedo fijar la RAM. Revisa la instalacion."
        return 0
    fi

    jq --arg xmx "-Xmx${PZ_MEMORY}" --arg xms "-Xms${PZ_MEMORY_MIN}" '
        .vmArgs = (
            ((.vmArgs // []) | map(select(
                (type == "string") and ((startswith("-Xmx") or startswith("-Xms")) | not)
            ))) + [$xms, $xmx]
        )
    ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"

    log "RAM del JVM fijada: ${PZ_MEMORY_MIN} inicial / ${PZ_MEMORY} maxima"
}

# ================================================================= BACKUPS ===

# Etiquetas que la rotacion puede borrar. Todo lo demas (pre-update,
# pre-restore, manual) se conserva indefinidamente: son justo los backups que
# quieres tener cuando algo ha salido mal.
ROTATABLE_LABELS="prestart periodic"

do_backup() {
    local label="${1:-manual}"
    local stamp; stamp="$(date -u +%Y%m%d-%H%M%S)"
    local out="${BACKUP_DIR}/pz-${PZ_SERVER_NAME}-${stamp}-${label}.tar.zst"

    mkdir -p "$BACKUP_DIR"

    # Si el servidor esta vivo, forzamos un guardado antes de empaquetar. Sin
    # esto capturariamos el estado del ultimo autosave, o peor, un mundo a
    # medio escribir.
    if zomboid_running && rcon_ready; then
        log "Forzando guardado antes del backup..."
        rcon_cmd save >/dev/null 2>&1 || warn "El 'save' por RCON no confirmo."
        sleep 5
    fi

    local -a items=()
    local candidate
    for candidate in Saves db Server .pz-buildid; do
        [[ -e "${DATA_DIR}/${candidate}" ]] && items+=("$candidate")
    done

    if (( ${#items[@]} == 0 )); then
        warn "No hay nada que respaldar todavia; me salto el backup."
        return 0
    fi

    log "Respaldando (${label}): ${items[*]}"
    tar --use-compress-program='zstd -6 -T0' \
        -cf "$out" -C "$DATA_DIR" "${items[@]}"

    log "Backup listo: $(basename "$out") ($(du -h "$out" | cut -f1))"
    rotate_backups
}

rotate_backups() {
    local keep="${BACKUP_KEEP:-20}"
    local label

    for label in $ROTATABLE_LABELS; do
        local -a files
        mapfile -t files < <(ls -1t "${BACKUP_DIR}"/pz-*-"${label}".tar.zst 2>/dev/null || true)
        (( ${#files[@]} > keep )) || continue
        local i
        for (( i = keep; i < ${#files[@]}; i++ )); do
            log "Rotacion: borrando $(basename "${files[$i]}")"
            rm -f "${files[$i]}"
        done
    done
}

do_restore() {
    local file="${1:-}"

    [[ -n "$file" ]] || die_loud "Uso: restore <fichero.tar.zst>"

    # Aceptamos ruta absoluta o solo el nombre dentro de /backups.
    [[ -f "$file" ]] || file="${BACKUP_DIR}/${file}"
    [[ -f "$file" ]] || die_loud "No encuentro el backup: ${1}"

    if zomboid_running; then
        die_loud \
"El servidor esta corriendo. Restaurar por debajo de un servidor vivo
destruiria los datos. Para el servidor primero:  docker compose down"
    fi

    log "Restaurando desde $(basename "$file")"

    # Antes de pisar nada, respaldamos lo que hay. Si la restauracion resulta
    # ser el error, esto es lo unico que permite deshacerla.
    do_backup "pre-restore"

    # Apartar en vez de borrar: si la extraccion falla a medias, el estado
    # anterior sigue existiendo y es recuperable a mano.
    local aside="${DATA_DIR}/.pre-restore-$(date -u +%Y%m%d-%H%M%S)"
    mkdir -p "$aside"
    local d
    for d in Saves db Server .pz-buildid; do
        [[ -e "${DATA_DIR}/${d}" ]] && mv "${DATA_DIR}/${d}" "${aside}/"
    done

    tar --use-compress-program='zstd -d' -xf "$file" -C "$DATA_DIR"

    log "Restauracion completada."
    log "El estado anterior quedo apartado en $(basename "$aside") por si acaso."
    log "Borralo cuando hayas comprobado que el mundo restaurado carga bien."
}
