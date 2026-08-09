#!/usr/bin/env bash
# Levanta el servidor de ENSAYO con una copia del mundo de produccion.
#
# Este es el mecanismo que da la certeza de que un cambio no rompe nada: en vez
# de razonar sobre si un mod nuevo va a corromper los guardados, se prueba
# sobre una copia real y se mira. Produccion no se entera.
#
# Uso:
#   ./scripts/stage.sh            copia el mundo actual de produccion y arranca
#   ./scripts/stage.sh --keep     arranca sin recopiar (sigue donde lo dejaste)
#   ./scripts/stage.sh --down     para y BORRA los datos de staging
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

MODE="${1:-fresh}"

if [[ "$MODE" == "--down" ]]; then
    confirm "Vas a parar staging y BORRAR sus datos. Produccion no se toca."
    "${DC[@]}" --profile staging down
    docker volume rm zroyecto-pombie_pz-data-staging 2>/dev/null || true
    say "Staging eliminado. El volumen del juego se conserva para no redescargar 8 GB."
    exit 0
fi

if [[ "$MODE" != "--keep" ]]; then
    say "Tomando una instantanea de produccion..."
    if service_running pz; then
        "${DC[@]}" exec -T pz /docker/run.sh backup "stage" || die "No pude respaldar produccion."
    else
        "${DC[@]}" run --rm --no-deps pz backup "stage" || die "No pude respaldar produccion."
    fi

    LATEST="$(ls -1t backups/*-stage.tar.zst 2>/dev/null | head -1)"
    [[ -n "$LATEST" ]] || die "No encuentro la instantanea recien creada."
    say "Instantanea: $(basename "$LATEST")"

    say "Limpiando datos previos de staging..."
    "${DC[@]}" --profile staging rm -sf pz-staging >/dev/null 2>&1 || true
    docker volume rm zroyecto-pombie_pz-data-staging >/dev/null 2>&1 || true

    say "Cargando la copia en staging..."
    "${DC[@]}" run --rm --no-deps pz-staging restore "$(basename "$LATEST")"
fi

say "Arrancando staging..."
"${DC[@]}" --profile staging up -d pz-staging

STAGE_PORT="$(grep -E '^STAGING_GAME_PORT=' .env | cut -d= -f2 || true)"

cat <<EOF

  Staging levantandose. La primera vez descarga el juego (~8 GB).

  Conectate a:  localhost:${STAGE_PORT:-16361}
  Logs:         docker compose --profile staging logs -f pz-staging

  Produccion sigue corriendo sin enterarse.

  Que comprobar antes de aplicar el cambio en produccion:
    - El mundo carga sin errores en el log.
    - Tu personaje sigue existiendo, con su inventario.
    - Las construcciones y los contenedores de tu base estan intactos.
    - Se puede recorrer zona ya explorada sin celdas rotas.

  Cuando termines:  ./scripts/stage.sh --down

EOF
