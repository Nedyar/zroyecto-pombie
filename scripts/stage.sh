#!/usr/bin/env bash
# Levanta el servidor de ENSAYO con una copia de un mundo real.
#
# Este es el mecanismo que da la certeza de que un cambio no rompe nada: en vez
# de razonar sobre si un mod nuevo va a corromper los guardados, se prueba
# sobre una copia real y se mira. El mundo original no se entera.
#
# Uso:
#   ./scripts/stage.sh              copia PRODUCCION y arranca
#   ./scripts/stage.sh --keep       arranca sin recopiar (sigue donde lo dejaste)
#   ./scripts/stage.sh --down       para y BORRA los datos de staging
#
# `--from <servicio>` elige el mundo origen; hoy solo existe `pz`. Si vuelve a
# haber un segundo mundo, se anade su caso al `case` de abajo.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# ---------------------------------------------- el volumen que se puede borrar ---
#
# Este script borra el volumen de datos de staging y restaura encima una copia.
# Hasta noviembre de 2026 lo hacia sobre un nombre escrito a mano
# (`pz-data-staging`), mientras que la restauracion escribe donde diga el
# compose. Cuando el compose cambio —el 13/08 se empezo a jugar en staging—,
# el nombre escrito a mano paso a ser el del mundo de juego y este script lo
# borraba en sus dos modos. Ahora el volumen SALE DEL COMPOSE, el mismo que
# usara la restauracion, y se comprueba antes de tocar nada:
#
#   1. que `pz` y `pz-staging` no monten el mismo volumen de datos;
#   2. que ningun contenedor salvo `pombie-staging` lo monte (con -a: un
#      contenedor parado tambien cuenta). `docker volume rm` ya se niega si
#      algun contenedor lo usa, pero solo si ese contenedor EXISTE, y
#      `do_restore` solo ve los procesos de su propio contenedor: ninguno de
#      los dos protege de restaurar por debajo de otro servidor vivo.
#   3. que `pombie-staging`, si existe, monte justo ese volumen.
#
# El YAML de `compose config` lleva las contrasenas del .env: se lee en una
# variable y se filtra con awk, nunca se imprime.
STAGING_DATA_VOL=""

# data_source_of <servicio> < yaml  ->  nombre del volumen montado en el
# directorio de datos (el de la clave del compose, sin prefijo de proyecto).
data_source_of() {
    awk -v want="$1" '
        /^services:/ { s = 1; next }
        /^[a-z]/     { s = 0 }
        s && /^  [a-z0-9_-]+:$/ { svc = $1; sub(":", "", svc) }
        s && /^      - type:/   { src = "" }
        s && /^        source:/ { src = $2 }
        s && svc == want && /^        target: \/home\/steam\/Zomboid$/ { print src }'
}

# docker_name_of <clave> < yaml  ->  nombre real del volumen en Docker.
docker_name_of() {
    awk -v want="$1" '
        /^volumes:/ { v = 1; next }
        /^[a-z]/    { v = 0 }
        v && /^  [a-z0-9_-]+:$/ { k = $1; sub(":", "", k) }
        v && k == want && /^    name:/ { print $2 }'
}

