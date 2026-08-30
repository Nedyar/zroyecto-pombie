# Mods desfasados: por qué el servidor se cae solo, y qué hacer

**Estado: implementado y verificado (16/08/2026).** Rama
`feat/deteccion-mods-desfasados`. El servidor detecta el desfase solo, avisa
por chat, y reinicia en cuanto queda vacío — nunca con gente dentro. Código en
`docker/modwatch.sh`; 51 pruebas propias en `docker/selftest-modwatch.sh`.

Este documento se escribió primero como estudio, con las tres decisiones que
bloqueaban la implementación. Se deja el estudio completo debajo porque el
razonamiento sigue siendo el que justifica el diseño; después de "Las tres
decisiones, resueltas" está lo que se construyó de verdad.

---

## El síntoma

Los jugadores no pueden entrar. Les sale:

> La versión del artículo de la workshop es diferente a la del servidor

Y reinstalar los mods desde el propio juego **no arregla nada**, porque el
desajuste no está en su lado.

## La causa

Steam actualiza los mods de los clientes **sola y sin preguntar**. El servidor
no. Cuando un autor publica una versión nueva, los clientes la cogen esa misma
noche y el servidor se queda con la vieja: a partir de ahí las versiones no
coinciden y **nadie puede entrar**.

No es un fallo del montaje: es la consecuencia directa de `UPDATE_ON_START=false`,
que existe para que Steam no cambie el motor del juego bajo un mundo vivo (ver
[DECISIONES.md](DECISIONES.md), sección 4). Esa protección es correcta y no se
toca. Lo que hay que resolver es su efecto colateral sobre los mods.

## Con qué frecuencia ocurre, medido

Ocurrió el 14/08 (Better Sorting y CleanUI) y otra vez el 15/08 (Run and
Reload). No es mala suerte. Consultando la API pública del Workshop la última
actualización de cada uno de los 24 mods instalados:

| Última actualización | Mods |
| --- | ---: |
| Últimos 7 días | **9 de 24** |
| Últimos 14 días | **15 de 24** |
| Últimos 30 días | 16 de 24 |
| Más de 100 días | 8 de 24 |

El reparto es bimodal: **16 mods vivos** y 8 dormidos (102 a 587 días sin
tocarse). De los vivos, 9 se actualizaron en una sola semana.

**Eso es al menos 1,3 publicaciones al día sobre el conjunto**, o sea que el
servidor se rompe casi a diario. Y hay motivo: Build 42 pasó a estable el
29/07/2026 y los autores están portando a toda velocidad. Cabe esperar que el
ritmo baje con los meses, pero no a corto plazo.

Consecuencia para el diseño: **una herramienta de diagnóstico manual no
resuelve nada**. Avisaría de algo que ya se sabe, porque el aviso llega cuando
alguien no puede entrar.

## El hallazgo que abarata la solución

Verificado el 15/08 al arreglarlo: **reiniciar el servidor actualiza los mods
pero NO toca el motor del juego.**

```
[11:12:15] Version verificada: buildid 24574884   <- el mismo de antes
```

Son dos mecanismos independientes:

- `UPDATE_ON_START=false` impide que el contenedor ejecute `app_update` sobre
  el juego (app 380870).
- Los **mods del Workshop** los descarga el propio servidor de PZ al arrancar,
  por su cuenta. En el log se ve `GetItemState()=NeedsUpdate` seguido de la
  descarga.

Y la guarda de `buildid` sigue vigilando en cada arranque.

**Un reinicio automático, por tanto, no compromete la protección contra
cambios de versión del juego.** Esto se daba por supuesto al revés, y era
falso: es lo que hace viable la opción 3.

## Lo que cuesta un reinicio, cronometrado

Medido en el reinicio del 15/08, con backup incluido:

| | |
| --- | --- |
| Señal de parada → apagado limpio | **21 s** |
| Arranque → servidor listo | **~15 s** |
| Hasta `healthy` | ~45 s |

**Menos de un minuto de corte.**

---

# Las tres opciones

## 1. Script de comprobación manual

