#!/usr/bin/env bash
# Pruebas de capture_ini, la captura de ajustes del INI hacia la plantilla.
#
# Existen sobre todo por UNA propiedad: esta funcion lee un fichero que contiene
# las contrasenas ya sustituidas y escribe en un fichero que SI se versiona. Una
# fuga aqui no se deshace: el historial de git es permanente. Todo lo demas que
# comprueba este fichero es secundario frente a eso.
#
#   ./docker/selftest-capture-ini.sh
#   docker compose run --rm --no-deps pz /docker/selftest-capture-ini.sh
#
# No tocan nada real: cada caso trabaja sobre ficheros temporales propios.

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
ok()   { printf '  OK    %s\n' "$*"; PASS=$(( PASS + 1 )); }
bad()  { printf '  FALLA %s\n' "$*"; FAIL=$(( FAIL + 1 )); }
caso() { printf '\n== %s\n' "$*"; }

log()  { printf '[test] %s\n' "$*"; }
warn() { printf '[test] AVISO: %s\n' "$*" >&2; }
is_true() { [[ "${1,,}" =~ ^(1|true|yes|si|y)$ ]]; }
# Sale con 42 para poder distinguir "aborto" de "devolvio 1", igual que en
# selftest-backups.sh. Las llamadas que puedan abortar van en $( ), que ya es
# una subshell.
die_loud() { printf '%s\n' "$*" >&2; exit 42; }

zomboid_running() { return 1; }
rcon_ready()      { return 1; }
rcon_cmd()        { return 1; }

# shellcheck source=/dev/null
source "${HERE}/ops.sh"

# La contrasena de mentira que NUNCA debe acabar en la plantilla.
SECRETO="ContrasenaSuperSecreta123"

nuevo_entorno() {
    CONFIG_DIR="$(mktemp -d)"
    DATA_DIR="$(mktemp -d)"
    export CONFIG_DIR DATA_DIR
    PZ_SERVER_NAME="pruebas"
    mkdir -p "${DATA_DIR}/Server"

    # Plantilla como la real: mezcla de variables, valores literales y las tres
    # claves de identidad del mundo.
    cat > "${CONFIG_DIR}/server.ini.tmpl" <<'EOF'
# Cabecera de la plantilla
PVP=${PZ_PVP}
RCONPassword=${PZ_RCON_PASSWORD}
Password=${PZ_SERVER_PASSWORD}
DiscordToken=
SleepNeeded=true
TrashDeleteAll=false
MapRemotePlayerVisibility=1
ResetID=5053633
ServerPlayerID=715247669
Seed=SemillaOriginal
EOF

    # INI de runtime: lo que el servidor tiene tras renderizar y tras haber
    # tocado ajustes en el panel. Las contrasenas van YA SUSTITUIDAS, que es
    # justo lo que hace peligrosa esta captura.
    cat > "${DATA_DIR}/Server/pruebas.ini" <<EOF
PVP=true
RCONPassword=${SECRETO}
Password=${SECRETO}
DiscordToken=
SleepNeeded=false
TrashDeleteAll=true
MapRemotePlayerVisibility=4
ResetID=9999999
ServerPlayerID=8888888
Seed=SemillaDeOtroMundo
EOF
}

limpiar() { rm -rf "$CONFIG_DIR" "$DATA_DIR"; }
tmpl() { cat "${CONFIG_DIR}/server.ini.tmpl"; }


# =========================================================== LOS CASOS =====

caso "Captura normal: coge los ajustes de verdad y NADA mas"
nuevo_entorno
salida="$(capture_ini 2>&1)" && rc=0 || rc=$?
[[ $rc -eq 0 ]] && ok "devuelve 0" || bad "devuelve $rc"

grep -q '^SleepNeeded=false$'              <<<"$(tmpl)" && ok "captura SleepNeeded"    || bad "no capturo SleepNeeded"
grep -q '^TrashDeleteAll=true$'            <<<"$(tmpl)" && ok "captura TrashDeleteAll" || bad "no capturo TrashDeleteAll"
grep -q '^MapRemotePlayerVisibility=4$'    <<<"$(tmpl)" && ok "captura la visibilidad" || bad "no capturo la visibilidad"


caso "LA PRUEBA QUE IMPORTA: la contrasena NO llega a la plantilla"
if grep -q "$SECRETO" <<<"$(tmpl)"; then
    bad "*** FUGA: el secreto esta en la plantilla versionada ***"
else
    ok "el secreto NO aparece en la plantilla"
fi
grep -q '^RCONPassword=${PZ_RCON_PASSWORD}$' <<<"$(tmpl)" \
    && ok "RCONPassword sigue siendo una variable" || bad "RCONPassword dejo de ser variable"
grep -q '^Password=${PZ_SERVER_PASSWORD}$' <<<"$(tmpl)" \
    && ok "Password sigue siendo una variable" || bad "Password dejo de ser variable"