resolve_staging_data_vol() {
    local cfg prod stg
    cfg="$("${DC[@]}" --profile staging config 2>/dev/null)" \
        || die "No puedo leer el compose (docker compose config). No toco nada."
    prod="$(data_source_of pz <<< "$cfg")"
    stg="$(data_source_of pz-staging <<< "$cfg")"
    [[ -n "$prod" && -n "$stg" ]] \
        || die "No encuentro en el compose el volumen de datos de pz o de pz-staging. No toco nada."
    [[ "$prod" != "$stg" ]] || die "pz y pz-staging montan EL MISMO volumen de datos (${stg}).
Dos servidores sobre un mundo lo corrompen, y este script lo borraria. Revisa el compose."
    STAGING_DATA_VOL="$(docker_name_of "$stg" <<< "$cfg")"
    [[ -n "$STAGING_DATA_VOL" ]] || die "No encuentro el nombre real del volumen ${stg}. No toco nada."
    # Las claves del compose pueden ser distintas y apuntar al MISMO volumen
    # real (un `name:` en la declaracion): se compara tambien el nombre en
    # Docker, que es lo que de verdad se borraria.
    [[ "$(docker_name_of "$prod" <<< "$cfg")" != "$STAGING_DATA_VOL" ]] \
        || die "pz y pz-staging montan EL MISMO volumen real (${STAGING_DATA_VOL}). Revisa el compose."

    # Y ademas tiene que ser el que se espera. Las comprobaciones de arriba no
    # saben cual de los dos mundos es el bueno: con los papeles invertidos
    # (agosto-noviembre de 2026) habrian dado por bueno borrar el de juego.
    # Si algun dia se vuelve a jugar en staging, esto obliga a pararse a
    # pensar antes de reactivar este script.
    [[ "$STAGING_DATA_VOL" == *_pz-data-ensayo ]] || die "El volumen de datos de staging es ${STAGING_DATA_VOL}, no el de ensayo.
Este script solo borra 'pz-data-ensayo'. Si staging ha vuelto a ser el mundo
de juego, NO lo uses: lee docs/DECISIONES.md seccion 6ter."
}

assert_staging_data_vol() {
    local others
    others="$(docker ps -a --filter "volume=${STAGING_DATA_VOL}" --format '{{.Names}}' \
              | grep -vx 'pombie-staging' || true)"
    [[ -z "$others" ]] || die "NO toco ${STAGING_DATA_VOL}: lo monta otro contenedor:
    ${others}
Ese volumen es solo de staging; si lo usa otro, el compose esta mal."

    if docker inspect pombie-staging >/dev/null 2>&1; then
        docker inspect -f '{{range .Mounts}}{{println .Name}}{{end}}' pombie-staging \
            | grep -qx "${STAGING_DATA_VOL}" \
            || die "pombie-staging no monta ${STAGING_DATA_VOL}. No toco nada: recrea staging o revisa el compose."
    fi
}

resolve_staging_data_vol
assert_staging_data_vol

# ------------------------------------------------------------- argumentos ---
MODE="fresh"
SRC_SVC="pz"
while (( $# )); do
    case "$1" in
        --down) MODE="--down" ;;
        --keep) MODE="--keep" ;;
        --from) shift; SRC_SVC="${1:-}" ;;
        *)      die "Argumento desconocido: '$1'. Mira la cabecera del script." ;;
    esac
    shift
done

# ------------------------------------------------------------------- down ---
if [[ "$MODE" == "--down" ]]; then
    confirm "Vas a parar staging y BORRAR sus datos. Los mundos reales no se tocan."

    # OJO: aqui NO vale `docker compose down`, ni siquiera con --profile.
    # `down` derriba el proyecto ENTERO, produccion incluida, sin avisar. Se
    # nombra el servicio explicitamente para tocar solo staging.
    "${DC[@]}" --profile staging stop pz-staging
    "${DC[@]}" --profile staging rm -f pz-staging
    assert_staging_data_vol
    docker volume rm "${STAGING_DATA_VOL}" 2>/dev/null || true

    say "Staging eliminado. El volumen del juego se conserva para no redescargar 8 GB."
    exit 0
fi

