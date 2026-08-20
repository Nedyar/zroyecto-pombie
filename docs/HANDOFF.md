# Handoff: estado del despliegue

Lo primero que hay que leer para retomar el trabajo. Describe **como esta
desplegado ahora**, que esta verificado y que no, y que queda pendiente.

Los datos propios de la instancia (IPs, correos, contrasenas) **no estan aqui a
proposito**: viven en `.env`, que no se versiona. Este documento describe la
forma del despliegue, no sus valores.

---

## Estado en una linea

**Hay UN mundo, en DOS copias con papeles distintos (reorganizado el 16/08):**

| | Puerto | Estado | Que lleva |
| --- | --- | --- | --- |
| **Produccion** (`pz`) | 16261 | **parado, a proposito** | El mundo **sin** los 5 mods irreversibles. Punto de retorno vivo |
| **Staging** (`pz-staging`) | 16461 | **desplegado, se juega aqui** | El mismo mundo **con** los 5 mods. 32 mods en total |

Los dos salen del mismo mundo (`pombie-vanilla`, 392 MB) y tienen volumenes
separados. Produccion se quedo con la foto de justo antes de meter los mods
irreversibles, y **no como tarball sino como mundo que arranca**: si algun dia
hay que volver, se levanta y ya. El precio es que volver cuesta todo lo jugado
en staging desde el 16/08, y ese coste crece cada dia.

**OJO, la trampa mas grave de este montaje**: `./scripts/stage.sh --down`
**borra el mundo de staging**, y staging es donde se juega. No lo lances sin
haber hecho backup.

**Novedad 16/08/2026 (I)**: el servidor detecta solo cuando Steam ha
actualizado un mod y el suyo se quedo atras (pasaba casi a diario), avisa por
chat, y se reinicia el mismo cuando el mundo queda vacio — nunca con gente
dentro. Detalle en [MODS-DESFASADOS.md](MODS-DESFASADOS.md).

**Novedad 16/08/2026 (II)**: se levanto la regla de "nada irreversible" y
entraron **Common Sense, Take A Bath, Manage Containers, Realistic Temperature
y Trailers!**. Siguen fuera StarvingZombies (reversible, espera votacion) y
Bicycle! (roto en 42.20). Decision tomada con el coste delante; el razonamiento
completo en [MODS-LISTA.md](MODS-LISTA.md) seccion 0.

## Que hay montado

| | |
| --- | --- |
| Anfitrion | Linux (Ubuntu 24.04), portatil usado como servidor, lid ignorado |
| Docker | **rootless**, daemon de usuario, sin grupo `docker` |
| Exposicion | **Tailscale**, sin puertos abiertos en el router |
| Juego | Build 42, `buildid` registrado y coincidente con el instalado |
| Mundos | **uno**, en dos copias: produccion (resguardo) y staging (en juego), 392 MB |
| Mods | **32** en staging: los 25 reversibles + los 5 irreversibles del 16/08 (y sus 3 dependencias). Produccion se queda en 25 |
| Memoria | heap 6g, `mem_limit` 10g |
| Backups | automatico al arrancar + cada 6 h + antes de un reinicio por mods |
| Mods desfasados | deteccion cada 30 min, reinicio solo si el mundo esta vacio |

**El nombre `pombie-vanilla` y los volumenes `*-vanilla` son herencia, no
descripcion**: ese mundo lleva 25 mods. Se conservaron a proposito — renombrar
exigiria mover 285 MB de guardados, y mover guardados es justo lo que este
montaje evita cuando no hace falta.

## Verificado en la maquina

Esto se ejecuto y se comprobo, no se dedujo:

- Build de la imagen con base fijada por digest y `sha256sum -c` del `rcon-cli`.
- El entrypoint funciona con `cap_drop: ALL` y las cinco capabilities elegidas
  (`CapEff` observado: `...00cb`, `NoNewPrivs=1`).
- Con `PUID=0`, lo que el contenedor escribe en los bind mounts aparece en el
  host con el usuario correcto, no con un subuid inalcanzable.
