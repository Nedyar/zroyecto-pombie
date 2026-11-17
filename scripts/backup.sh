#!/usr/bin/env bash
# Backup manual del mundo. Uso: ./scripts/backup.sh [etiqueta]
#
# Si el servidor esta vivo se le fuerza un `save` por RCON antes de empaquetar,
# para capturar un estado consistente en vez del ultimo autosave.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LABEL="${1:-manual}"

if service_running pz; then
    say "Servidor en marcha: fuerzo guardado y respaldo en caliente."
    "${DC[@]}" exec -T pz /docker/run.sh backup "$LABEL"
else
    say "Servidor parado: respaldo en frio."
    "${DC[@]}" run --rm --no-deps pz backup "$LABEL"
fi

say "Backups disponibles:"
ls -lht backups/*.tar.zst 2>/dev/null | head -10 || echo "  (ninguno)"
