#!/usr/bin/env bash
# Actualiza el servidor a la ultima version publicada en Steam.
#
# Es la UNICA via por la que deberia cambiar la version del juego. El arranque
# normal no comprueba actualizaciones a proposito: asi ningun reinicio rutinario
# puede cambiar el motor por debajo de un mundo vivo, que es de las formas mas
# habituales (y mas silenciosas) de acabar con un guardado corrupto.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

cat <<'EOF'

  Actualizar el servidor implica que:

  - Los jugadores tendran que actualizar tambien su cliente en Steam,
    o no podran conectarse.
  - Los mods pueden dejar de funcionar hasta que sus autores los porten.
  - El mundo existente se abrira con un motor distinto al que lo creo.

  Se hace un backup completo (etiqueta pre-update) antes de nada.

  Si puedes, prueba primero en staging:  ./scripts/stage.sh

EOF

confirm "Continuar con la actualizacion?"

if service_running pz; then
    say "Parando el servidor de forma segura (save + quit). Esto tarda."
    "${DC[@]}" stop pz
fi

say "Actualizando..."
"${DC[@]}" run --rm --no-deps pz update

say "Regenerando la configuracion de referencia de la nueva version..."
"${DC[@]}" run --rm --no-deps pz bootstrap || warn "El bootstrap fallo; hazlo a mano luego."

cat <<'EOF'

  Hecho. Antes de arrancar:

  1. git diff config/reference/
     Muestra que ajustes nuevos trae esta version. Los que te interesen,
     incorporalos a config/server.ini.tmpl.

  2. docker compose up -d

  3. Comprueba que tu personaje y tu base siguen ahi.

EOF
