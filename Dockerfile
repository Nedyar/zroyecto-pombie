# syntax=docker/dockerfile:1

# Zroyecto Pombie - imagen del servidor dedicado de Project Zomboid (Build 42).
#
# La instalacion del juego (~8 GB) NO se hornea en la imagen: se descarga al
# volumen `pz-game` en el primer arranque. Asi la imagen pesa poco, reconstruirla
# es barato, y sobre todo: la version del juego pasa a ser un dato del volumen,
# no de la imagen. Eso es lo que nos permite controlar cuando se actualiza en
# lugar de que una reconstruccion cualquiera nos cambie el binario por debajo de
# un mundo vivo.
#
# La base va fijada por DIGEST, no por tag. `ubuntu-22` es un tag mutable: un
# rebuild dentro de seis meses traeria otra imagen sin que nadie lo decidiera,
# que es exactamente lo que este proyecto evita con la version del juego. Aqui
# la reconstruccion no es rutinaria pero si es lo primero que se hace al migrar
# de maquina, y ahi es donde duele encontrarse una base distinta.
#
# Para actualizarla a proposito:
#     docker buildx imagetools inspect steamcmd/steamcmd:ubuntu-22
# y se pega el digest nuevo aqui, en su propio commit.
FROM steamcmd/steamcmd:ubuntu-22@sha256:48a3ddb98338a53c9a4f0e03fe002331019844a81ab09c978aaae9850c460409

ARG DEBIAN_FRONTEND=noninteractive
ARG RCON_CLI_VERSION=0.10.3
# sha256 del tarball de la version de arriba. Si cambias RCON_CLI_VERSION tienes
# que cambiar tambien esto o el build fallara, que es justo lo que queremos.
ARG RCON_CLI_SHA256=6962a641ebf9a5957bd0cda1b8acf3e34a23686ae709f6c6a14ac3898521a5cc

# gettext-base -> envsubst, para renderizar la plantilla del INI
# jq            -> parchear ProjectZomboid64.json (asignacion real de RAM)
# procps        -> pgrep, para esperar a que muera el JVM en el apagado seguro
# zstd          -> compresion de los backups
# gosu          -> soltar privilegios de root a steam conservando las senales
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gettext-base \
        gosu \
        jq \
        procps \
        tzdata \
        unzip \
        zip \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# Cliente RCON estatico. Es la pieza que hace posible el apagado seguro:
# sin el no hay forma de mandarle `save` y `quit` al servidor antes de pararlo.
#
# Se verifica el sha256 antes de instalarlo. Este binario recibe la contrasena
# de RCON en cada healthcheck, o sea que es de lo ultimo que interesa aceptar a
# ciegas: una release reemplazada en origen entraria sin que nadie lo notara.
RUN set -eux; \
    curl -fsSL -o /tmp/rcon.tar.gz \
        "https://github.com/gorcon/rcon-cli/releases/download/v${RCON_CLI_VERSION}/rcon-${RCON_CLI_VERSION}-amd64_linux.tar.gz"; \
    echo "${RCON_CLI_SHA256}  /tmp/rcon.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/rcon.tar.gz -C /tmp; \
    install -m 0755 "/tmp/rcon-${RCON_CLI_VERSION}-amd64_linux/rcon" /usr/local/bin/rcon; \
    rm -rf /tmp/rcon.tar.gz "/tmp/rcon-${RCON_CLI_VERSION}-amd64_linux"; \
    test -x /usr/local/bin/rcon

# Usuario no-root. Los UID/GID reales se ajustan en tiempo de arranque via
# PUID/PGID; esto solo fija el punto de partida. Importa al migrar a Linux:
# ficheros propiedad de root en el volumen de guardados son un incordio serio.
RUN set -eux; \
    if ! getent group steam >/dev/null; then groupadd -g 1000 steam; fi; \
    if ! getent passwd steam >/dev/null; then useradd -m -u 1000 -g steam -s /bin/bash steam; fi; \
    mkdir -p /opt/pz-server /home/steam/Zomboid /config /backups \
             /home/steam/.steam/sdk64 /home/steam/Steam; \
    chown -R steam:steam /opt/pz-server /home/steam /backups

COPY docker/ /docker/
RUN chmod +x /docker/*.sh

ENV HOME=/home/steam \
    LANG=C.UTF-8 \
    PZ_DIR=/opt/pz-server \
    DATA_DIR=/home/steam/Zomboid \
    CONFIG_DIR=/config \
    BACKUP_DIR=/backups \
    STEAM_APP_ID=380870

# 16261/udp y 16262/udp son los puertos de juego. Son UDP, no TCP: es el error
# de configuracion mas comun al abrir puertos en el router.
EXPOSE 16261/udp 16262/udp 27015/tcp

VOLUME ["/opt/pz-server", "/home/steam/Zomboid"]

ENTRYPOINT ["/docker/entrypoint.sh"]