`./scripts/check-mods.sh` compara el manifiesto de Steam del servidor
(`appworkshop_108600.acf`, campo `timeupdated` por mod) contra la API pública
`ISteamRemoteStorage/GetPublishedFileDetails`, y dice qué mods están
desfasados y desde cuándo.

Ya se ha usado dos veces a mano y funciona. Coste: bajo. Riesgo: ninguno.

**Pero no resuelve el problema**, solo lo diagnostica más rápido. Con una
rotura diaria, sigue dependiendo de que alguien esté disponible.

*Detalle de implementación aprendido*: hay que sacar los IDs de
`steamapps/workshop/content/108600/` (las carpetas realmente instaladas), **no**
con una expresión regular sobre el `.acf`. El fichero contiene también números
de manifiesto de 10 dígitos que coinciden con IDs de Workshop reales y
producen falsos positivos — pasó al escribirlo.

## 2. Aviso automático

Lo mismo, ejecutado periódicamente, avisando por el canal que sea. Permite
enterarse antes de que se queje nadie.

Mejora el tiempo de reacción, pero **el servidor sigue roto hasta que alguien
actúa**.

## 3. Reinicio automático al detectar desfase *(recomendada)*

Comprobar cada 30-60 min. Si hay desfase **y no hay nadie conectado**, backup y
reinicio. Si hay gente dentro, no se toca nada: se anota y se reintenta luego.

Con esto el problema **desaparece** sin echar a nadie nunca. La ventana de
rotura pasa de "hasta que alguien esté disponible" a "hasta que el servidor
esté vacío", que de madrugada es inmediato.

Es viable precisamente por el hallazgo de arriba: el reinicio no toca el motor
del juego, y la guarda de `buildid` sigue protegiendo.

---

# Las tres decisiones, resueltas (15-16/08/2026)

## 1. ¿Qué hacer si hay gente conectada muchas horas seguidas?

**Resuelto: solo si está vacío, sin excepción.** Decisión del grupo (15/08),
tomada explícitamente: se avisa una vez por chat de que hay mods desfasados y
que el servidor reiniciará solo en cuanto quede vacío; los de dentro siguen
jugando sin que nadie los eche. Quien intente entrar mientras tanto no podrá
—es el problema de hoy, sin cambios—, pero ya no depende de que alguien esté
disponible para arreglarlo: en cuanto la sesión termine, se resuelve solo.

Se descartaron las otras dos opciones que barajaba el estudio (reiniciar tras
un plazo fijo, o reiniciar siempre tras un aviso corto) precisamente porque
ambas implican expulsar a alguien de su propia partida en un juego de muerte
permanente. "Solo si está vacío" es la única que no le cuesta el personaje a
nadie.

## 2. Aceptar actualizaciones automáticas es aceptar lo que publique el autor

**Resuelto: riesgo asumido, mitigado en cuatro capas** (detalladas más abajo,
sección "Mitigación del riesgo"). No hay alternativa real —los clientes se
actualizan solos y el servidor debe coincidir, o nadie entra—, pero ya no es
un descuido silencioso: hay un backup insaltable justo antes de cada apertura
del mundo, una verificación automática después del reinicio, un rastro
completo de qué mod y cuándo provocó cada reinicio, y una vía de salida
garantizada (todo mod del mundo es reversible por diseño, ver
[MODS-LISTA.md](MODS-LISTA.md) sección 0).

## 3. ¿Dónde vive el temporizador?

**Resuelto: dentro del contenedor, y la objeción original era falsa.** El
estudio asumía que "un proceso no puede reiniciar su propio contenedor", pero
no hace falta: los mods los descarga el propio JVM de Project Zomboid al
arrancar, no `app_update` sobre el contenedor. Basta con apagar el JVM
limpiamente (la misma secuencia `save`+`quit` de siempre) y relanzarlo **dentro
del mismo contenedor**, sin tocar Docker para nada. `docker/run.sh` ya lanzaba
el servidor como un hijo al que le hacía `wait`; ahora ese lanzamiento vive
dentro de un bucle que se repite en cada apertura del mundo, la primera vez
igual que las siguientes.

