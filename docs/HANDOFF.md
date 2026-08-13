# Handoff: estado del despliegue

Lo primero que hay que leer para retomar el trabajo. Describe **como esta
desplegado ahora**, que esta verificado y que no, y que queda pendiente.

Los datos propios de la instancia (IPs, correos, contrasenas) **no estan aqui a
proposito**: viven en `.env`, que no se versiona. Este documento describe la
forma del despliegue, no sus valores.

---

## Estado en una linea

**Donde se juega ahora es el mundo VANILLA (puerto 16461). Produccion (16261)
esta parada desde el 12/08 y su mundo intacto. Ambos sanos; hay bugs de
jugabilidad abiertos, y ya se sabe que no los causan los mods.**

Levantar produccion cuando toque: `docker compose up -d`. No conviene tener las
dos a la vez sin mirar antes `docker stats`.

## Que hay montado

| | |
| --- | --- |
| Anfitrion | Linux (Ubuntu 24.04), portatil usado como servidor, lid ignorado |
| Docker | **rootless**, daemon de usuario, sin grupo `docker` |
| Exposicion | **Tailscale**, sin puertos abiertos en el router |
| Juego | Build 42, `buildid` registrado y coincidente con el instalado |
| Mods en produccion | 33 elementos del Workshop + 1 local (`TariqsBeardsB42`) |
| Mods en vanilla | **25** (oleada 1): todos reversibles, sin definiciones persistentes |
| Memoria | produccion heap 6g / vanilla 3g, `mem_limit` 10g |
| Backups | automatico al arrancar + cada 6 h, **en las dos instancias** |

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

## El mundo vanilla: de referencia a mundo propio

Existe un tercer servidor, perfil `vanilla`, con el **mismo mapa, la misma
semilla y los mismos ajustes** que produccion pero con el mundo generado desde
cero. Puerto 16461.

Nacio **sin un solo mod**, y no era un capricho: sin el no habia forma de
distinguir "esto lo rompe un mod" de "esto es asi en Build 42", y varias
incidencias abiertas estaban bloqueadas por eso.

**Ha dejado de ser eso.** La gente se puso a jugar ahi y pidio mods: el 12/08
entraron 7 de interfaz y el 13/08 la **oleada 1** completa —25 mods, todos
reversibles, criterio y medicion en MODS-LISTA.md seccion 0—. Antes se le
habian activado los backups. Todo responde al mismo hecho: es un mundo
habitado.

La linea base de errores de un B42.20 limpio **ya no se puede volver a medir
aqui** —el vanilla dejo de estar limpio el 12/08— pero **se rescato a tiempo**
de los logs archivados de la sesion del 11/08, cuando aun no llevaba nada:
**~16 `ERROR`/h en cliente, ~2 causas distintas**. Detalle y salvedades en la
incidencia 004. Para descartar mods de via unica el vanilla sigue sirviendo;
para medir el juego base, lo que vale es esa sesion archivada.

Detalle en [OPERACIONES.md](OPERACIONES.md), seccion *Mundo vanilla*.

**Ya no es desechable, y tiene backups propios.** Nacio sin ellos por ser un
mundo de comparacion, pero la gente se puso a jugar ahi: cuatro personajes y un
mundo mas grande que el de produccion. Se le activaron los automaticos (al
arrancar y cada 6 h, prefijo `vanilla-`) el 2026-08-12. Merece la pena recordar
el patron: la premisa que justifica saltarse una salvaguarda puede caducar sin
que nadie lo anuncie.

**Solo uno a la vez.** Produccion y vanilla consumen ~4,5 GB y ~4,1 GB sobre una
maquina de 14 GB: caben los dos, pero sin margen para picos. Mira `docker stats`
antes de levantar el segundo.

## NO verificado

1. **Que el servidor vuelva solo tras un reinicio.** El daemon rootless y el
   linger estan habilitados, pero hay una carrera sin probar: si Docker arranca
   antes de que exista la interfaz de Tailscale, el bind falla. `restart:
   unless-stopped` deberia recuperarlo.
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

- **Conseguir los logs de los demas clientes** para la incidencia 005. Solo se
  ha analizado uno, y los errores del servidor son la suma de todos los
  conectados: "aqui esta limpio" no significa "no paso". El procedimiento y el
  encargo que funciono estan en el README de `docs/incidencias/`.
- **Que alguien anote la hora** la proxima vez que ocurra. Es la pieza que mas
  falta: hay dos logs senalando momentos distintos y ninguno captura lo que
  vivieron los jugadores.
- **REGLA VIGENTE: no entra ningun mod irreversible.** Decision del grupo
  (15/08). Deja CONGELADA la oleada 2 (Common Sense, Take A Bath, Manage
  Containers, Realistic Temperature) y descarta Trailers!. No es por calidad:
  los cuatro son buenos, pero declaran definiciones persistentes y no se
  pueden sacar de un mundo jugado. Criterio y medicion en MODS-LISTA.md
  seccion 0, por si la regla cambia.
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
