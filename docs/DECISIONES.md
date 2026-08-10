# Decisiones de diseno

Por que el montaje es asi y no de otra forma. Escrito para cuando dentro de
seis meses algo parezca innecesariamente complicado y haga falta recordar que
problema resolvia.

---

## El requisito que manda sobre todo

Una vez el servidor este abierto y la gente tenga personajes y bases, vamos a
querer seguir tocando ajustes y anadiendo mods. Eso tiene que poder hacerse sin
arriesgar los guardados.

Ese requisito no se cumple teniendo cuidado. Se cumple haciendo que los caminos
peligrosos sean dificiles de recorrer por accidente. Casi todo lo que sigue es
una consecuencia de eso.

---

## 1. Dockerfile propio en vez de una imagen comunitaria

Hay imagenes ya hechas y decentes (Terule, Renegade-Master, Danixu). Se
descartaron por dos razones.

La primera es el momento: Build 42 paso a estable el 29 de julio de 2026, y
empezamos once dias despues. Las imagenes de terceros estan reaccionando a ese
cambio a su propio ritmo. Depender del calendario de otro justo ahora anade un
riesgo que no controlamos.

La segunda pesa mas: el apagado seguro, la guarda de version y la politica de
backups **son** el producto aqui. No son detalles de empaquetado que convenga
delegar. Escribirlos nosotros cuesta unas doscientas lineas de bash y a cambio
sabemos exactamente que hace cada una.

La instalacion del juego no se hornea en la imagen. Vive en un volumen. Asi la
version del juego es un dato del volumen y no de la imagen, que es lo que
permite controlar cuando cambia en vez de que la cambie una reconstruccion
cualquiera.

---

## 2. Volumenes con nombre para los datos, tarball para migrar

Lo intuitivo seria montar `./data` como bind mount: se ve todo en el
explorador de archivos y se copia arrastrando. Se descarto.