Consecuencia: cero lógica fuera del repo. Nada de systemd, nada de socket de
Docker, nada que se comporte distinto en otra máquina.

---

# Cómo funciona, implementado

## Detección (`docker/modwatch.sh`)

Compara dos fechas por cada mod activo:

- **Local**: el `timeupdated` de dentro de `WorkshopItemsInstalled` en el
  manifiesto `appworkshop_*.acf` de Steam. **No** cualquier `timeupdated` del
  fichero: existe una segunda sección, `WorkshopItemDetails`, con su propio
  `timeupdated` (y un `latest_timeupdated` que además contiene la palabra como
  substring) y valores **distintos**. Verificado contra el manifiesto real:
  24 mods dan 72 apariciones de la cadena "timeupdated", 3 por mod. El
  parseo sigue la profundidad de llaves del fichero y solo mira dentro de
  `WorkshopItemsInstalled`, así que no hay forma de que la trampa cuele.
- **Remoto**: un único POST a `ISteamRemoteStorage/GetPublishedFileDetails`
  con todos los IDs activos a la vez —nunca uno por mod, para no arriesgarse
  a que la API limite las llamadas.

Desfasado ⇔ remoto > local. Un mod sin datos (API caída, o retirado del
Workshop) se marca **`sin-datos`**, nunca `ok` ni `desfasado`: un fallo al
medir no puede disfrazarse de "todo bien" ni de "hay que reiniciar".

Los IDs activos son la **intersección** de lo configurado
(`PZ_WORKSHOP_ITEMS`) con lo que hay de verdad en
`steamapps/workshop/content/<appid>/`. Igual que aprendió `cmd_mods`: nunca se
sacan IDs con una expresión regular sobre el `.acf` completo, porque contiene
números de manifiesto de 10 dígitos que pueden coincidir con IDs reales.

## El bucle vigilante

Cada `MODS_CHECK_INTERVAL_MINUTES` (30 por defecto) comprueba. Si hay
desfase:

1. Avisa una vez por chat (`servermsg`) y pasa a sondear cada
   `MODS_EMPTY_POLL_SECONDS` (120 por defecto) cuántos jugadores hay, en vez de
   seguir llamando a la API de Steam.
2. En cuanto el servidor queda vacío: guarda qué mods lo provocaron, apaga
   limpio (`save` → `quit` → esperar al JVM, la secuencia de siempre) y pide
   reabrir el mundo.
3. El proceso padre (`docker/run.sh`) ve la petición, toma un backup **antes**
   de reabrir (etiqueta `pre-mods`), y relanza el servidor **en el mismo
   contenedor**. `guard_buildid` se revalida en esa apertura igual que en
   cualquier otra: el motor no puede cambiar por esta vía.
4. Sigue vigilando después, exactamente igual que antes del reinicio.

**Backoff**: si tras reabrir el mismo conjunto de mods sigue desfasado (un
mod que no se puede sincronizar, o se retiró del Workshop), el vigilante avisa
fuerte y **no vuelve a reintentar solo** con ese conjunto. Sin esto, un mod
imposible de sincronizar reiniciaría el servidor cada 30 minutos toda la
noche. Dos matices que salieron de la revisión, ambos con prueba propia:

- La clave del backoff es **id + fecha publicada**, no solo el id: si el
  autor publica *otra* versión mientras el conjunto está atascado, la fecha
  cambia y eso cuenta como intento legítimo nuevo, no como insistencia.
- El backoff **se resetea** cuando un chequeo con la API viva confirma 0
  desfasados. Sin ese reset, la segunda actualización legítima del mismo mod
  quedaba bloqueada para siempre — y con autores que publican dos veces en
  24 h (CleanUI la semana del 14/08), ese era el caso más probable, no una
  rareza. Un apagón de la API no resetea nada: "todos sin datos" no es
  "todos curados".

## Mitigación del riesgo (decisión 2, en detalle)

Aceptar lo que publique cada autor no se puede evitar, pero sí acotar:

1. **Backup `pre-mods` insaltable.** Se toma con el mundo ya quieto (JVM
   muerto, el estado más consistente posible) justo antes de abrir con el mod
   nuevo. A diferencia del `prestart` normal, este **nunca se salta** por el
   guarda de "ya hay uno reciente": es exactamente el punto de restauración
   que hace falta si el mod actualizado resulta romper algo. Rota igual que
   `prestart`/`periodic` (`BACKUP_KEEP`, ~2 semanas de historial a este ritmo);
   eternizarlo acumularía ~2 GB/mes sin aportar nada pasado ese margen.
2. **Verificación automática tras el reinicio.** El vigilante comprueba que el
   servidor vuelva a estar operativo (mismo `wait_for_ready` de siempre) y
   cuenta `required mod not found` y `ERROR` **fuera del frame de carga**
   (`f:0`, el mismo criterio que ya usan `docs/incidencias/*.md` para no
   confundir ruido de arranque con un problema real —decenas de ERROR en la
   carga son *normales*, verificado con un reinicio real: 148 ERROR totales,
   los 148 con `f:0`, 0 fuera de él). El resultado queda escrito y visible en
   `docker/run.sh status`.
3. **Rastro de auditoría.** Cada reinicio automático deja constancia de qué
   mods lo causaron y cuándo, además del resultado de la verificación. Si
   aparece un síntoma nuevo en el juego, la pregunta "¿qué cambió justo antes?"
   tiene respuesta con fecha exacta.
4. **Vía de salida garantizada.** Por la regla "nada irreversible"
   ([MODS-LISTA.md](MODS-LISTA.md) sección 0, medida fichero a fichero),
   cualquier mod del mundo puede retirarse sin dejar nada roto. Si una
   actualización resulta mala, el runbook es: restaurar `pre-mods` si hizo
   falta, quitar el mod de la lista, relanzar. Detalle completo en
   [OPERACIONES.md](OPERACIONES.md).

## RESUELTA el mismo día: el jugador rechazado ya no bloquea

La limitación de abajo se arregló el propio 16/08 con `players_in_game()` en
`docker/modwatch.sh`. La clave salió de comparar, en el log de conexiones, los
tres casos reales que dejó el incidente: una entrada buena, una salida buena y
el rechazo. El evento **`player-connect` marca el spawn dentro del mundo** —
una entrada real es `connection-details → login-queue-* → player-connect`; el
rechazo muere en `connection-details` y nunca llega.

La regla del grupo queda **intacta**: nunca se reinicia con alguien dentro del
mundo. Lo que cambia es qué significa "dentro": quien nunca llegó a
`player-connect` no está jugando —está en un menú, cargando, o es un rechazo—
y un reinicio no le quita nada más que una pantalla.

El sesgo es deliberadamente conservador, con sus 8 casos de prueba: RCON
caído, log ausente, nombres que no cuadran con el recuento, o un jugador sin
rastro → **cuenta como dentro** y bloquea. Y el primer intento de un fantasma
(aún sin morir, indistinguible de alguien eligiendo personaje) bloquea un
sondeo; en cuanto ese intento muere (~85 s) el patrón queda a la vista y deja
de bloquear.

Se conserva la limitación original escrita tal cual se encontró, porque
explica el porqué del arreglo:

## La limitación, tal como se encontró (16/08/2026)

Encontrada en producción el **16/08/2026**, con gente esperando para jugar. No
es teórica: pasó, y bloqueó el mecanismo por completo.

**El síntoma.** Modern Status se actualizó y el servidor se quedó atrás. Un
jugador intentó entrar y le salió el aviso del Workshop, como es de esperar.
Pero sus intentos dejaron rastro en el log de conexiones:

```
login → client-connect → connection-details    ...y ahí muere
```

El cliente llega hasta `connection-details` —justo donde compara versiones de
mods—, rechaza la conexión y **la deja medio abierta**. El servidor lo sigue
contando:

```
Players connected (1):
-Nedyar        <- no puede jugar, pero cuenta
```

**Por qué es grave.** El vigilante solo reinicia con el servidor vacío. Con esa
conexión fantasma, `player_count()` nunca devuelve 0, así que **el reinicio
automático no se dispara jamás**. Y como el reinicio es lo único que arreglaría
el desfase, el sistema se cierra sobre sí mismo:

> no puede entrar porque hay desfase → sus reintentos lo cuentan como conectado
> → no se reinicia porque cree que hay gente → sigue el desfase

Se comprobó de la forma más directa: los otros dos jugadores salieron de verdad
y el contador se quedó en 1, con el único "conectado" siendo quien no podía
jugar.

**Cómo se salió ese día**: a mano (backup etiquetado + `docker compose
restart`, ~90 s, que de paso se lleva la conexión fantasma). De las dos vías
de arreglo que se plantearon —distinguir sesiones vivas de conexiones a
medias, o un plazo máximo tras el cual reiniciar avisando— se eligió la
primera, porque mantiene intacta la regla del grupo: el plazo habría acabado
echando también a jugadores reales, que es justo lo que la regla existe para
impedir. El resultado es `players_in_game()`, arriba.

## El caso inverso (17/08): el servidor por delante de los clientes

Al día siguiente de desplegarlo apareció el espejo del problema original.
Better Sorting publicó a las 16:12 UTC; el servidor, vacío a las 16:22, se
actualizó solo — diez minutos después. Perfecto. Pero dos jugadores de la
sesión de esa tarde no pudieron reentrar: su juego, **abierto desde antes de
la publicación**, conservaba la versión vieja. Steam solo actualiza los mods
del Workshop **al arrancar el juego**, así que salir al menú y volver no
basta: hay que cerrarlo del todo.

La firma en los logs, para distinguirlo del caso de ayer: la conexión
**completa** (`Connected new client` en el DebugLog) y se pierde ~1-2 minutos
después (`connection-lost` de RakNet). El servidor está sano; es el cliente el
que, al comparar versiones, se queda en su aviso hasta caducar.

### Por qué NO se arregló con un margen de gracia

La tentación obvia es que el servidor espere unas horas antes de actualizarse,
para dar tiempo a Steam a repartir. **Se descartó a propósito, y conviene que
el porqué quede escrito antes de que alguien lo "arregle" así:**

- Quien **arranca el juego de cero** recibe la versión NUEVA en ese momento.
  Con un servidor retrasado, esa persona queda fuera **sin remedio propio**:
  no puede degradar su mod. Es el problema original, el que exigía un
  administrador despierto.
- Quien **tenía el juego abierto** conserva la vieja. Con el servidor al día
  queda fuera, pero su remedio es **autoservicio e inmediato**: cerrar y
  abrir el juego.

Un margen de gracia solo mueve el bloqueo del segundo grupo al primero — y el
primero no puede arreglárselo solo. El desfase entre clientes es inevitable
mientras Steam los actualice de forma asíncrona; lo único que se elige es qué
lado favorecer, y se favorece al que tiene salida.

### Lo que se arregló de verdad: el aviso llega con la instrucción, y a todos

Dos cambios en el vigilante, con sus pruebas:

1. **El aviso lleva el remedio**, no solo la noticia: *"al salir, CERRAD el
   juego del todo y volved a abrirlo; si no, Steam no os actualiza el mod y no
   podréis reentrar"*. Quien más lo necesita oír es exactamente quien está
   dentro cuando se anuncia — los que hoy quedaron fuera.
2. **Quien entra durante la espera también lo recibe.** El aviso original se
   emitía una sola vez; quien se conectara después no lo veía, y era candidato
   perfecto al bloqueo (entró con la versión vieja, la que el servidor aún
   tenía). Ahora, cuando el recuento de jugadores sube durante la espera, se
   reenvía — y solo entonces: ni spam a los mismos, ni mensajes al vacío.

### El remedio, si le pasa a alguien

Cerrar Project Zomboid **del todo** (no al menú: cerrar), esperar unos
segundos a que Steam actualice, y volver a entrar. Si no basta: desuscribirse
y resuscribirse al mod en el Workshop. Está contado en llano en
[MODS-ADOPTADOS.md](MODS-ADOPTADOS.md).

## Lo que el vigilante NO cubre, demostrado el mismo 17/08: el motor del juego