# ------------------------------------------------------- origen de la copia ---
#
# Staging comparte a proposito el nombre de mundo con su ORIGEN: el nombre da
# nombre a la carpeta de guardado, y si no coincidieran, staging restauraria la
# copia y luego generaria un mundo vacio al lado, ignorandola — estarias
# probando los mods sobre un mundo recien creado creyendo que es el tuyo.
#
# Por eso aqui se averigua el nombre del mundo origen y se exporta
# STAGING_SERVER_NAME, que el compose usa para el PZ_SERVER_NAME de staging
# (con el de produccion como valor por defecto, asi el uso clasico no cambia).
#
# Los nombres se leen del .env clave a clave, sin volcar el fichero: lleva
# contrasenas.
case "$SRC_SVC" in
    pz)
        SRC_DC=("${DC[@]}")
        SRC_NAME="$(sed -n 's/^PZ_SERVER_NAME=//p' .env | tr -d '[:space:]')"
        [[ -n "$SRC_NAME" ]] || die "No encuentro PZ_SERVER_NAME en .env"
        # El prefijo de las copias de produccion lo fija el compose
        # (BACKUP_NAME_PREFIX del servicio pz). Antes era pz-<nombre>, que es
        # tambien el de las copias del mundo de agosto: con ese prefijo, "la
        # ultima -stage" podia ser una instantanea de agosto.
        SRC_PREFIX="produccion"
        ;;
    # Si algun dia vuelve a haber un segundo mundo, su caso va aqui: hace falta
    # su nombre de mundo (para que staging cargue la copia y no genere uno
    # vacio al lado) y su prefijo de backup (para no restaurar la instantanea
    # de otro). Si el servicio lleva perfil, SRC_DC necesita --profile <x>.
    *)  die "Origen desconocido: '--from ${SRC_SVC}'. Hoy solo existe 'pz'." ;;
esac

export STAGING_SERVER_NAME="$SRC_NAME"

# ------------------------------------------------------------------ copia ---
if [[ "$MODE" != "--keep" ]]; then
    say "Tomando una instantanea de ${SRC_SVC} (mundo '${SRC_NAME}')..."
    # Marca de tiempo ANTES del backup: la instantanea que se restaure tiene
    # que ser la que se acaba de hacer, no una anterior con el mismo prefijo.
    MARK="$(mktemp)"
    trap 'rm -f "$MARK"' EXIT
    if [[ -n "$("${SRC_DC[@]}" ps -q --status running "$SRC_SVC" 2>/dev/null)" ]]; then
        "${SRC_DC[@]}" exec -T "$SRC_SVC" /docker/run.sh backup "stage" || die "No pude respaldar ${SRC_SVC}."
    else
        "${SRC_DC[@]}" run --rm --no-deps "$SRC_SVC" backup "stage" || die "No pude respaldar ${SRC_SVC}."
    fi

    # Solo instantaneas del ORIGEN elegido: cada instancia tiene su prefijo, y
    # el ultimo *-stage.tar.zst a secas podria ser de otro mundo.
    LATEST="$(ls -1t backups/"${SRC_PREFIX}"-*-stage.tar.zst 2>/dev/null | head -1)"
    [[ -n "$LATEST" ]] || die "No encuentro la instantanea recien creada."
    [[ "$LATEST" -nt "$MARK" ]] || die "La instantanea mas reciente (${LATEST}) es ANTERIOR a este
arranque: el backup de ahora no ha dejado fichero. No restauro una copia vieja."
    say "Instantanea: $(basename "$LATEST")"

    say "Limpiando datos previos de staging..."
    "${DC[@]}" --profile staging rm -sf pz-staging >/dev/null 2>&1 || true
    assert_staging_data_vol
    docker volume rm "${STAGING_DATA_VOL}" >/dev/null 2>&1 || true

    say "Cargando la copia en staging..."
    "${DC[@]}" run --rm --no-deps pz-staging restore "$(basename "$LATEST")"
fi

say "Arrancando staging (mundo '${SRC_NAME}')..."
"${DC[@]}" --profile staging up -d pz-staging

STAGE_PORT="$(sed -n 's/^STAGING_GAME_PORT=//p' .env | tr -d '[:space:]')"

cat <<EOF

  Staging levantandose con una copia del mundo '${SRC_NAME}'.
  La primera vez descarga el juego (~8 GB).

  Conectate a:  localhost:${STAGE_PORT:-16361}
  Logs:         docker compose --profile staging logs -f pz-staging

  El mundo original sigue donde estaba, sin enterarse.

  Que comprobar antes de aplicar el cambio en el mundo real:
    - El mundo carga sin errores en el log.
    - Tu personaje sigue existiendo, con su inventario.
    - Las construcciones y los contenedores de tu base estan intactos.
    - Se puede recorrer zona ya explorada sin celdas rotas.

  Cuando termines:  ./scripts/stage.sh --down

EOF
