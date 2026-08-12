#!/usr/bin/env bash
# Pruebas de las salvaguardas de backup y restauracion.
#
# Existen porque el repo entero se apoya en que estas rutas funcionen el dia
# malo, y ese dia no es momento de descubrir que no. La regla que sigue el
# proyecto —"un mecanismo de seguridad que nunca se ha visto funcionar es una
# suposicion, no una salvaguarda"— tambien vale para las salvaguardas mismas.
#
# No tocan nada real: cada caso trabaja sobre directorios temporales propios y
# falsea `df`, `du` o `tar` cuando hace falta provocar el fallo. Se puede lanzar
# con el servidor en marcha.
#
#   ./docker/selftest-backups.sh                 # desde el host
#   docker compose run --rm --no-deps pz /docker/selftest-backups.sh
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
#
# Se carga ops.sh de verdad, no una copia. Lo que no se puede cargar aqui son
# lifecycle.sh (necesita un servidor vivo) ni la parte de lib.sh que depende
# del contenedor, asi que esas piezas se sustituyen por lo minimo.

log()  { printf '[test %s] %s\n'       "$(date -u +%H:%M:%S)" "$*"; }
warn() { printf '[test %s] AVISO: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

is_true() { [[ "${1,,}" =~ ^(1|true|yes|si|y)$ ]]; }

# El die_loud de verdad hace `exit 1`, y esa diferencia importa: si el doble se
# limitara a `return`, la funcion probada seguiria ejecutandose despues de
# abortar y las pruebas darian por bueno un codigo que en produccion nunca corre.
# Asi que tambien sale, con un codigo propio para poder distinguir "aborto por
# die_loud" de "devolvio 1". Las llamadas que puedan abortar se hacen dentro de
# `$( ... )`, que ya es una subshell: el exit se queda ahi.
die_loud() { printf '%s\n' "$*" >&2; exit 42; }

# Sin servidor: el backup no intenta forzar el guardado por RCON.
zomboid_running() { return 1; }
rcon_ready()      { return 1; }
rcon_cmd()        { return 1; }

# shellcheck source=/dev/null
source "${HERE}/ops.sh"

# Cada caso arranca con un mundo falso limpio.
nuevo_entorno() {
    BACKUP_DIR="$(mktemp -d)"
    DATA_DIR="$(mktemp -d)"
    export BACKUP_DIR DATA_DIR
    unset BACKUP_NAME_PREFIX
    PZ_SERVER_NAME="pruebas"
    BACKUP_KEEP=20
    BACKUP_INTERVAL_HOURS=6

    mkdir -p "${DATA_DIR}/Saves/mundo" "${DATA_DIR}/db" "${DATA_DIR}/Server"
    head -c 2000000 /dev/urandom > "${DATA_DIR}/Saves/mundo/chunks.bin"
    echo "jugadores" > "${DATA_DIR}/db/players.db"
    echo "1234" > "${DATA_DIR}/.pz-buildid"
}

limpiar() { rm -rf "$BACKUP_DIR" "$DATA_DIR"; }

cuenta_backups() { ls -1 "${BACKUP_DIR}"/*.tar.zst 2>/dev/null | wc -l; }


# =========================================================== LOS CASOS =====

caso "Backup normal: se crea y se verifica"
nuevo_entorno
rc=0; do_backup "manual" >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] && ok "devuelve 0" || bad "devuelve $rc, esperaba 0"
[[ "$(cuenta_backups)" -eq 1 ]] && ok "deja 1 fichero" || bad "deja $(cuenta_backups) ficheros"
if zstd -t "${BACKUP_DIR}"/*.tar.zst >/dev/null 2>&1; then
    ok "el archivo pasa zstd -t"
else
    bad "el archivo NO pasa zstd -t"
fi
# El contenido tiene que estar completo, no solo ser legible.
# El listado se guarda antes de filtrar: con `set -o pipefail`, un `grep -q`
# corta la tuberia en cuanto encuentra la linea, quien escribe recibe SIGPIPE y
# la condicion entera da falso aunque el archivo este perfecto.
listado="$(zstd -dc "${BACKUP_DIR}"/*.tar.zst 2>/dev/null | tar -t 2>/dev/null || true)"
if grep -q 'Saves/mundo/chunks.bin' <<<"$listado"; then
    ok "el mundo esta dentro del archivo"
else
    bad "falta el mundo dentro del archivo"
fi
# umask 077: el tarball lleva la base de datos de jugadores.
perms="$(stat -c %a "${BACKUP_DIR}"/*.tar.zst)"
[[ "$perms" == "600" ]] && ok "permisos 600" || bad "permisos $perms, esperaba 600"
limpiar


caso "tar avisa 'file changed' (salida 1): el backup es valido y SE CONSERVA"
# Es el desenlace normal cuando se respalda con jugadores dentro. Tratarlo como
# fallo borraba copias buenas: justo las que mas valen.
nuevo_entorno
tar() { command tar "$@" >/dev/null 2>&1; command tar --version >/dev/null; return 1; }
rc=0; do_backup "periodic" >/dev/null 2>&1 || rc=$?
unset -f tar
[[ $rc -eq 0 ]] && ok "devuelve 0 pese al aviso de tar" || bad "devuelve $rc, esperaba 0"
[[ "$(cuenta_backups)" -eq 1 ]] && ok "CONSERVA el backup valido" || bad "borro un backup valido"
limpiar


caso "tar falla de verdad (salida 2): se borra el fichero a medias"
nuevo_entorno
tar() { command tar "$@" >/dev/null 2>&1 || true; return 2; }
rc=0; do_backup "periodic" >/dev/null 2>&1 || rc=$?
unset -f tar
[[ $rc -eq 1 ]] && ok "devuelve 1" || bad "devuelve $rc, esperaba 1"
[[ "$(cuenta_backups)" -eq 0 ]] && ok "no deja restos" || bad "deja $(cuenta_backups) ficheros a medias"
limpiar


caso "Truncamiento real: el archivo incompleto no sobrevive a zstd -t"
nuevo_entorno
# ulimit -f corta la escritura a mitad, que es lo que pasa con el disco lleno.
rc=0
( ulimit -f 100; do_backup "periodic" >/dev/null 2>&1 ) || rc=$?
[[ $rc -ne 0 ]] && ok "devuelve $rc (fallo)" || bad "devuelve 0, deberia fallar"
[[ "$(cuenta_backups)" -eq 0 ]] && ok "no queda ningun archivo roto" || bad "queda un archivo roto"
limpiar


caso "Falta de espacio: se cancela sin escribir nada"
nuevo_entorno
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/fake 100 99 1 99%% /\n'; }
rc=0; do_backup "periodic" >/dev/null 2>&1 || rc=$?
unset -f df
[[ $rc -eq 1 ]] && ok "devuelve 1" || bad "devuelve $rc, esperaba 1"
[[ "$(cuenta_backups)" -eq 0 ]] && ok "no escribe nada" || bad "escribio pese a no haber sitio"
limpiar


caso "Falta de espacio: rota antes de rendirse (autorreparacion)"
# La rotacion vive al final de do_backup, detras del return por falta de
# espacio. Sin el intento de rotar, bajar BACKUP_KEEP no libera nada porque la
# limpieza esta detras de un backup que ya no puede ocurrir.
nuevo_entorno
BACKUP_KEEP=10
for i in 1 2 3 4 5; do
    do_backup "periodic" >/dev/null 2>&1
done
[[ "$(cuenta_backups)" -eq 5 ]] && ok "hay 5 backups de partida" || bad "hay $(cuenta_backups), esperaba 5"
BACKUP_KEEP=2
rc=0; do_backup "periodic" >/dev/null 2>&1 || rc=$?
# Con espacio de sobra, la rotacion normal del final deja KEEP.
[[ "$(cuenta_backups)" -eq 2 ]] && ok "la rotacion aplica el nuevo KEEP" || bad "quedan $(cuenta_backups), esperaba 2"

# Ahora el caso que importa: espacio insuficiente la primera vez que se mira.
# `df` miente solo en la primera llamada; si la rotacion libera y se vuelve a
# medir, la segunda ya da espacio de sobra.
#
# El contador vive en un fichero y no en una variable porque el codigo probado
# mide con `free_kb="$(backup_free_kb)"`, y una sustitucion de comandos es una
# subshell: una variable se reiniciaria a 0 en cada llamada y `df` mentiria
# siempre, haciendo fallar una prueba que en realidad pasa.
CONTADOR="$(mktemp)"; echo 0 > "$CONTADOR"
df() {
    local n; n=$(( $(cat "$CONTADOR") + 1 )); echo "$n" > "$CONTADOR"
    if (( n == 1 )); then
        printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/fake 100 99 1 99%% /\n'
    else
        command df -Pk "$BACKUP_DIR"
    fi
}
BACKUP_KEEP=1
rc=0; salida="$(do_backup "periodic" 2>&1)" || rc=$?
unset -f df; rm -f "$CONTADOR"
[[ $rc -eq 0 ]] && ok "consigue el backup tras rotar" || bad "devuelve $rc: no se autoreparo"
if grep -q "roto los antiguos antes de rendirme" <<<"$salida"; then
    ok "dice que ha rotado para hacer sitio"
else
    bad "no consta el intento de rotar"
fi
limpiar


caso "No se puede medir el espacio: sigue adelante, pero avisando"
# Un fallo al medir no debe dejarte sin copias, y "no lo se" no puede colarse
# como "hay cero" ni como "hay de sobra" en silencio.
nuevo_entorno
df() { return 1; }
salida="$(do_backup "periodic" 2>&1)" && rc=0 || rc=$?
unset -f df
[[ $rc -eq 0 ]] && ok "devuelve 0" || bad "devuelve $rc, esperaba 0"
[[ "$(cuenta_backups)" -eq 1 ]] && ok "hace el backup igualmente" || bad "no hizo el backup"
if grep -q "No he podido medir el espacio" <<<"$salida"; then
    ok "avisa de que la guarda no se aplico"
else
    bad "no avisa: la guarda se apago en silencio"
fi
limpiar


caso "Cerrojo: un backup no se solapa con otro en marcha"
nuevo_entorno
# El cerrojo se retiene desde fuera en vez de lanzar dos backups a la vez: asi
# la prueba no depende de quien gane la carrera y siempre comprueba lo mismo.
( flock 200; sleep 5 ) 200>"${BACKUP_DIR}/.backup.lock" &
retenedor=$!
sleep 0.3
rc=0; salida="$(BACKUP_LOCK_WAIT=1 do_backup "periodic" 2>&1)" || rc=$?
kill "$retenedor" 2>/dev/null || true
wait "$retenedor" 2>/dev/null || true

[[ $rc -eq 1 ]] && ok "se rinde en vez de solaparse" || bad "devuelve $rc, esperaba 1"
[[ "$(cuenta_backups)" -eq 0 ]] && ok "no llega a escribir" || bad "escribio pese al cerrojo"
if grep -q "otro backup en marcha" <<<"$salida"; then
    ok "explica el motivo"
else
    bad "no explica por que se salta"
fi

# Y con el cerrojo libre vuelve a funcionar: no se queda atascado.
rc=0; do_backup "periodic" >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 && "$(cuenta_backups)" -eq 1 ]] \
    && ok "al soltarse el cerrojo, el siguiente pasa" || bad "el cerrojo no se libero"
limpiar


caso "recent_backup_exists: detecta el prestart reciente"
nuevo_entorno
recent_backup_exists "prestart" 60 && bad "dice que hay uno sin haberlo" || ok "sin backups, dice que no"
do_backup "prestart" >/dev/null 2>&1
recent_backup_exists "prestart" 60 && ok "detecta el que acaba de hacer" || bad "no detecta el reciente"
recent_backup_exists "periodic" 60 && bad "confunde etiquetas" || ok "no confunde etiquetas"
limpiar


caso "Restaurar un archivo corrupto: no toca el mundo actual"
nuevo_entorno
do_backup "manual" >/dev/null 2>&1
archivo="$(ls -1 "${BACKUP_DIR}"/*.tar.zst)"
printf 'basura' > "$archivo"          # lo rompemos a proposito
antes="$(cat "${DATA_DIR}/db/players.db")"
rc=0; salida="$(do_restore "$archivo" 2>&1)" || rc=$?
[[ $rc -eq 42 ]] && ok "aborta antes de tocar nada" || bad "devuelve $rc, esperaba abortar"
[[ "$(cat "${DATA_DIR}/db/players.db" 2>/dev/null)" == "$antes" ]] \
    && ok "el mundo actual sigue intacto" || bad "el mundo actual se ha tocado"
[[ -z "$(ls -A "${DATA_DIR}" | grep '^\.pre-restore-' || true)" ]] \
    && ok "no ha apartado nada" || bad "aparto el mundo pese a no restaurar"
limpiar


caso "Restaurar sin poder respaldar: se cancela, pero hay salida"
nuevo_entorno
do_backup "manual" >/dev/null 2>&1
archivo="$(ls -1 "${BACKUP_DIR}"/*.tar.zst)"
antes="$(cat "${DATA_DIR}/db/players.db")"

# Disco lleno -> el pre-restore falla. Antes esto mataba la restauracion entera
# por set -e, sin mensaje y sin forma de forzarla. El disco lleno es justo el
# dia en que quieres restaurar.
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/fake 100 99 1 99%% /\n'; }
rc=0; salida="$(do_restore "$archivo" 2>&1)" || rc=$?
[[ $rc -eq 42 ]] && ok "cancela con mensaje en vez de morir en seco" || bad "devuelve $rc"
if grep -q "FORCE_RESTORE=true" <<<"$salida"; then
    ok "el mensaje explica como forzarlo"
else
    bad "el mensaje no ofrece salida"
fi
[[ "$(cat "${DATA_DIR}/db/players.db" 2>/dev/null)" == "$antes" ]] \
    && ok "el mundo sigue intacto" || bad "el mundo se ha tocado"

# Y con la puerta de emergencia abierta, restaura de verdad.
rm -rf "${DATA_DIR}/Saves"
rc=0; salida="$(FORCE_RESTORE=true do_restore "$archivo" 2>&1)" || rc=$?
unset -f df
[[ $rc -eq 0 ]] && ok "FORCE_RESTORE=true si restaura" || bad "devuelve $rc con FORCE_RESTORE"
[[ -f "${DATA_DIR}/Saves/mundo/chunks.bin" ]] \
    && ok "el mundo vuelve a estar" || bad "el mundo no se restauro"
limpiar


caso "Restaurar bien: aparta el mundo anterior sin borrarlo"
nuevo_entorno
echo "estado-viejo" > "${DATA_DIR}/db/players.db"
do_backup "manual" >/dev/null 2>&1
archivo="$(ls -1 "${BACKUP_DIR}"/*.tar.zst)"
echo "estado-nuevo" > "${DATA_DIR}/db/players.db"
rc=0; salida="$(do_restore "$archivo" 2>&1)" || rc=$?
[[ $rc -eq 0 ]] && ok "devuelve 0" || bad "devuelve $rc"
[[ "$(cat "${DATA_DIR}/db/players.db")" == "estado-viejo" ]] \
    && ok "restaura el contenido del backup" || bad "no restauro el contenido"
aside="$(find "$DATA_DIR" -maxdepth 1 -name '.pre-restore-*' -print -quit)"
[[ -n "$aside" && "$(cat "${aside}/db/players.db")" == "estado-nuevo" ]] \
    && ok "el estado anterior queda apartado y recuperable" || bad "no se aparto el estado anterior"
limpiar


caso "Rotacion: por etiqueta y por instancia"
nuevo_entorno
BACKUP_KEEP=3
for i in 1 2 3 4 5; do do_backup "periodic" >/dev/null 2>&1; done
for i in 1 2; do do_backup "manual" >/dev/null 2>&1; done
n_per="$(ls -1 "${BACKUP_DIR}"/*-periodic.tar.zst 2>/dev/null | wc -l)"
n_man="$(ls -1 "${BACKUP_DIR}"/*-manual.tar.zst 2>/dev/null | wc -l)"
[[ "$n_per" -eq 3 ]] && ok "periodic rota a KEEP=3" || bad "quedan $n_per periodic"
[[ "$n_man" -eq 2 ]] && ok "manual NO se rota" || bad "quedan $n_man manual, esperaba 2"

# Otra instancia no puede tocar los backups de esta.
BACKUP_NAME_PREFIX="otra-instancia"
for i in 1 2 3 4 5; do do_backup "periodic" >/dev/null 2>&1; done
n_per="$(ls -1 "${BACKUP_DIR}"/pz-pruebas-*-periodic.tar.zst 2>/dev/null | wc -l)"
[[ "$n_per" -eq 3 ]] && ok "otra instancia no rota los ajenos" || bad "quedan $n_per de la primera"
limpiar


# ============================================================== RESUMEN =====

printf '\n---------------------------------------------\n'
printf 'Pruebas superadas: %s   fallidas: %s\n' "$PASS" "$FAIL"

if (( FAIL > 0 )); then
    printf 'HAY FALLOS.\n'
    exit 1
fi
printf 'Todo correcto.\n'
