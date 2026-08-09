#!/usr/bin/env bash
# Genera config/reference/ arrancando el servidor una vez con un nombre
# desechable, y crea config/server.ini.tmpl si aun no existe.
#
# Se ejecuta solo una vez al principio, y despues de cada actualizacion del
# juego: el `git diff` de config/reference/ muestra exactamente que ajustes
# nuevos ha traido la version, en vez de que aparezcan en silencio.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

service_running pz && die "Para el servidor antes:  docker compose stop pz"

say "Generando configuracion de referencia (arranca y apaga el servidor una vez)."
say "La primera vez descarga ~8 GB. Paciencia."

"${DC[@]}" run --rm --no-deps pz bootstrap

say "Listo. Revisa:"
echo "    config/reference/server.ini     <- lo que genera la version instalada"
echo "    config/server.ini.tmpl          <- nuestra plantilla (editable)"