grep -q '^PVP=${PZ_PVP}$' <<<"$(tmpl)" \
    && ok "las demas variables tampoco se tocan" || bad "se sustituyo una variable"
grep -q 'NO capturadas por venir del .env' <<<"$salida" \
    && ok "avisa de cuales no capturo y por que" || bad "no explica las protegidas"
# Una clave sensible VACIA es el estado normal (DiscordToken viene asi de
# serie): no puede confundirse con una fuga. La primera ejecucion real contra
# el servidor aborto por esto, y las pruebas no lo cazaron porque el fixture no
# tenia ninguna vacia.
grep -q '^DiscordToken=$' <<<"$(tmpl)" \
    && ok "una clave sensible vacia no se confunde con una fuga" \
    || bad "DiscordToken vacio no sobrevivio a la captura"


caso "Identidad del mundo: no se captura aunque haya cambiado"
grep -q '^ResetID=5053633$'        <<<"$(tmpl)" && ok "ResetID intacto"        || bad "capturo ResetID"
grep -q '^ServerPlayerID=715247669$' <<<"$(tmpl)" && ok "ServerPlayerID intacto" || bad "capturo ServerPlayerID"
grep -q '^Seed=SemillaOriginal$'   <<<"$(tmpl)" && ok "Seed intacta"           || bad "capturo la Seed de otro mundo"
grep -q 'identidad del mundo' <<<"$salida" \
    && ok "explica por que no las captura" || bad "no lo explica"
limpiar


caso "Idempotencia: capturar dos veces no cambia nada la segunda"
nuevo_entorno
capture_ini >/dev/null 2>&1
antes="$(tmpl)"
salida="$(capture_ini 2>&1)"
[[ "$(tmpl)" == "$antes" ]] && ok "la plantilla no cambia" || bad "la segunda captura la modifico"
grep -q 'no tiene ningun ajuste distinto' <<<"$salida" \
    && ok "lo dice en vez de callarse" || bad "no informa de que no habia nada"
limpiar


caso "La cabecera y los comentarios de la plantilla se conservan"
nuevo_entorno
capture_ini >/dev/null 2>&1
grep -q '^# Cabecera de la plantilla$' <<<"$(tmpl)" \
    && ok "el comentario sigue ahi" || bad "se perdieron los comentarios"
limpiar


caso "Guarda: si el algoritmo fallara y sustituyera una variable, se cancela"
# Se fuerza el escenario que la guarda existe para atrapar: una plantilla en la
# que RCONPassword ya NO es variable. Al capturar, el recuento de lineas con
# ${...} cuadraria, pero la comprobacion de claves sensibles debe saltar.
nuevo_entorno
sed -i 's|^RCONPassword=.*|RCONPassword=valorLiteralQueNoDeberiaEstar|' "${CONFIG_DIR}/server.ini.tmpl"
antes="$(tmpl)"
rc=0; salida="$(capture_ini 2>&1)" || rc=$?
[[ $rc -eq 42 ]] && ok "aborta en vez de continuar" || bad "devuelve $rc, esperaba abortar"
[[ "$(tmpl)" == "$antes" ]] && ok "NO toca la plantilla al abortar" || bad "modifico la plantilla pese a abortar"
grep -q 'CAPTURA CANCELADA' <<<"$salida" && ok "dice por que" || bad "aborta sin explicar"
[[ -z "$(ls "${CONFIG_DIR}"/server.ini.tmpl.tmp.* 2>/dev/null)" ]] \
    && ok "no deja temporales" || bad "deja un fichero temporal"
limpiar


caso "Claves nuevas del servidor: se informan, NO se anaden a ciegas"
nuevo_entorno
printf 'OpcionQueNoExistiaAntes=42\n' >> "${DATA_DIR}/Server/pruebas.ini"
salida="$(capture_ini 2>&1)"
grep -q 'OpcionQueNoExistiaAntes' <<<"$(tmpl)" \
    && bad "la anadio sola a la plantilla" || ok "no la anade sola"
grep -q 'claves que la plantilla no' <<<"$salida" \
    && ok "avisa de que existen" || bad "no avisa"
grep -q 'bootstrap' <<<"$salida" \
    && ok "dice que hacer con ellas" || bad "no dice que hacer"
limpiar


caso "Sin INI de runtime todavia: aborta con mensaje, no a lo bruto"
nuevo_entorno
rm -f "${DATA_DIR}/Server/pruebas.ini"
rc=0; salida="$(capture_ini 2>&1)" || rc=$?
[[ $rc -eq 42 ]] && ok "aborta" || bad "devuelve $rc"
grep -qi 'arrancado al menos una vez' <<<"$salida" \
    && ok "explica que hace falta" || bad "el mensaje no ayuda"
limpiar


# ============================================================== RESUMEN =====

printf '\n---------------------------------------------\n'
printf 'Pruebas superadas: %s   fallidas: %s\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then printf 'HAY FALLOS.\n'; exit 1; fi
printf 'Todo correcto.\n'