- El daemon rootless esta activo y habilitado; el usuario **no** puede hablar
  con el daemon de sistema (`permission denied`).
- Bootstrap completo: instalacion, arranque, RCON y **apagado limpio** (`save`
  -> `quit` -> JVM muerto por su cuenta).
- Primer arranque real: todos los mods del Workshop descargados y **cero**
  `required mod not found`. Cifras confirmadas contra el INI renderizado.
- **Los jugadores entran y juegan.** 4 simultaneos, sesion larga, sin
  desconexiones inesperadas ni reinicios del contenedor.
- **Varios clientes a la vez se distinguen bien**, pese a que la IP registrada
  no identifique a nadie. Era una incognita y quedo resuelta jugando.
- **Steam Relay no estorba** contra un servidor que solo existe dentro del
  tailnet. Es mas: **la mayoria de las conexiones entran por ahi** (157 frente a
  37 por UDP directo en una sesion), asi que hay un salto mas entre cliente y
  servidor del que sugiere la configuracion de red. Conviene recordarlo al
  diagnosticar.
- El juego escucha solo en la interfaz de Tailscale, no en `0.0.0.0`. RCON solo
  en loopback.
- El mod local se instalo tras auditar su contenido: 142 ficheros, unicamente
  10 lineas de Lua sin acceso a red, sistema ni reflexion Java.
- **La oleada 2 aplicada en staging (16/08)**: backup `antes-oleada-2`
  verificado aparte (90.817 entradas dentro), mundo trasladado a produccion y
  comprobado alli (392 MB, 90.023 ficheros, db y buildid correctos), staging
  rehecho desde produccion con la lista nueva. Verificado: **33 Mod ID / 31
  WorkshopItems** en el INI renderizado, los 8 nuevos presentes, **0**
  `required mod not found`, **0 ERROR fuera del frame de carga**, un solo mundo
  en `Saves/Multiplayer`, RCON respondiendo y `healthy`. La configuracion de
  sandbox del repo ya cubria estos mods (se capturo del mundo de 33): lo unico
  que le sobra son los bloques `Bicycle` y `StarvingZombies`, justo los dos
  excluidos.
- **Reinicio automatico ante mods desfasados**, de extremo a extremo: contra
  el volumen real de produccion (parado, sin exponer puertos) con un mod
  forzado a desfasado, y desplegado de verdad en staging. 51 pruebas propias
  en `docker/selftest-modwatch.sh`, verificadas dentro del contenedor (que
  corre `mawk`, no el `gawk` del host). Una revision adversarial posterior
  corrigio 4 fallos (el grave: el backoff no se reseteaba y la SEGUNDA
  actualizacion del mismo mod quedaba bloqueada para siempre); detalle en
  MODS-DESFASADOS.md.

## Bugs abiertos de jugabilidad

La primera sesion con jugadores destapo fallos **de juego, no de servidor**: el
contenedor no se ha reiniciado ni una vez y la memoria sigue plana. El mas
concreto es que **los cadaveres no aparecen como contenedor** en la ventana de
saqueo, asi que no se pueden registrar.

La investigacion completa —sintoma, evidencia, causa y propuesta, **sin aplicar
nada**— vive en la rama `docs/incidencias-jugabilidad`, carpeta
`docs/incidencias/`. **Cinco incidencias**, cada una con su seccion de lo que NO
esta probado.

**Lo que hay que saber antes de tocar nada:**

- **NO retires mods por estos fallos.** Es la reaccion natural y los datos dicen
  lo contrario. Se ha preguntado dos veces al servidor vanilla y las dos ha
  contestado que no eran los mods: la desincronizacion y el fallo de los
  cadaveres son **varias veces mas frecuentes SIN un solo mod** que con 33.
- La 001 culpaba a `StarvingZombies` de los cadaveres no registrables. Ese
  diagnostico esta **refutado**; retirarlo no habria arreglado nada.
