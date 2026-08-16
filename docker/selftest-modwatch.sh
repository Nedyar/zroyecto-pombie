#!/usr/bin/env bash
# Pruebas de la deteccion y el reinicio automatico de mods desfasados.
#
# Mismo espiritu que selftest-backups.sh: un mecanismo de seguridad que nunca
# se ha visto funcionar es una suposicion, no una salvaguarda. Nada de red de
# verdad (curl se falsea siempre) ni de tiempos reales de un servidor (RCON y
# el apagado seguro tambien se falsean). Los ficheros .acf son de mentira, en
# directorios temporales propios.
#
#   ./docker/selftest-modwatch.sh                 # desde el host
#   docker compose run --rm --no-deps pz /docker/selftest-modwatch.sh
#
# OJO de portabilidad: el contenedor corre `mawk`, no gawk (comprobado a
# proposito antes de escribir esto). local_timeupdated() en modwatch.sh evita
# a drede el match() de 3 argumentos (extension de gawk) por eso mismo: estas
# pruebas pasando en un host con gawk no demostrarian nada si el codigo
# dependiera de una extension que el contenedor real no tiene.
#
# Cada caso imprime OK o FALLA, y el script sale 1 si algo falla.

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0

ok()   { printf '  OK    %s\n' "$*"; PASS=$(( PASS + 1 )); }
bad()  { printf '  FALLA %s\n' "$*"; FAIL=$(( FAIL + 1 )); }
caso() { printf '\n== %s\n' "$*"; }

# --------------------------------------------------------------- entorno ---

log()  { printf '[test %s] %s\n'       "$(date -u +%H:%M:%S)" "$*"; }
warn() { printf '[test %s] AVISO: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
is_true() { [[ "${1,,}" =~ ^(1|true|yes|si|y)$ ]]; }
die_loud() { printf '%s\n' "$*" >&2; exit 42; }

# curl NUNCA toca la red de verdad en estas pruebas. Por defecto falla (asi
# los casos que no configuran su propia respuesta se comportan como "la API
# no responde", que es el escenario mas seguro por defecto). Los casos que
# necesitan una respuesta concreta redefinen curl y la deshacen despues.
curl() { return 1; }

# graceful_shutdown/wait_for_ready/wait_for_exit vienen de lifecycle.sh, que
# necesita un servidor de verdad. Aqui se sustituyen por dobles que registran
# que se les llamo (para los casos que verifican "se disparo el reinicio").
LLAMADAS_SHUTDOWN="$(mktemp)"
graceful_shutdown() { echo "1" >> "$LLAMADAS_SHUTDOWN"; return 0; }
wait_for_ready()    { return "${FAKE_WAIT_FOR_READY_RC:-0}"; }
wait_for_exit()     { return 0; }

rcon_cmd() {
    case "$1" in
        players) printf 'Players connected (%s)\n' "${FAKE_PLAYER_COUNT:-0}" ;;
        *)       return 0 ;;
    esac
}
zomboid_running() { return 0; }
rcon_ready()      { return 0; }

# shellcheck source=/dev/null
source "${HERE}/ops.sh"
# shellcheck source=/dev/null
source "${HERE}/modwatch.sh"

STOPPING=0
SHUTDOWN_TIMEOUT=5

# Mundo falso: PZ_DIR con la estructura minima del Workshop, DATA_DIR para
# los ficheros de estado, BACKUP_DIR para las pruebas de rotacion de pre-mods.
nuevo_entorno() {
    PZ_DIR="$(mktemp -d)"
    DATA_DIR="$(mktemp -d)"
    BACKUP_DIR="$(mktemp -d)"
    export PZ_DIR DATA_DIR BACKUP_DIR
    unset BACKUP_NAME_PREFIX MODS_FORCE_STALE FAKE_PLAYER_COUNT FAKE_WAIT_FOR_READY_RC
    PZ_SERVER_NAME="pruebas"
    RESTART_FLAG="${DATA_DIR}/.pz-restart-requested"
    rm -f "$LLAMADAS_SHUTDOWN"; : > "$LLAMADAS_SHUTDOWN"

    mkdir -p "${PZ_DIR}/steamapps/workshop/content/108600"
    mkdir -p "${DATA_DIR}/Saves/mundo" "${DATA_DIR}/db" "${DATA_DIR}/Server" "${DATA_DIR}/Logs"
}

limpiar() { rm -rf "$PZ_DIR" "$DATA_DIR" "$BACKUP_DIR"; }