Horas después del caso inverso llegó su hermano mayor, y confundirlos costó
una hora de diagnóstico. Mismo síntoma exacto (nadie entra, colgado en
"uniéndose al juego", conexión que completa y muere), pero **ningún mod
desfasado: era el JUEGO**. The Indie Stone publicó el hotfix **42.20.3** a las
12:18 UTC; los clientes se actualizaron solos por la tarde — con más motivo
tras seguir el consejo de "cerrad y abrid el juego" del caso anterior — y el
servidor seguía en 42.20.2 (`buildid 24574884` frente a `24775771`).

El vigilante no toca el motor **a propósito** (decisión 4 de DECISIONES.md:
el binario solo cambia por decisión humana, vía `./scripts/update-server.sh`).
Eso significa que **este caso siempre requerirá intervención manual**, y está
bien que así sea. Lo que se puede mejorar es reconocerlo rápido.

**Cómo distinguir los tres casos con el mismo síntoma "no puedo entrar":**

| Comprobación | Resultado | Diagnóstico |
| --- | --- | --- |
| `./scripts/check-mods.sh` | hay desfasados | mods del servidor atrás → esperar al reinicio automático |
| check-mods 0 desfasados + el cliente cerró y abrió el juego | sigue fallando | seguir abajo |
| Noticias de PZ (`ISteamNews`, appid 108600) o `steamcmd app_info_print 380870` vs `buildid disco` de `status` | hay build nuevo | **hotfix del juego** → `./scripts/update-server.sh` (o su equivalente sobre staging) |

Falsas pistas que se descartaron con datos, para no volver a perseguirlas: el
WARN `No packet handler for type: Drink...` de `PacketsCache.<init>` aparece
en cada conexión **también en los arranques sanos** (12 veces en el arranque
bueno del 16-17/08); y Better Sorting quedó exonerado retirándolo en caliente
y comprobando que el cuelgue seguía — se devolvió a su posición.

Pendiente de decidir (no implementado): que el vigilante compare también el
`buildid` público de Steam con el instalado y **avise** —solo avisar, nunca
actualizar— cuando haya hotfix del juego. Habría convertido esta hora de
diagnóstico en una línea de log.

### Volvió a pasar el 27/08, y con una variante peor

42.20.4 salió el 26/08. Esta vez **solo un jugador quedó fuera**: el que había
reinstalado el juego y por tanto tenía la versión nueva. Los demás seguían en
42.20.3, igual que el servidor, y entraban sin problema.

