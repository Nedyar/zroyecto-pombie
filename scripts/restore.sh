#!/usr/bin/env bash
# Restaura el mundo desde un backup. Uso: ./scripts/restore.sh [fichero]
#
# Sin argumento, lista los backups disponibles y no hace nada.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
    say "Backups disponibles:"
    ls -lht backups/*.tar.zst 2>/dev/null || echo "  (ninguno)"
    echo
    echo "Uso: ./scripts/restore.sh <nombre-del-fichero.tar.zst>"
    exit 0
fi

[[ -f "backups/$(basename "$FILE")" ]] || die "No encuentro backups/$(basename "$FILE")"

confirm "Vas a SUSTITUIR el mundo actual por el contenido de:
    $(basename "$FILE")

Antes de tocar nada se hace un backup automatico del estado actual
(etiqueta pre-restore), asi que esto es reversible."

if service_running pz; then
    say "Parando el servidor de forma segura (save + quit). Esto tarda."
    "${DC[@]}" stop pz
fi

say "Restaurando..."

# FORCE_RESTORE hay que reenviarlo a mano: las variables del shell del host no
# entran solas en el contenedor, y sin este -e la puerta de emergencia que
# documentamos no haria absolutamente nada.
#
# Sirve para cuando el backup previo no se puede hacer (tipicamente, disco
# lleno). El mundo actual se aparta igualmente, asi que sigue habiendo marcha
# atras; lo que se pierde es el tarball.
"${DC[@]}" run --rm --no-deps \
    -e FORCE_RESTORE="${FORCE_RESTORE:-false}" \
    pz restore "$(basename "$FILE")"

say "Restauracion terminada. Arranca cuando quieras:"
echo "    docker compose up -d"
echo
echo "Comprueba que el mundo carga bien ANTES de borrar la carpeta"
echo ".pre-restore-* que quedo dentro del volumen de datos."
