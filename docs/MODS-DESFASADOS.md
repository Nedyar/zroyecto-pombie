# Mods desfasados: por qué el servidor se cae solo, y qué hacer

**Estado: estudio, nada implementado.** Rama `feat/deteccion-mods-desfasados`.
Se escribe antes de tocar código para que la decisión se tome con los datos
delante y no en caliente el día que vuelva a pasar.

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

# Las tres decisiones pendientes

Nada se implementa hasta que estén resueltas.

## 1. ¿Qué hacer si hay gente conectada muchas horas seguidas?

Con la regla "solo si está vacío", una sesión larga bloquea la actualización.
Los que ya están dentro siguen jugando sin problema, pero **quien intente
entrar nuevo no podrá** — y esa persona no tiene forma de saber por qué.

Opciones: avisar por chat y reiniciar igualmente pasado un plazo; esperar
indefinidamente; o avisar y dejar que decidan ellos.

## 2. Aceptar actualizaciones automáticas es aceptar lo que publique el autor

Un mod puede actualizarse **a peor** y romper algo. Hoy eso se descubriría
después de que el servidor ya lo haya cogido.

No hay alternativa real —los clientes se actualizan solos y el servidor debe
coincidir, o nadie entra— pero conviene que conste como riesgo asumido y no
como descuido. La mitigación existente es el backup previo a cada arranque.

## 3. ¿Dónde vive el temporizador?

- **Dentro del contenedor**, como el bucle de backups periódicos de
  `docker/run.sh`. Más coherente con el repo: toda la lógica vive dentro y se
  comporta igual en cualquier máquina. Pero un proceso no puede reiniciar su
  propio contenedor.
- **Fuera, con systemd de usuario** (hay linger habilitado). Puede reiniciar el
  contenedor sin problema, pero es lógica que vive fuera del repo y rompe la
  propiedad de "se despliega en otra máquina y funciona igual".

Esta es la que más condiciona el diseño y no tiene respuesta obvia.

---

## Lo que NO hay que hacer

**Poner `UPDATE_ON_START=true`.** Resolvería el desfase de mods de paso, pero
reabriría el agujero que esa opción cierra: cualquier reinicio rutinario un día
que Steam haya publicado un parche cambiaría el motor bajo el mundo. Es
exactamente el escenario que este montaje existe para evitar.
