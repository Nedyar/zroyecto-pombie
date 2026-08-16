# Mods desfasados: por qué el servidor se cae solo, y qué hacer

**Estado: implementado y verificado (16/08/2026).** Rama
`feat/deteccion-mods-desfasados`. El servidor detecta el desfase solo, avisa
por chat, y reinicia en cuanto queda vacío — nunca con gente dentro. Código en
`docker/modwatch.sh`; 30 pruebas propias en `docker/selftest-modwatch.sh`.

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
noche.

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

## Cómo se desactiva

`MODS_CHECK_INTERVAL_MINUTES=0` en el `.env` apaga toda la vigilancia: el
servidor vuelve a comportarse exactamente como antes de esta funcionalidad,
sin aviso ni reinicio automático.

## Verificación hecha

- 30 pruebas en `docker/selftest-modwatch.sh`, en verde tanto en el host
  (gawk) como **dentro del contenedor real (mawk)** — la diferencia importa:
  el parseo del `.acf` evita a propósito el `match()` de 3 argumentos, una
  extensión de gawk que mawk no tiene.
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