- La 005 concluye que los teletransportes y el mapa que no carga son
  **desincronizacion de estado de mundo propia de Build 42 bajo carga de horda**.
  Ni los mods, ni la red, ni esta maquina.

Avisos metodologicos, que costaron mas que las propias investigaciones: el error
mas numeroso del log **no** era el relevante —se cuenta por causas distintas, no
por lineas—; dos firmas que aparecen juntas en un extracto **no** van
emparejadas hasta que se saca su distribucion por minuto; y una ventana con mas
lineas de log tendra mas de todo, asi que se normaliza en tasa. Los tres estan
detallados en el README de `docs/incidencias/`.

## La historia del mundo que hay, y por que se llama como se llama

Hubo dos mundos y hoy queda uno. Conviene saber como se llego aqui, porque los
nombres despistan.

**El mundo original** (33 mods, `pombie`) se creo el 10/08 y se jugo dos dias.
Se retiro el 13/08 con backup etiquetado
(`pz-pombie-*-antes-de-retirar-mundo-33mods`, 22.647 ficheros dentro,
verificado aparte). Sus volumenes se borraron y liberaron 7 GB.

**El mundo que queda** nacio el 11/08 como *referencia sin mods*, para poder
distinguir "esto lo rompe un mod" de "esto es asi en Build 42". Cumplio ese
papel: se le pregunto **cuatro veces y las cuatro respondio que no eran los
mods** (incidencias 001, 002, 004 y 005). Despues la gente se puso a jugar en
el, pidio interfaz, y acabo llevando 25 mods y siendo mejor mundo que el
original. El 13/08 paso a ser **produccion**.

**Por eso se sigue llamando `pombie-vanilla` y sus volumenes llevan `-vanilla`
en el nombre.** Es herencia, no descripcion. Renombrarlo exigiria mover 285 MB
de guardados dentro del volumen, y mover guardados sin necesidad es justo lo
que este montaje evita. Produccion lo **adoptó tal cual**: se reasigno el
volumen en el compose, sin tocar un byte.

El servicio `pz-vanilla` se elimino en el mismo movimiento. Dos servicios
apuntando al mismo volumen es la forma mas directa de corromper un mundo.

**Consecuencia que hay que tener presente**: ya no existe un mundo limpio de
referencia. Para descartar mods de via unica sigue valiendo staging sobre una
copia; para medir la **linea base del juego base**, lo que vale es la sesion
archivada del 11/08 (~16 `ERROR`/h en cliente, ~2 causas distintas — detalle en
la incidencia 004). Si algun dia hiciera falta una referencia limpia de nuevo,
hay que crear una instancia aparte.

Detalle operativo en [OPERACIONES.md](OPERACIONES.md).

## Caida de 14 horas del 20/08/2026: el papel se hereda, la resistencia no

**Sintoma**: los jugadores llevaban dias sin poder entrar. El contenedor
estaba `Exited (255)` desde hacia 14 horas y nadie se entero.

**Cadena completa**, reconstruida de los logs:

```
04:00:20 CEST  la MAQUINA se reinicia (unattended-upgrades: Automatic-Reboot
               "true", Automatic-Reboot-Time "04:00", con parche de seguridad)
04:00:00 UTC   el contenedor recibe SIGTERM y se apaga LIMPIO
               (SaveAll, Saving players, Saving finish: el mundo se guardo bien)
04:00:34 CEST  el daemon de Docker rootless vuelve solo
     ...       staging NO vuelve
```

**La causa**: `pz-staging` llevaba `restart: "no"`, correcto cuando era un
banco de pruebas de usar y tirar, y **nunca se reviso al convertirse en el
sitio donde se juega** (13/08). Produccion, que esta parada, si tenia
`unless-stopped`. El servicio heredo el papel de produccion pero no sus
salvaguardas.

Es exactamente el escenario que este documento listaba como "NO verificado
nº1" —"que el servidor vuelva solo tras un reinicio"— y que se daba por
cubierto por `restart: unless-stopped`... que staging no tenia.

