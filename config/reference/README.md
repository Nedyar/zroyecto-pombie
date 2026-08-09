# config/reference

Ficheros **generados** por el propio servidor instalado. No los edites a mano:
se regeneran cada vez que se hace un bootstrap y perderias los cambios.

Sirven para dos cosas:

1. Ser el punto de partida honesto de `config/server.ini.tmpl` — son las claves
   reales de la version instalada, no las de una guia de internet.
2. Detectar que introduce cada actualizacion del juego. Tras actualizar, se
   regeneran y el `git diff` de esta carpeta muestra exactamente que ajustes
   nuevos hay que decidir.