# Crea el directorio de un mod (lo que hace que active_workshop_ids lo cuente
# como "de verdad descargado").
crear_mod_dir() {
    mkdir -p "${PZ_DIR}/steamapps/workshop/content/108600/${1}"
}

# Escribe un appworkshop_108600.acf de mentira, con la MISMA trampa que tiene
# el real: una seccion "WorkshopItemDetails" con su propio timeupdated (y
# distinto del de instalado, a proposito, para demostrar que se ignora), y un
# "manifest" que hace de numero-que-parece-un-ID de otro mod.
#
# args: pares "id:timeupdated_instalado" ...
escribir_acf() {
    local f="${PZ_DIR}/steamapps/workshop/appworkshop_108600.acf"
    {
        printf '"AppWorkshop"\n{\n\t"appid"\t\t"108600"\n\t"WorkshopItemsInstalled"\n\t{\n'
        local par id ts
        for par in "$@"; do
            id="${par%%:*}"; ts="${par##*:}"
            printf '\t\t"%s"\n\t\t{\n' "$id"
            printf '\t\t\t"size"\t\t"12345"\n'
            printf '\t\t\t"timeupdated"\t\t"%s"\n' "$ts"
            # La trampa: el manifest es un numero de 10 digitos que coincide
            # con el ID real de OTRO mod de la lista (el primero, desplazado).
            printf '\t\t\t"manifest"\t\t"%s0"\n' "$id"
            printf '\t\t}\n'
        done
        printf '\t}\n\t"WorkshopItemDetails"\n\t{\n'
        for par in "$@"; do
            id="${par%%:*}"; ts="${par##*:}"
            printf '\t\t"%s"\n\t\t{\n' "$id"
            printf '\t\t\t"manifest"\t\t"%s0"\n' "$id"
            # A drede DISTINTO del de instalado: si local_timeupdated leyera
            # esta seccion por error, las pruebas 3/4 lo detectarian.
            printf '\t\t\t"timeupdated"\t\t"%s"\n' "$(( ts + 999999 ))"
            printf '\t\t\t"timetouched"\t\t"%s"\n' "$(( ts + 999999 ))"
            printf '\t\t\t"latest_timeupdated"\t\t"%s"\n' "$(( ts + 999999 ))"
            printf '\t\t}\n'
        done
        printf '\t}\n}\n'
    } > "$f"
}


# =========================================================== LOS CASOS =====

caso "workshop_dir: usa 108600 cuando no existe 380870"
nuevo_entorno
[[ "$(workshop_dir)" == "${PZ_DIR}/steamapps/workshop/content/108600" ]] \
    && ok "elige la ruta correcta" || bad "eligio $(workshop_dir)"
limpiar


caso "active_workshop_ids: interseccion entre configurado y descargado"
nuevo_entorno
crear_mod_dir 1111111111
crear_mod_dir 2222222222
# 3333333333 esta configurado pero NO descargado: no debe aparecer.
# 2222222222 esta descargado pero NO configurado: tampoco debe aparecer.
PZ_WORKSHOP_ITEMS="1111111111;3333333333"
activos="$(active_workshop_ids | sort | tr '\n' ',')"
[[ "$activos" == "1111111111," ]] \
    && ok "solo el que esta en ambos lados" || bad "dio '${activos}'"
limpiar


caso "local_timeupdated: lee el valor de instalado, no el de detalles"
nuevo_entorno
escribir_acf "1111111111:1000000000" "2222222222:2000000000"
[[ "$(local_timeupdated 1111111111)" == "1000000000" ]] \
    && ok "valor correcto para el primer mod" || bad "dio '$(local_timeupdated 1111111111)'"
[[ "$(local_timeupdated 2222222222)" == "2000000000" ]] \
    && ok "valor correcto para el segundo mod" || bad "dio '$(local_timeupdated 2222222222)'"
limpiar


caso "local_timeupdated: no cae en la trampa del manifest ni de WorkshopItemDetails"
nuevo_entorno
# El manifest de 1111111111 es literalmente "11111111110", que NO coincide
# con ningun ID real de esta lista (por construccion, un digito de mas), asi
# que esto ademas comprueba que un id inexistente no devuelve nada.
escribir_acf "1111111111:1000000000"
[[ -z "$(local_timeupdated 11111111110)" ]] \
    && ok "el numero de manifest no se confunde con un ID" || bad "conto el manifest como ID"
