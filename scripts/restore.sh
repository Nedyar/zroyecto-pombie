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
"${DC[@]}" run --rm --no-deps pz restore "$(basename "$FILE")"

say "Restauracion terminada. Arranca cuando quieras:"
echo "    docker compose up -d"
echo
echo "Comprueba que el mundo carga bien ANTES de borrar la carpeta"
echo ".pre-restore-* que quedo dentro del volumen de datos."