**Arreglado**: `pz-staging` pasa a `unless-stopped`, con el porque al lado en
el compose. No estorba a `stage.sh --down` ni a `docker compose stop`: una
parada explicita deja el contenedor "stopped" y `unless-stopped` la respeta.

**Lo que funciono y conviene reconocer**: el apagado seguro hizo su trabajo
con un reinicio del sistema por medio. El mundo cruzo la caida sin un
rasguno; lo que fallo fue exclusivamente volver a levantarse.

**Lo que sigue sin resolver, y es lo mas grave del incidente**: nadie se
entero durante 14 horas. No hay ninguna alerta que avise de que el servidor
esta caido; se descubrio porque los jugadores lo dijeron. El vigilante de
mods no sirve para esto —vive dentro del contenedor, asi que muere con el—.
Haria falta algo FUERA: un timer de systemd de usuario que compruebe el
estado y avise. Es la unica pieza del montaje que, por naturaleza, no puede
vivir dentro del repo autocontenido, y por eso se ha ido posponiendo.

## NO verificado

1. **Que el servidor vuelva solo tras un reinicio.** ~~El daemon rootless y el
   linger estan habilitados... `restart: unless-stopped` deberia recuperarlo.~~
   **PROBADO EN REAL el 20/08 y FALLO**, por un motivo distinto al que se
   temia: no fue la carrera con Tailscale, fue que staging llevaba
   `restart: "no"`. Corregido; ver la seccion de la caida de 14 horas arriba.
   **Sigue sin verificarse la carrera original**: si Docker arranca antes de
   que exista la interfaz de Tailscale, el bind puede fallar. El reinicio del
   20/08 no lo aclara porque el contenedor ni siquiera lo intento. Ahora que
   la politica es `unless-stopped`, el proximo reinicio del sistema sera la
   primera prueba real de esa carrera: **conviene mirar el log tras el
   siguiente parche de seguridad**.
2. **Que los mods hagan lo que prometen en juego.** Para eso esta
   [CHECKLIST-MODS.md](CHECKLIST-MODS.md), que ya lleva buena parte marcada.
3. ~~Cual es la linea base de errores de un B42.20 multijugador sano.~~
   **Resuelto el 14/08**: ~16 `ERROR`/h y ~2 causas distintas, medido sobre la
   sesion archivada del 11/08 en el vanilla con cero mods. Con ella, los 172/h
   del cliente en produccion pasan a ser ~11 veces la referencia: anomalo, y
   pendiente de desglosar por firmas. Detalle en la incidencia 004.
4. **Si el mapa que no carga deja rastro en algun sitio.** Ni el servidor ni el
   cliente instrumentan la entrega de chunks, asi que cero errores de carga es
   igual de compatible con "no paso" que con "paso y no se registra". Es el
   agujero principal de la incidencia 005.

## Pendiente

- **Redesplegar staging con la imagen corregida**: la desplegada el 16/08 por
  la manana lleva el fallo del backoff sin reset que cazo la revision (la
  correccion existe, pero el contenedor vivo corre la version anterior). Es
  una recreacion normal con el servidor vacio:
  `docker compose --profile staging up -d pz-staging`.
- **Observar el primer disparo real** del reinicio automatico por mods
  desfasados en staging (al ritmo medido deberia darse en menos de un dia) y
  anotarlo en [MODS-DESFASADOS.md](MODS-DESFASADOS.md) como cierre de todo el
  mecanismo. Ya se probo de extremo a extremo con un mod forzado, pero un
  disparo espontaneo con datos reales de Steam cierra el ciclo.
- **Conseguir los logs de los demas clientes** para la incidencia 005. Solo se
  ha analizado uno, y los errores del servidor son la suma de todos los
  conectados: "aqui esta limpio" no significa "no paso". El procedimiento y el
  encargo que funciono estan en el README de `docs/incidencias/`.
- **Que alguien anote la hora** la proxima vez que ocurra. Es la pieza que mas
  falta: hay dos logs senalando momentos distintos y ninguno captura lo que
  vivieron los jugadores.