# Y el valor de WorkshopItemDetails (1000000000 + 999999) NUNCA debe salir.
valor="$(local_timeupdated 1111111111)"
[[ "$valor" == "1000000000" ]] \
    && ok "ignora el timeupdated de WorkshopItemDetails" || bad "se colo el de detalles: ${valor}"
limpiar


caso "collect_mod_status: API caida -> sin-datos, nunca ok ni desfasado por defecto"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
# curl sigue fallando (el doble por defecto de la cabecera).
reporte="$(collect_mod_status)"
verdicto="$(awk -F'\t' '{print $5}' <<<"$reporte")"
[[ "$verdicto" == "sin-datos" ]] \
    && ok "sin red, el veredicto es 'sin-datos'" || bad "veredicto '${verdicto}', esperaba sin-datos"
limpiar


caso "collect_mod_status: API arriba -> ok cuando coincide, desfasado cuando Steam va por delante"
nuevo_entorno
crear_mod_dir 1111111111
crear_mod_dir 2222222222
PZ_WORKSHOP_ITEMS="1111111111;2222222222"
escribir_acf "1111111111:1000000000" "2222222222:1000000000"
curl() {
    cat <<'JSON'
{"response":{"result":1,"publishedfiledetails":[
  {"publishedfileid":"1111111111","result":1,"time_updated":1000000000,"title":"Mod Al Dia"},
  {"publishedfileid":"2222222222","result":1,"time_updated":2000000000,"title":"Mod Desfasado"}
]}}
JSON
}
reporte="$(collect_mod_status)"
v1="$(awk -F'\t' '$1=="1111111111"{print $5}' <<<"$reporte")"
v2="$(awk -F'\t' '$1=="2222222222"{print $5}' <<<"$reporte")"
curl() { return 1; }  # vuelve al stub por defecto, NO a la red real
[[ "$v1" == "ok" ]] && ok "al dia se marca ok" || bad "al dia dio '${v1}'"
[[ "$v2" == "desfasado" ]] && ok "Steam por delante se marca desfasado" || bad "desfasado dio '${v2}'"
limpiar


caso "collect_mod_status: result!=1 o sin time_updated -> sin-datos, no 'ok' por defecto"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
curl() {
    cat <<'JSON'
{"response":{"result":1,"publishedfiledetails":[
  {"publishedfileid":"1111111111","result":9}
]}}
JSON
}
verdicto="$(collect_mod_status | awk -F'\t' '{print $5}')"
curl() { return 1; }  # vuelve al stub por defecto, NO a la red real
[[ "$verdicto" == "sin-datos" ]] \
    && ok "un item retirado/oculto no se confunde con 'ok'" || bad "dio '${verdicto}'"
limpiar


caso "collect_mod_status: MODS_FORCE_STALE fuerza el veredicto sin tocar la red"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
MODS_FORCE_STALE="1111111111"
verdicto="$(collect_mod_status | awk -F'\t' '{print $5}')"
[[ "$verdicto" == "desfasado" ]] \
    && ok "el gancho de pruebas fuerza 'desfasado'" || bad "dio '${verdicto}'"
unset MODS_FORCE_STALE
limpiar


caso "player_count: interpreta la respuesta de RCON, o cadena vacia si no entiende"
nuevo_entorno
FAKE_PLAYER_COUNT=3
[[ "$(player_count)" == "3" ]] && ok "lee 3 jugadores" || bad "dio '$(player_count)'"
rcon_cmd() { printf 'algo irreconocible\n'; }
[[ -z "$(player_count || true)" ]] \
    && ok "respuesta irreconocible da vacio, no 0" || bad "dio '$(player_count || true)'"
# Restaurar el stub por defecto, NO 'unset -f': sin esto, cualquier caso
# posterior que use player_count (via mods_watch_loop) heredaria esta
# respuesta ilegible para SIEMPRE y "vacio" no se detectaria nunca. Exactamente
# la misma clase de fuga que ya obligo a arreglar los casos de curl().
rcon_cmd() {
    case "$1" in
        players) printf 'Players connected (%s)\n' "${FAKE_PLAYER_COUNT:-0}" ;;
        *)       return 0 ;;
    esac
}
limpiar


caso "write_mods_status + note_mods_restart: el resumen no borra la auditoria"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
[[ "$(mods_status_summary)" == "sin comprobar todavia" ]] \
    && ok "antes del primer chequeo lo dice" || bad "dio '$(mods_status_summary)'"
