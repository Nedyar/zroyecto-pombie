#!/usr/bin/env bash
# Base compartida por los scripts de operacion del host.
#
# Estos scripts son envoltorios finos a proposito: toda la logica de verdad
# (backup, restauracion, apagado seguro) vive dentro del contenedor, en
# docker/run.sh. Asi existe una sola implementacion y se comporta igual la
# lances desde Windows, desde Linux o desde dentro del propio contenedor.

set -Eeuo pipefail

# En Git Bash (Windows), MSYS reescribe cualquier argumento que parezca una
# ruta absoluta de Unix. Sin esto, `/docker/run.sh` le llega a Docker como
# 'C:/Program Files/Git/docker/run.sh' y todos los comandos fallan con un
# "no such file or directory" bastante desconcertante. En Linux es inocuo.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

# Trabajar siempre desde la raiz del proyecto, se llame al script desde donde
# se llame.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

say()  { printf '\n>> %s\n' "$*"; }
warn() { printf '\n!! %s\n' "$*" >&2; }
die()  { printf '\n!! %s\n' "$*" >&2; exit 1; }

[[ -f .env ]] || die "Falta el fichero .env. Copialo de la plantilla:
    cp .env.example .env
y rellena las contrasenas."

# docker compose (v2) o docker-compose (v1), lo que haya.
if docker compose version >/dev/null 2>&1; then
    DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    DC=(docker-compose)
else
    die "No encuentro docker compose. Arranca Docker Desktop o instala Docker."
fi

docker info >/dev/null 2>&1 || die "El daemon de Docker no responde. Arranca Docker Desktop."

# Devuelve 0 si el servicio dado esta corriendo.
service_running() {
    local svc="$1"
    [[ -n "$("${DC[@]}" ps -q --status running "$svc" 2>/dev/null)" ]]
}

# PROVISIONAL (16/11/2026), hasta aplicar docs/PLAN-CAMBIO-DE-PAPELES.md.
#
# Desde el 13/08 los papeles estan invertidos: `pz` ("produccion") es la foto
# congelada del 16/08 y el mundo en el que se juega es `pz-staging`. Todos los
# scripts que trabajan sobre `pz` operan entonces sobre el mundo EQUIVOCADO sin
# dar ningun error: backup.sh hace una copia en frio del mundo de agosto,
# capture-*.sh trae al repo los ajustes de agosto y el render se los aplica a la
# partida buena en el siguiente arranque, install-local-mods.sh instala en un
# volumen que ya no existe. Mejor que se nieguen.
#
# Se quita en el mismo cambio que devuelve el mundo de juego a `pz`.
refuse_frozen_pz() {
    # `pz-vanilla` tambien: install-local-mods.sh aun lo acepta y escribe en
    # el volumen del mundo congelado (el servicio se retiro el 13/08).
    [[ "${1:-}" == "pz" || "${1:-}" == "pz-vanilla" ]] || return 0
    die "PROVISIONAL: hoy 'pz' es el mundo CONGELADO de agosto, no el de juego.
El mundo de juego es 'pz-staging'. Este script trabajaria sobre el equivocado.
Ver docs/PLAN-CAMBIO-DE-PAPELES.md. Equivalentes para el mundo de juego:
  backup (en marcha):  docker compose --profile staging exec -T pz-staging /docker/run.sh backup <etiqueta>
  backup (parado):     docker compose --profile staging run --rm --no-deps pz-staging backup <etiqueta>
  rcon:                docker compose --profile staging exec -T pz-staging /docker/run.sh rcon <comando>
  capturas:            ./scripts/capture-ini.sh pz-staging   (y capture-sandbox.sh)"
}

confirm() {
    local prompt="$1"
    printf '\n%s\n' "$prompt"
    read -r -p "Escribe SI para continuar: " answer
    [[ "$answer" == "SI" ]] || die "Cancelado."
}
