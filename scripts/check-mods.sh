#!/usr/bin/env bash
# Compara los mods instalados contra la ultima version publicada en el
# Workshop, y dice cuales estan desfasados. De solo lectura: no reinicia nada
# ni toca datos. El reinicio automatico lo hace el propio servidor por su
# cuenta cuando queda vacio (docker/modwatch.sh); esto es para comprobar a
# mano, o para investigar por que alguien no puede entrar.
#
# Uso:
#   ./scripts/check-mods.sh              detecta el servicio en marcha
#   ./scripts/check-mods.sh pz           fuerza produccion
#   ./scripts/check-mods.sh pz-staging   fuerza staging
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SVC="${1:-}"

if [[ -z "$SVC" ]]; then
    if service_running pz && service_running pz-staging; then
        die "Estan corriendo pz Y pz-staging a la vez. Di cual:
    ./scripts/check-mods.sh pz
    ./scripts/check-mods.sh pz-staging"
    elif service_running pz-staging; then
        SVC="pz-staging"
    else
        SVC="pz"
    fi
fi

if service_running "$SVC"; then
    "${DC[@]}" exec -T "$SVC" /docker/run.sh check-mods
else
    say "El servicio '${SVC}' no esta corriendo; compruebo igualmente (en frio)."
    "${DC[@]}" run --rm --no-deps "$SVC" check-mods
fi
