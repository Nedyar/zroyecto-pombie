#!/usr/bin/env bash
# Instala en el servidor un mod que NO viene del Workshop.
#
# Uso:
#   ./scripts/install-local-mods.sh <fichero.zip|carpeta> [pz|pz-staging|pz-vanilla]
#
# Ejemplos:
#   ./scripts/install-local-mods.sh ~/Descargas/TariqsBeardsB42.zip
#   ./scripts/install-local-mods.sh ./workbench/tariqs-beards-b42 pz-staging
#
# Por que existe: los mods locales no pueden vivir en el repositorio cuando son
# material de terceros sin permiso, pero el servidor los necesita en cada
# maquina donde se despliegue. Este script hace de puente: el fichero viaja por
# donde vosotros querais y la instalacion sigue siendo un comando.
#
# Cada JUGADOR necesita ademas su propia copia en %USERPROFILE%\Zomboid\mods,
# porque un mod cosmetico lo dibuja el cliente. Esto solo instala el del servidor.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SRC="${1:-}"
SVC="${2:-pz}"

if [[ -z "$SRC" ]]; then
    cat <<'EOF'

Uso: ./scripts/install-local-mods.sh <fichero.zip|carpeta> [pz|pz-staging|pz-vanilla]

Instala un mod local en la carpeta Zomboid/mods del servidor indicado.
Por defecto instala en produccion (pz).

EOF
    exit 1
fi

[[ -e "$SRC" ]] || die "No encuentro: ${SRC}"

case "$SVC" in
    pz)         VOL="zroyecto-pombie_pz-data" ;;
    pz-staging) VOL="zroyecto-pombie_pz-data-staging" ;;
    pz-vanilla) VOL="zroyecto-pombie_pz-data-vanilla" ;;
    *)          die "Servicio desconocido: '${SVC}'. Usa 'pz', 'pz-staging' o 'pz-vanilla'." ;;
esac

# Instalar por debajo de un servidor vivo es pedir problemas: el juego indexa los
# mods al arrancar y no le sienta bien que aparezcan a media partida.
if service_running "$SVC"; then
    die "El servicio '${SVC}' esta corriendo. Paralo antes:
    docker compose stop ${SVC}"
fi

SRC_ABS="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
SRC_DIR="$(dirname "$SRC_ABS")"
SRC_NAME="$(basename "$SRC_ABS")"

say "Instalando '${SRC_NAME}' en ${SVC} (volumen ${VOL})"

# El dueno que hay que dejar en los ficheros sale del .env, no de un 1000 fijo.
# Este `docker run` no pasa por env_file, asi que los valores se leen aqui, igual
# que hace stage.sh con los puertos. Importa cuando el .env no usa 1000: en
# Docker rootless el dueno correcto es 0, porque el UID 0 de dentro es el usuario
# del host, y dejar 1000 obliga al entrypoint a rehacer un chown recursivo sobre
# todo el volumen en el siguiente arranque.
PUID="$(grep -E '^PUID=' .env | cut -d= -f2 | tr -d '[:space:]' || true)"
PGID="$(grep -E '^PGID=' .env | cut -d= -f2 | tr -d '[:space:]' || true)"

# --entrypoint bash para quedarnos como root: un volumen recien creado pertenece
# a root, y el entrypoint normal baja a 'steam' antes de poder tocarlo.
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint bash \
    -v "${VOL}:/data" \
    -v "${SRC_DIR}:/src:ro" \
    -e SRC_NAME="$SRC_NAME" \
    -e PUID="${PUID:-1000}" \
    -e PGID="${PGID:-1000}" \
    zroyecto-pombie:latest -c '
set -euo pipefail
mkdir -p /data/mods
tmp="$(mktemp -d)"

if [[ -d "/src/${SRC_NAME}" ]]; then
    cp -r "/src/${SRC_NAME}" "${tmp}/"
elif [[ "${SRC_NAME}" == *.zip ]]; then
    unzip -q "/src/${SRC_NAME}" -d "$tmp" 2>/dev/null || true

    # Los zips hechos con Compress-Archive de PowerShell usan barras invertidas
    # como separador. unzip avisa y extrae ficheros cuyo NOMBRE contiene las
    # barras, en vez de crear las carpetas. Se reconstruye el arbol a mano.
    if find "$tmp" -maxdepth 1 -name "*\\\\*" | grep -q .; then
        echo "  (zip con separadores de Windows; reconstruyendo el arbol)"
        while IFS= read -r f; do
            rel="$(basename "$f" | tr "\\\\" "/")"
            mkdir -p "${tmp}/_fix/$(dirname "$rel")"
            mv "$f" "${tmp}/_fix/${rel}"
        done < <(find "$tmp" -maxdepth 1 -type f -name "*\\\\*")
    fi
else
    echo "No se que hacer con ${SRC_NAME}: ni carpeta ni .zip" >&2
    exit 1
fi

# El zip puede traer el mod en la raiz o dentro de una carpeta contenedora.
# Buscamos donde esta de verdad el mod.info en lugar de suponerlo: es el fallo
# mas comun al instalar mods a mano, acabar con un nivel de mas.
#
# Se coge el MENOS PROFUNDO: un mod de Build 42 tiene un mod.info en su raiz y
# otro dentro de la carpeta de version (42/). find no garantiza el orden, y
# quedarse con el primero que aparezca instala la subcarpeta de version como si
# fuera el mod entero.
root="$(find "$tmp" -maxdepth 4 -name mod.info -printf "%d %h\n" 2>/dev/null | sort -n | head -1 | cut -d" " -f2-)"
[[ -n "$root" ]] || { echo "No hay ningun mod.info dentro de ${SRC_NAME}" >&2; exit 1; }

name="$(basename "$root")"
rm -rf "/data/mods/${name}"
cp -r "$root" "/data/mods/${name}"
chown -R "${PUID}:${PGID}" /data

modid="$(grep -iE "^id=" "/data/mods/${name}/mod.info" | head -1 | cut -d= -f2- | tr -d "\r")"
echo
echo "  instalado en : Zomboid/mods/${name}"
echo "  Mod ID       : ${modid}"
echo "  ficheros     : $(find "/data/mods/${name}" -type f | wc -l)"
echo
echo "  Anade este Mod ID a PZ_MODS en .env si no esta ya."
rm -rf "$tmp"
'

say "Listo. Recuerda que cada jugador necesita su propia copia en su carpeta"
echo "   Zomboid\\mods; el servidor no se la puede enviar."