Eso hace el diagnóstico mucho más difícil, porque la intuición apunta al
jugador que falla — y **es el único que está bien**. La pista que lo resuelve
en segundos es la ruta del fichero del error: si empieza por
`steamapps\common\ProjectZomboid\`, es el **juego base** y ningún mod puede
tener la culpa; si empieza por `steamapps\workshop\`, entonces sí es un mod.

Refuerza el argumento de arriba: **este es el segundo hotfix seguido que
cuesta una hora de diagnóstico.** El aviso automático de "hay build nuevo del
juego" pasa de mejora cómoda a claramente rentable. Sigue sin implementarse
porque nadie lo ha pedido, no porque haya dudas de diseño: sería una
comparación más dentro del chequeo que ya se hace cada 30 minutos, y **solo
avisaría** — actualizar el motor seguiría siendo decisión humana.

Procedimiento completo (diagnóstico y actualización, incluido el atasco
`state is 0x6` de SteamCMD, que ya ha salido las dos veces) en
[OPERACIONES.md](OPERACIONES.md).

## 30/08: un mod que publica DOS veces en una hora

Primera vez que ocurre, y deja ver el límite de la ventana de 30 minutos.

```
17:04 UTC  ClassicBows publica
17:31      el vigilante lo detecta y avisa
17:33      servidor vacío → reinicio automático
17:34      verificación OK, 0 mods faltantes          ✅ todo solo
18:04      ClassicBows publica OTRA VEZ
18:20      los jugadores no pueden entrar
18:33      (le habría tocado el siguiente chequeo)
```

**El sistema no falló**: la segunda publicación cayó dentro de su ventana de
30 minutos y la habría resuelto a las 18:33. Se adelantó a mano solo porque
había gente esperando.

**Lo que sí valida este caso es el arreglo de la revisión del 16/08.** La clave
del backoff incluye la fecha publicada, no solo el id:

```
1er reinicio:  3776949545:1788109476
2ª publicación: 3776949545:1788113072   ← distinta, no la bloquea
```

Con la versión original —que comparaba solo el id— esto se habría leído como
"el mismo mod sigue desfasado tras reiniciar", habría entrado en backoff y el
servidor **se habría quedado bloqueado indefinidamente**. Era el caso hipotético
que motivó el cambio; hoy ocurrió de verdad.

**Decisión pendiente**: bajar `MODS_CHECK_INTERVAL_MINUTES` de 30 a 10-15. El
coste es solo más llamadas a la API de Steam (una por chequeo, con todos los
ids juntos), y reduciría a un tercio la ventana en la que un mod recién
publicado deja fuera a la gente. Con el ritmo medio (~1,3 publicaciones/día
sobre 34 mods) los 30 minutos bastan; con autores que publican dos veces por
hora, no. **Sin decidir: es cambio de configuración y lo decide el usuario.**

## Cómo se desactiva

`MODS_CHECK_INTERVAL_MINUTES=0` en el `.env` apaga toda la vigilancia: el
servidor vuelve a comportarse exactamente como antes de esta funcionalidad,
sin aviso ni reinicio automático.

## Verificación hecha

- 51 pruebas en `docker/selftest-modwatch.sh`, en verde tanto en el host
  (gawk) como **dentro del contenedor real (mawk)** — la diferencia importa:
  el parseo del `.acf` evita a propósito el `match()` de 3 argumentos, una
  extensión de gawk que mawk no tiene.
- Una revisión adversarial posterior (16/08) encontró y corrigió, con prueba
  nueva cada uno: el backoff sin reset (arriba), la ausencia de guarda si el
  JVM viejo no muriera antes de relanzar (ahora aborta el contenedor entero
  antes que abrir dos servidores sobre el mismo mundo), el plazo de la
  verificación post-reinicio (180→600 s: ese arranque es justo el que
  descarga los mods nuevos), y el saneado de títulos con tabuladores en el
  informe TSV.
- `selftest-backups.sh` sigue en verde (41 pruebas): la reestructuración de
  `cmd_serve` en un bucle no le afecta.
- **Simulacro de extremo a extremo** contra el volumen real de producción
  (parada, sin exponer puertos: `docker compose run --rm --no-deps`), con un
  mod forzado a "desfasado": detección → aviso (nadie conectado, se saltó) →
  servidor vacío → apagado limpio → backup `pre-mods` tomado y verificado →
  `guard_buildid` revalidada sin cambio de `buildid` → reapertura sin repetir
  el backup → verificación post-reinicio OK → backoff correcto en el segundo
  ciclo. Y de propina: un `docker stop` real (la vía normal de apagado)
  durante el ciclo demostró que el trap de señales sigue funcionando igual
  con la nueva estructura del bucle.
- **Desplegado en staging** (16/08, servidor vacío en el momento del cambio):
  backup `prestart` y vigilante arrancado correctamente en el arranque real.

## Qué NO hace este mecanismo

- No toca `UPDATE_ON_START` ni la guarda de `buildid`: el motor del juego solo
  cambia por `./scripts/update-server.sh`, nunca por un reinicio automático.
- No añade ni quita mods de la lista: solo actualiza los que ya están.
- No reinicia nunca con jugadores dentro.
- No vive nada fuera del repo (sin systemd, sin cron del host, sin socket de
  Docker).

---

## Lo que NO hay que hacer

**Poner `UPDATE_ON_START=true`.** Resolvería el desfase de mods de paso, pero
reabriría el agujero que esa opción cierra: cualquier reinicio rutinario un día
que Steam haya publicado un parche cambiaría el motor bajo el mundo. Es
exactamente el escenario que este montaje existe para evitar.
