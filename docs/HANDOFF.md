# Handoff: estado del despliegue

Lo primero que hay que leer para retomar el trabajo. Describe **como esta
desplegado ahora**, que esta verificado y que no, y que queda pendiente.

Los datos propios de la instancia (IPs, correos, contrasenas) **no estan aqui a
proposito**: viven en `.env`, que no se versiona. Este documento describe la
forma del despliegue, no sus valores.

---

## Estado en una linea

**El servidor esta levantado y sano. Ya se ha jugado: 4 jugadores simultaneos
durante una sesion larga, sin caidas. Hay bugs de jugabilidad abiertos.**

## Que hay montado

| | |
| --- | --- |
| Anfitrion | Linux (Ubuntu 24.04), portatil usado como servidor, lid ignorado |
| Docker | **rootless**, daemon de usuario, sin grupo `docker` |
| Exposicion | **Tailscale**, sin puertos abiertos en el router |
| Juego | Build 42, `buildid` registrado y coincidente con el instalado |
| Mods | 33 elementos del Workshop + 1 local (`TariqsBeardsB42`) |
| Memoria | heap 6g, `mem_limit` 10g |
| Backups | automatico al arrancar + cada 6 h |

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
- **Varios clientes a la vez se distinguen bien** pese a compartir IP de origen
  por el reenvio UDP de rootless. Era una incognita y quedo resuelta jugando.
- **Steam Relay no estorba** contra un servidor que solo existe dentro del
  tailnet. Tambien era incognita.
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
`docs/incidencias/`. Cuatro incidencias, cada una con su seccion de lo que NO
esta probado. Leerlas antes de tocar mods: hay una hipotesis ya refutada con
datos y no conviene volver a recorrerla.

Aviso metodologico que costo tiempo aprender: el error mas numeroso del log
**no** era el relevante. Se cuenta por causas distintas, no por lineas.

## NO verificado

1. **Que el servidor vuelva solo tras un reinicio.** El daemon rootless y el
   linger estan habilitados, pero hay una carrera sin probar: si Docker arranca
   antes de que exista la interfaz de Tailscale, el bind falla. `restart:
   unless-stopped` deberia recuperarlo.
2. **Que los mods hagan lo que prometen en juego.** Para eso esta
   [CHECKLIST-MODS.md](CHECKLIST-MODS.md), que ya lleva buena parte marcada.
3. **Cual es la linea base de errores** de un B42.20 multijugador sano. Sin ese
   dato no se puede calificar de anomalo el volumen de errores del cliente, y
   eso condiciona varias de las incidencias abiertas.

## Pendiente

- Decidir sobre la incidencia 001: retirar `StarvingZombies`. Requiere reinicio.
- Cada jugador necesita su **propia copia del mod local** en su carpeta
  `Zomboid\mods`. El servidor no puede enviarselo.
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
