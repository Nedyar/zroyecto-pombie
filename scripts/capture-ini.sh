#!/usr/bin/env bash
# Trae al repo los ajustes del servidor que se hayan tocado dentro del juego.
#
# Uso: ./scripts/capture-ini.sh [pz|pz-staging]
#
# El panel de administrador permite cambiar ajustes en caliente, pero el
# arranque renderiza el INI desde config/server.ini.tmpl y se lleva por delante
# lo que se hubiera tocado. Antes eso se notaba poco porque los reinicios eran
# manuales; desde que el vigilante de mods reinicia solo, puede pasar a diario.
#
# Este script cierra el circulo: ajustas en la partida, capturas, y el cambio
# pasa a ser configuracion versionada que ya sobrevive a todos los reinicios.
#
# Lo que NO captura, a proposito:
#   - Las claves que en la plantilla son ${VARIABLES}: su valor manda desde el
#     .env, y dos de ellas son las contrasenas de RCON y del servidor.
#   - ResetID, ServerPlayerID y Seed: son identidad del mundo, no preferencias,
#     y produccion y staging comparten esta plantilla.
#
# Despues de ejecutarlo, mira el diff antes de commitear.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SVC="${1:-pz}"
case "$SVC" in
    pz|pz-staging) ;;
    *) die "Servicio desconocido: '${SVC}'. Usa 'pz' o 'pz-staging'." ;;
esac

say "Capturando los ajustes del INI de ${SVC}"

# Siempre en un contenedor nuevo, por los mismos dos motivos que
# capture-sandbox.sh: el contenedor en marcha puede llevar una imagen sin este
# comando, y recrearlo seria peor porque al arrancar renderiza la config y
# sobrescribiria justo los ajustes que venimos a capturar.
#
# Ojo: por eso mismo, si el servidor esta corriendo y alguien acaba de cambiar
# algo en el panel, el cambio ya esta en el fichero del volumen y se captura
# bien. Lo que se pierde es lo que no haya llegado a escribirse todavia.
"${DC[@]}" --profile staging run --rm --no-deps "$SVC" capture-ini

echo
say "Cambios en config/server.ini.tmpl:"
git diff --stat -- config/server.ini.tmpl 2>/dev/null || true
echo
echo "   Revisa con:  git diff config/server.ini.tmpl"
echo "   Se aplicaran en el proximo arranque del servidor."