MODS_FORCE_STALE="1111111111"
write_mods_status "$(collect_mod_status)"
grep -q "desfasados: 1 de 1" "$(mods_status_file)" \
    && ok "el resumen cuenta bien" || bad "el resumen no refleja el desfase"
note_mods_restart "solicitado (prueba)"
grep -q "ultimo-reinicio-automatico: solicitado (prueba)" "$(mods_status_file)" \
    && ok "registra el reinicio" || bad "no registra el reinicio"
# Un chequeo posterior NO debe borrar la linea de auditoria.
write_mods_status "$(collect_mod_status)"
grep -q "ultimo-reinicio-automatico: solicitado (prueba)" "$(mods_status_file)" \
    && ok "un chequeo nuevo conserva la auditoria anterior" || bad "el chequeo borro la auditoria"
unset MODS_FORCE_STALE
limpiar


caso "verify_after_mods_restart: no responde -> avisa y senala el backup de resguardo"
nuevo_entorno
FAKE_WAIT_FOR_READY_RC=1
salida="$(verify_after_mods_restart 2>&1 || true)"
grep -qi "no respondio" <<<"$salida" \
    && ok "avisa de que no respondio" || bad "no avisa del fallo de arranque"
grep -q "FALLO" "$(mods_status_file)" \
    && ok "queda registrado como FALLO" || bad "no quedo registrado"
limpiar


caso "verify_after_mods_restart: operativo con un mod que ya no encaja -> AVISO, no silencio"
nuevo_entorno
logf="${DATA_DIR}/Logs/2026-01-01_00-00_DebugLog-server.txt"
printf '[x] required mod not found: DemoMod\n[x] ERROR algo\n' > "$logf"
verify_after_mods_restart >/dev/null 2>&1 || true
grep -q "AVISO" "$(mods_status_file)" \
    && ok "el mod que no encaja queda como AVISO" || bad "no quedo registrado el aviso"
limpiar


caso "verify_after_mods_restart: operativo y limpio -> OK"
nuevo_entorno
logf="${DATA_DIR}/Logs/2026-01-01_00-00_DebugLog-server.txt"
printf '[x] LOG algo normal\n' > "$logf"
verify_after_mods_restart >/dev/null 2>&1 || true
grep -q "OK" "$(mods_status_file)" \
    && ok "arranque limpio se registra como OK" || bad "no se registro como OK"
limpiar


caso "mods_watch_loop: intervalo 0 desactiva la vigilancia y no hace nada"
nuevo_entorno
MODS_CHECK_INTERVAL_SECONDS=0
salida="$(mods_watch_loop 2>&1)"
grep -qi "desactivada" <<<"$salida" \
    && ok "lo dice explicitamente" || bad "no explica que esta desactivado"
limpiar


caso "mods_watch_loop: sin mods desfasados, nunca toca nada"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
curl() { cat <<'JSON'
{"response":{"result":1,"publishedfiledetails":[{"publishedfileid":"1111111111","result":1,"time_updated":1000000000,"title":"Al Dia"}]}}
JSON
}
MODS_CHECK_INTERVAL_SECONDS=1
mods_watch_loop >/dev/null 2>&1 &
pid=$!
sleep 3
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
curl() { return 1; }  # vuelve al stub por defecto, NO a la red real
[[ ! -f "$RESTART_FLAG" ]] && ok "no crea la bandera de reinicio" || bad "creo la bandera sin motivo"
[[ ! -s "$LLAMADAS_SHUTDOWN" ]] && ok "no llama a graceful_shutdown" || bad "llamo a graceful_shutdown sin motivo"
limpiar


caso "mods_watch_loop: desfasado y ocupado -> avisa, NO reinicia"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
MODS_FORCE_STALE="1111111111"
FAKE_PLAYER_COUNT=2
MODS_CHECK_INTERVAL_SECONDS=1
MODS_EMPTY_POLL_SECONDS=1
salida="$(mods_watch_loop 2>&1 & pid=$!; sleep 3; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; true)"
[[ ! -f "$RESTART_FLAG" ]] && ok "con gente dentro NO crea la bandera" || bad "reinicio con gente dentro"
[[ ! -s "$LLAMADAS_SHUTDOWN" ]] && ok "con gente dentro NO llama a graceful_shutdown" || bad "llamo a graceful_shutdown con gente dentro"
unset MODS_FORCE_STALE FAKE_PLAYER_COUNT
limpiar