- ~~REGLA VIGENTE: no entra ningun mod irreversible.~~ **LEVANTADA el 16/08**:
  entraron los cinco (Common Sense, Take A Bath, Manage Containers, Realistic
  Temperature, Trailers!) sabiendo que ya no salen. El montaje de dos copias
  —produccion sin ellos, staging con ellos— es la red que hizo asumible la
  decision. Razonamiento en MODS-LISTA.md seccion 0.
- **PREGUNTA ABIERTA, ahora medible: que pasa de verdad al quitar Trailers!**
  Se dedujo que los remolques quedarian huerfanos y que el mundo NO se
  romperia (ninguno declara construibles, que es el caso grave de la seccion 5
  de MODS-LISTA), pero **nadie lo ha probado**. Con produccion guardando el
  mundo sin ellos, el experimento sale gratis: enganchar remolques en una
  copia, quitar el mod, y mirar si carga. Convertiria "irreversible" de
  etiqueta heredada en dato.
- **Revisar hacia mediados de septiembre**: los mods-parche de sincronizacion
  de vehiculos. Se evaluaron el 15/08 y ninguno dio la talla —el que ataca
  vehiculos exige instalacion manual en cada cliente, el mantenido para 42.20
  no ataca el sintoma—. Cuadro completo y criterios de revision en la
  incidencia 005.
- **Una votacion de grupo**: StarvingZombies (reversible y exonerado, pero
  cambia jugabilidad).
- Cada jugador necesita su **propia copia del mod local** en su carpeta
  `Zomboid\mods`. El servidor no puede enviarselo. Quien jugo en el mundo
  anterior ya la tiene.
- Dar de alta a los invitados que falten: son **tres** pasos independientes, ver
  [TAILSCALE.md](TAILSCALE.md). Ojo con Tailnet Lock, que fue lo que mas tiempo
  costo de todo el despliegue.

## Errores del log que ya estan revisados

Aparecen en cada arranque y **no son fallos**:

- `Sanitizing container name '...'` — aviso cosmetico de scripts.
- `Could not find bone index for node name: "Body"` — avisos de esqueleto.
- `NoSuchFileException ... /AnimSets` y `/actiongroups` — el animador busca
  carpetas que algunos mods no traen.
- `[S_API FAIL] ... SteamNetworkingUtils004` — aparece siempre, incluso con todo
  funcionando.

## Lo que git NO puede devolverte

El repositorio reconstruye el montaje entero en otra maquina, pero hay dos cosas
que no cubre y que solo existen en el disco del servidor:

- **`.env`**, con las contrasenas y los valores de la instancia. Esta ignorado a
  proposito.
- **El mundo**, en volumenes de Docker. Ni siquiera esta dentro del repositorio.

Si la maquina se pierde, con el repositorio se levanta el servidor en un rato,
pero el mundo jugado y las credenciales no vuelven. Las dos piezas viajan por
otro canal: el **tarball de `backups/`** y una **copia del `.env`**.

Que ambas esten hechas no basta: mientras vivan en el mismo disco que protegen,
no protegen de nada. Tienen que salir de la maquina.

Ver [OPERACIONES.md](OPERACIONES.md), seccion *Migrar a otra maquina*, que es el
mismo procedimiento.

## Lo que mas tiempo costo, para no repetirlo

El despliegue en si fue rapido. Lo que consumio la tarde fue **dar acceso a los
invitados por Tailscale**, y por un motivo que conviene interiorizar: los tres
mecanismos implicados (share, ACL y Tailnet Lock) fallan **de forma parecida y
silenciosa**, y ninguno da un error que apunte a la causa.

La leccion operativa: cuando alguien "no puede conectar", no empieces por el
juego. Mira primero si llegan paquetes:

```bash
docker compose logs pz | grep "initiating a connection"
```

Si no hay ni una linea, el problema esta antes del juego y el juego no tiene
nada que decir al respecto. La tabla de sintomas de [TAILSCALE.md](TAILSCALE.md)
distingue los tres casos.