En Windows, un bind mount desde `E:\` hacia el contenedor cruza la frontera
entre WSL2 y NTFS en cada operacion. Project Zomboid escribe chunks del mapa
constantemente, y esa frontera es cara. Un volumen con nombre vive dentro del
disco de WSL2 y rinde como Linux nativo.

La portabilidad, que era el motivo para querer el bind mount, la resuelve mejor
el tarball: `backup.sh` produce un `.tar.zst` que `restore.sh` reconstituye en
cualquier host. Funciona igual entre Windows y Linux, va comprimido, y de paso
es el mismo mecanismo que usamos para los backups. Una sola herramienta para
dos problemas.

`config/` y `backups/` **si** son bind mounts: son pequenos, se editan a mano y
conviene tenerlos a la vista.

---

## 3. Configuracion como codigo, en una sola direccion

`config/` es la fuente de verdad y esta en git. El contenedor la renderiza
hacia `Zomboid/Server/` en cada arranque. Nunca al reves.

Esto tiene una propiedad concreta y comprobable: el proceso de configuracion
escribe unicamente en `Server/*.ini` y `Server/*_SandboxVars.lua`. No toca
`Saves/` ni `db/`. Por eso un cambio de ajustes **no puede** danar el mundo, y
no hace falta confiar en que nadie se equivoque.

De regalo, el historial de git responde a "que cambiamos el dia que el servidor
se puso raro", que es una pregunta que se acaba haciendo siempre.

### config/reference/

Lo genera el propio servidor instalado, arrancandolo una vez con un nombre
desechable (`_bootstrap`) y capturando lo que escribe. Sirve para dos cosas.

Una: partir de las claves reales de la version instalada en vez de una
plantilla copiada de una guia que puede estar desactualizada, o ser de Build 41
sin decirlo. La 42.20 genera 144 claves de INI y 1020 lineas de SandboxVars;
adivinar eso no era una opcion.

Dos: cuando el juego se actualiza, se regenera y `git diff config/reference/`
muestra exactamente que ajustes nuevos trae. Sin esto, las claves nuevas
aparecen con su valor por defecto y nadie se entera.

---

## 4. Las actualizaciones no ocurren solas

`UPDATE_ON_START=false` por defecto: el arranque normal ni siquiera pregunta a
Steam si hay algo nuevo.

El escenario que evita es concreto. Steam publica un parche un martes. Alguien
reinicia el servidor el miercoles por cualquier motivo rutinario. El binario se
actualiza, el mundo de la version anterior se abre con un motor distinto, y el
dano no se manifiesta hasta dias despues en forma de contenedores vacios o
celdas del mapa rotas. Para entonces los backups buenos ya han rotado.

Como una sola defensa no basta, hay una segunda: el `buildid` con el que se usa
el mundo queda registrado en el volumen de datos, y el arranque **se detiene**
si no coincide con el instalado. Es preferible un servidor caido a un mundo
corrupto: de lo primero se sale, de lo segundo no siempre.

Actualizar es ejecutar `update-server.sh`, que hace backup, actualiza, registra
la nueva version y regenera la referencia.

---

## 5. El apagado seguro, y por que `stop_grace_period` importa tanto

Parar mal el servidor es el vector de corrupcion mas frecuente que existe. Un
SIGKILL a media escritura deja zombis sin trackear (la gente reaparece en su
base rodeada), inventarios a medias y celdas inconsistentes.

La secuencia es: avisar por chat, `save`, **esperar de verdad** a que termine
de escribir, `quit`, y esperar a que el JVM muera por su cuenta. Medido en este
montaje: 23 segundos con el mundo vacio. Con jugadores y mundo explorado, mas.

Por eso `stop_grace_period: 180s` es probablemente la linea mas importante del
`docker-compose.yml`. Docker manda SIGKILL 10 segundos despues del SIGTERM por
defecto. Sin ese margen, todo lo anterior se queda a medias y acabamos
exactamente en el escenario que queriamos evitar.

Tres detalles que no son obvios:

- **Se espera al JVM, no al lanzador.** `start-server.sh` es un envoltorio; el
  proceso que escribe los guardados es su hijo. Esperar al padre parece
  correcto y no lo es.
- **Hay dos caminos hacia `save`.** RCON es el principal; la consola del
  servidor a traves de un FIFO es el respaldo. Cuando lo que esta en juego es
  no corromper el mundo, un unico mecanismo es poco.
- **El FIFO tambien resuelve otro problema.** El servidor lee comandos por
  stdin; con stdin cerrado, algunas versiones giran sobre EOF comiendose una
  CPU entera. Un FIFO abierto en lectura-escritura nunca produce EOF.

---

## 6. Staging con volumenes propios

Es la respuesta directa a "quiero anadir mods sin arriesgar los guardados". En
vez de razonar sobre si un mod va a romper algo, se levanta una copia del mundo
real en otros puertos, se prueba, y se mira.

Staging tiene su **propio** volumen del juego, no solo de datos. Compartirlo
ahorraria 7,5 GB de disco y una descarga, pero romperia el aislamiento justo
donde importa: al descargar mods del Workshop, Steam actualizaria tambien los
que produccion esta usando en ese momento. El disco es mas barato que eso.

---

## 7. Backups: que se rota y que no

Automaticos antes de arrancar, cada 6 horas, y antes de actualizar o restaurar.
Si el servidor esta vivo se fuerza un `save` por RCON antes de empaquetar, para
capturar un estado consistente en vez del ultimo autosave.

La rotacion solo borra los automaticos. Los `manual`, `pre-update` y
`pre-restore` no se borran nunca, porque son exactamente los que quieres tener
el dia que algo ha salido mal. Un sistema de rotacion que borra el backup
anterior a la actualizacion que rompio el mundo no sirve de nada.

Restaurar no borra: **aparta** los datos previos en `.pre-restore-<fecha>`. Si
la restauracion resulta ser el error, sigue habiendo marcha atras.

---

## 8. Docker rootless en vez del grupo `docker`

Meter al usuario en el grupo `docker` es lo que hace todo el mundo y es
equivalente a darle root sin contrasena: con acceso al socket, un
`docker run -v /:/host` te entrega la maquina entera. Para un servidor de juego
expuesto a amigos, esa concesion no compensa.

Docker rootless levanta un daemon propio del usuario, sin privilegios. Es la
alternativa que la propia documentacion de Docker propone, y aqui encaja
especialmente bien porque **no obliga a cambiar ni una linea del repo**: los
scripts llaman a `docker compose` a secas y un `docker context` activo los
redirige al daemon correcto.

El precio son tres cosas: un daemon mas (e imagenes duplicadas en disco si ya
habia otro), `PUID=0` en el `.env` por el mapeo de UID, y que el reenvio de
puertos UDP no conserva la IP de origen. Las tres estan explicadas en
[OPERACIONES.md](OPERACIONES.md).

---

## 9. Endurecimiento del contenedor

Cinco cambios, todos con el mismo criterio: que el fallo sea imposible o
ruidoso, nunca silencioso.

**La imagen base va por digest, no por tag.** `ubuntu-22` es mutable. Todo este
proyecto existe para que nada cambie bajo el servidor sin decision humana, y la
imagen se reconstruye justo al migrar de maquina — el peor momento posible para
encontrarse una base distinta.

**Se verifica el sha256 de `rcon-cli`.** Ese binario recibe la clave de RCON en
cada healthcheck. Es de lo ultimo que interesa descargar y ejecutar a ciegas.

**`cap_drop: ALL` y solo cinco capabilities.** El contenedor arrancaba con las
~14 por defecto, incluidas `NET_RAW` y `MKNOD`, cuando solo usa `CHOWN`,
`DAC_OVERRIDE`, `FOWNER`, `SETUID` y `SETGID`. Mas `no-new-privileges`, que no
estorba a `gosu` porque gosu deja privilegios en vez de cogerlos.

**`mem_limit`.** Sin techo declarado, quedarse sin RAM deja al OOM killer del
kernel eligiendo victima. Si le toca al JVM en mitad de un guardado, sale justo
el mundo corrupto que todo esto evita: un SIGKILL del kernel no espera al
apagado seguro. Con techo, al menos muere el proceso correcto y de forma
predecible.

**`HOST_BIND_IP`.** Decide en que interfaz se publica el juego. Con la IP de
Tailscale, el servidor no existe fuera del tailnet y las ACL pasan a ser el
unico control de acceso. En `0.0.0.0` seguiria accesible desde la red local,
donde ninguna ACL de Tailscale interviene — y conviene saber que los puertos
publicados por Docker **se saltan UFW**, asi que el bind es el control real, no
el cortafuegos.

Y un sexto, mas prosaico: **hay `.dockerignore`**. Sin el, el contexto de build
era el repositorio entero, incluido el `.env` con las contrasenas y una carpeta
`backups/` que con el tiempo son decenas de GB. Es lista blanca, no negra: con
lista negra, cualquier carpeta futura vuelve a colarse sola.

---

## Cosas que costaron una tarde y conviene no redescubrir

**SteamCMD: `validate` sobre un directorio vacio falla.** Da el error
`Failed to install app '380870' (Missing configuration)`, que no dice nada
util. No es red ni permisos: no se puede validar lo que aun no existe. Se
valida solo cuando ya hay instalacion.

**SteamCMD: `+force_install_dir` va antes de `+login`.** Si va despues, avisa
con `Please use force_install_dir before logon!` y te instala en `~/Steam`.

**La RAM se fija en `ProjectZomboid64.json`, no por linea de comandos.** El
lanzador construye los argumentos del JVM desde ese JSON e ignora lo que le
llegue por fuera. Es un fallo silencioso: crees tener 8 GB y estas corriendo
con los 2 GB por defecto hasta que revienta bajo carga. Se comprueba en el log:
`pzexe: vmArg (json) 9: -Xmx8g`.

**rcon-cli trata cada argumento como un comando independiente.** `rcon servermsg
"hola"` manda dos comandos y el servidor responde con dos `Unknown command`.
Hay que unirlos en una sola cadena. Esto rompia el aviso a los jugadores del
apagado sin que se notara en ningun sitio.

**Git Bash reescribe las rutas absolutas.** `/docker/run.sh` le llega a Docker
como `C:/Program Files/Git/docker/run.sh`. Se resuelve con `MSYS_NO_PATHCONV=1`
en `scripts/_common.sh`; en Linux es inocuo.

**Los puertos de juego son UDP.** 16261 y 16262. Una regla TCP en el router se
ve perfecta y no hace absolutamente nada.

**Los scripts venian de git sin bit de ejecucion.** Estaban como `100644`
porque el proyecto nacio en Windows, donde da igual. En Linux fallan todos los
comandos del README con un `permission denied` antes de leer una sola linea. En
`docker/` no se notaba porque el Dockerfile hace `chmod +x` al construir.

**Editar `docker/*.sh` no surte efecto hasta reconstruir.** Se hornean en la
imagen. Se pierde un rato largo relanzando algo y viendo el comportamiento
antiguo, convencido de que el cambio no funciona.

**Tailnet Lock bloquea a los invitados en silencio.** Si esta activo, cada
dispositivo compartido necesita firma manual. Hasta entonces el invitado ve la
maquina como `active` y su contador `tx` sube, pero `rx` se queda en 0 y al
servidor no llega ni un paquete. Ademas la nodekey **rota** en cada reintento,
asi que hay que mirar y firmar seguido o dara `node not found`.

**Un nodo compartido tiene una IP distinta para el invitado.** El dueno lo ve
como `.39` y los invitados como `.38`. Darles la IP propia en vez de la suya
produce un "no conecta" sin ningun error por ninguna parte.

**`tailscale serve` exige el nombre DNS; un puerto normal exige la IP.** Serve
termina TLS con un certificado emitido para el nombre, asi que por IP falla. El
juego es un socket UDP crudo y solo escucha en IPv4, asi que por nombre puede
irse a IPv6 y morir en silencio. Dos reglas opuestas en la misma maquina: no
extrapolar de un servicio al otro.
