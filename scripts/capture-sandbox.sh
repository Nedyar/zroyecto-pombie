#!/usr/bin/env bash
# Trae al repo los ajustes de sandbox que el servidor genera por su cuenta.
#
# Uso: ./scripts/capture-sandbox.sh [pz|pz-staging]
#
# Al anadir un mod, el juego le agrega su bloque de opciones al SandboxVars en
# tiempo de ejecucion. Como el arranque sobrescribe ese fichero con el del repo,
# esos bloques se regeneran con los valores por defecto cada vez. Este script
# los captura para que pasen a ser configuracion versionada: editable, revisable
# en un diff y transmisible por commits.
#
# Despues de ejecutarlo, mira el diff antes de commitear.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SVC="${1:-pz}"
case "$SVC" in
    pz|pz-staging) ;;
    *) die "Servicio desconocido: '${SVC}'. Usa 'pz' o 'pz-staging'." ;;
esac

say "Capturando el sandbox de ${SVC}"

# Siempre en un contenedor nuevo, aunque el servidor este corriendo. Dos motivos:
#
# 1. El contenedor en marcha puede tener una imagen antigua, sin este comando.
# 2. Recrearlo para actualizarlo seria peor: al arrancar renderiza la config y
#    sobrescribiria el sandbox con el del repo, borrando justo los bloques de los
#    mods que venimos a capturar.
#
# La captura solo lee un fichero del volumen y escribe en config/, asi que no
# necesita el servidor vivo.
"${DC[@]}" --profile staging run --rm --no-deps "$SVC" capture-sandbox

echo
say "Cambios en config/SandboxVars.lua:"
git diff --stat -- config/SandboxVars.lua 2>/dev/null || true
echo
echo "   Revisa con:  git diff config/SandboxVars.lua"