caso "mods_watch_loop: desfasado y vacio -> reinicia, y SIGUE vigilando despues"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
MODS_FORCE_STALE="1111111111"
FAKE_PLAYER_COUNT=0
MODS_CHECK_INTERVAL_SECONDS=1
MODS_EMPTY_POLL_SECONDS=1
mods_watch_loop >/dev/null 2>&1 &
pid=$!
# Esperar (acotado) a que dispare, en vez de un sleep fijo a ciegas.
esperado=0
for i in $(seq 1 20); do
    if [[ -s "$LLAMADAS_SHUTDOWN" ]]; then esperado=1; break; fi
    sleep 0.5
done
[[ "$esperado" -eq 1 ]] && ok "llama a graceful_shutdown al quedar vacio" || bad "nunca disparo el reinicio"
[[ -f "$RESTART_FLAG" ]] || true  # la bandera la consumiria run.sh; aqui solo importa que se llamara al apagado
kill -0 "$pid" 2>/dev/null && ok "el bucle SIGUE vivo tras el reinicio (continue, no exit)" || bad "el bucle murio tras el reinicio"
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
unset MODS_FORCE_STALE FAKE_PLAYER_COUNT
limpiar


caso "mods_watch_loop: backoff, no reintenta solo con el mismo conjunto desfasado"
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
MODS_FORCE_STALE="1111111111"   # sigue "desfasado" SIEMPRE, como un mod que no se puede sincronizar
FAKE_PLAYER_COUNT=0
MODS_CHECK_INTERVAL_SECONDS=1
MODS_EMPTY_POLL_SECONDS=1
mods_watch_loop >/dev/null 2>&1 &
pid=$!
sleep 6
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
n_llamadas="$(grep -c . "$LLAMADAS_SHUTDOWN" || true)"
[[ "${n_llamadas:-0}" -eq 1 ]] \
    && ok "reinicia UNA vez y no repite con el mismo conjunto (n=${n_llamadas})" \
    || bad "llamo a graceful_shutdown ${n_llamadas} veces, esperaba exactamente 1"
unset MODS_FORCE_STALE FAKE_PLAYER_COUNT
limpiar


caso "mods_watch_loop: el backoff se RESETEA cuando un chequeo con API viva da 0 desfasados"
# El fallo que caza esta prueba existio de verdad: sin el reset, la SEGUNDA
# actualizacion legitima del mismo mod quedaba bloqueada para siempre (CleanUI
# publico dos veces en 24 horas: es el caso mas probable, no una rareza). La
# coreografia va por fichero de respuesta, no por MODS_FORCE_STALE: el bucle
# corre en un subshell y no se le puede cambiar el entorno una vez lanzado.
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
RESPUESTA="$(mktemp)"
curl() { cat "$RESPUESTA"; }
respuesta_con_ts() {
    printf '{"response":{"result":1,"publishedfiledetails":[{"publishedfileid":"1111111111","result":1,"time_updated":%s,"title":"Mod Cambiante"}]}}' "$1" > "$RESPUESTA"
}
espera_llamadas() {  # espera acotada a que LLAMADAS_SHUTDOWN alcance N lineas
    local n="$1" i
    for i in $(seq 1 24); do
        [[ "$(grep -c . "$LLAMADAS_SHUTDOWN" || true)" -ge "$n" ]] && return 0
        sleep 0.5
    done
    return 1
}
FAKE_PLAYER_COUNT=0
MODS_CHECK_INTERVAL_SECONDS=1
MODS_EMPTY_POLL_SECONDS=1

respuesta_con_ts 1000000001          # fase 1: Steam por delante -> debe reiniciar
mods_watch_loop >/dev/null 2>&1 &
pid=$!
espera_llamadas 1 && ok "fase 1: primer desfase dispara el reinicio" \
                  || bad "fase 1: nunca disparo"

respuesta_con_ts 1000000000          # fase 2: curado (fechas iguales, API viva)
sleep 3                              # un par de chequeos limpios -> reset del backoff

respuesta_con_ts 1000000001          # fase 3: MISMO conjunto y MISMA fecha otra vez
if espera_llamadas 2; then
    ok "fase 3: tras curarse, el mismo conjunto vuelve a disparar (backoff reseteado)"
else
    bad "fase 3: el backoff no se reseteo y bloqueo un desfase legitimo"
fi
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
rm -f "$RESPUESTA"
curl() { return 1; }  # vuelve al stub por defecto, NO a la red real
unset FAKE_PLAYER_COUNT
limpiar


