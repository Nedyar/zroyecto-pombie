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
    docker volume rm zroyecto-pombie_pz-data-staging 2>/dev/null || true

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
        # el prefijo de backup de produccion es pz-<nombre> (docker/ops.sh)
        SRC_PREFIX="pz-${SRC_NAME}"
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
    if [[ -n "$("${SRC_DC[@]}" ps -q --status running "$SRC_SVC" 2>/dev/null)" ]]; then
        "${SRC_DC[@]}" exec -T "$SRC_SVC" /docker/run.sh backup "stage" || die "No pude respaldar ${SRC_SVC}."
    else
        "${SRC_DC[@]}" run --rm --no-deps "$SRC_SVC" backup "stage" || die "No pude respaldar ${SRC_SVC}."
    fi

    # Solo instantaneas del ORIGEN elegido: cada instancia tiene su prefijo, y
    # el ultimo *-stage.tar.zst a secas podria ser de otro mundo.
    LATEST="$(ls -1t backups/"${SRC_PREFIX}"-*-stage.tar.zst 2>/dev/null | head -1)"
    [[ -n "$LATEST" ]] || die "No encuentro la instantanea recien creada."
    say "Instantanea: $(basename "$LATEST")"

    say "Limpiando datos previos de staging..."
    "${DC[@]}" --profile staging rm -sf pz-staging >/dev/null 2>&1 || true
    docker volume rm zroyecto-pombie_pz-data-staging >/dev/null 2>&1 || true

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