caso "mods_watch_loop: atascado, pero una PUBLICACION NUEVA del autor si reintenta"
# El caso complementario del backoff: el reinicio no consiguio sincronizar
# (fecha remota identica -> no insistir), pero si el autor publica OTRA
# version, la fecha remota cambia y eso es un intento legitimo nuevo aunque
# nunca haya habido un chequeo "curado" de por medio. Lo distingue la clave
# id:fecha, no el reset.
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
RESPUESTA="$(mktemp)"
curl() { cat "$RESPUESTA"; }
FAKE_PLAYER_COUNT=0
MODS_CHECK_INTERVAL_SECONDS=1
MODS_EMPTY_POLL_SECONDS=1

respuesta_con_ts 1000000001          # desfase; el acf de mentira NUNCA se actualiza
mods_watch_loop >/dev/null 2>&1 &
pid=$!
espera_llamadas 1 || bad "no disparo el primer reinicio"
sleep 3                              # misma fecha remota -> el backoff debe frenar
n_llamadas="$(grep -c . "$LLAMADAS_SHUTDOWN" || true)"
[[ "${n_llamadas:-0}" -eq 1 ]] \
    && ok "con la misma fecha publicada no insiste (n=${n_llamadas})" \
    || bad "insistio ${n_llamadas} veces con la misma fecha publicada"

respuesta_con_ts 1000000002          # el autor publica OTRA version
if espera_llamadas 2; then
    ok "una fecha publicada nueva vuelve a disparar (clave id:fecha)"
else
    bad "la publicacion nueva quedo bloqueada por el backoff"
fi
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
rm -f "$RESPUESTA"
curl() { return 1; }  # vuelve al stub por defecto, NO a la red real
unset FAKE_PLAYER_COUNT
limpiar


caso "collect_mod_status: un titulo con tabulador no rompe el TSV"
# Los titulos los escribe el autor del mod. Un tabulador dentro desplazaria el
# veredicto a un sexto campo y los awk -F'\t' de todo el flujo dejarian de
# contar ese mod, sin error. Se sanea en el jq de origen; esto lo demuestra.
nuevo_entorno
crear_mod_dir 1111111111
PZ_WORKSHOP_ITEMS="1111111111"
escribir_acf "1111111111:1000000000"
curl() {
    # OJO al %s: el titulo debe llegar al JSON como la SECUENCIA escapada
    # \t (que jq decodifica a tabulador dentro del valor), no como un
    # tabulador crudo, que es JSON ilegal y haria fallar el parseo entero.
    # Esta prueba fallo por eso la primera vez: probaba un fixture roto, no
    # el codigo.
    printf '%s' '{"response":{"result":1,"publishedfiledetails":[{"publishedfileid":"1111111111","result":1,"time_updated":2000000000,"title":"Mod\tCon\tTabuladores"}]}}'
}
reporte="$(collect_mod_status)"
curl() { return 1; }  # vuelve al stub por defecto, NO a la red real
campos="$(awk -F'\t' '{print NF}' <<<"$reporte")"
[[ "$campos" == "5" ]] && ok "la linea conserva exactamente 5 campos" \
                       || bad "la linea tiene ${campos} campos, esperaba 5"
verdicto="$(awk -F'\t' '{print $5}' <<<"$reporte")"
[[ "$verdicto" == "desfasado" ]] && ok "el veredicto sigue en su campo" \
                                 || bad "el veredicto se perdio: '${verdicto}'"
limpiar


caso "ROTATABLE_LABELS: pre-mods rota igual que prestart/periodic"
nuevo_entorno
BACKUP_KEEP=2
for i in 1 2 3 4; do do_backup "pre-mods" >/dev/null 2>&1; done
n="$(ls -1 "${BACKUP_DIR}"/*-pre-mods.tar.zst 2>/dev/null | wc -l)"
[[ "$n" -eq 2 ]] && ok "pre-mods rota a BACKUP_KEEP=2" || bad "quedan ${n}, esperaba 2"
limpiar


rm -f "$LLAMADAS_SHUTDOWN"

# ============================================================== RESUMEN =====

printf '\n---------------------------------------------\n'
printf 'Pruebas superadas: %s   fallidas: %s\n' "$PASS" "$FAIL"

if (( FAIL > 0 )); then
    printf 'HAY FALLOS.\n'
    exit 1
fi
printf 'Todo correcto.\n'
