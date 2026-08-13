# Incidencias

Una incidencia por fichero, numerada. Formato de issue: síntoma, evidencia,
causa, propuesta, y **qué no está probado**.

Existen porque el resto de `docs/` describe cómo funciona el montaje, y esto es
otra cosa: lo que está roto, con las pruebas en la mano y sin haberlo tocado
todavía. Investigar y arreglar son fases distintas y conviene que se vean
separadas en el historial.

| # | Incidencia | Estado |
| --- | --- | --- |
| [001](001-cadaveres-no-looteables.md) | Cadáveres que no aparecen como contenedor y no se pueden registrar | **Diagnóstico REFUTADO**, síntoma abierto |
| [002](002-bicycle-api-inexistente.md) | Bicycle! llama a una API que 42.20 eliminó | Diagnosticada, impacto sin determinar |
| [003](003-mtu-tailscale-fragmentacion.md) | MTU del contenedor mayor que el de la ruta real | Confirmada, **descartada** como causa de 005 |
| [004](004-sintomas-sin-diagnosticar.md) | Tres síntomas más, sin causa identificada | Abierta, **reproducida sin los mods sospechosos** |
| [005](005-desincronizacion-al-conducir.md) | Teletransportes y muros de mapa sin cargar al conducir por ciudad | Analizada, causa acotada, **no son los mods** |

## Lo que el servidor vanilla ya ha resuelto

Se levantó para poder distinguir "esto lo rompe un mod" de "esto es así en Build
42". Ha respondido **cuatro veces, y las cuatro la respuesta fue que no eran los
mods**:

- La 001 culpaba a `StarvingZombies` de los cadáveres no registrables. En vanilla,
  sin ese mod, el fallo es **más del doble de frecuente**.
- La 005 investigaba si los teletransportes venían de los mods. En vanilla, sin
  ninguno, la desincronización es **varias veces más frecuente**.
- La 002 apoyaba su sospecha sobre `Bicycle!` en una firma de 4.541 líneas. Esa
  firma aparece a tasa comparable en el vanilla **sin ningún mod**.
- La 004 tenía como sospechosos naturales a los seis mods de inventario. Los
  síntomas 1 y 2 **se reprodujeron el 12/08 en el vanilla**, que no lleva
  ninguno de los seis.

Merece la pena retener el patrón: **cuatro de cuatro**. Cada vez que una firma
llamativa se atribuyó a un mod, resultó igual o más frecuente sin él. La
reacción natural habría sido retirar mods, y las cuatro veces habría costado
tiempo sin arreglar nada.

## Cómo se investiga aquí

Reglas que salieron de equivocarse en estas mismas investigaciones, y que
conviene respetar en la siguiente:

**El error más numeroso no es el más importante.** Un fallo puede generar miles
de líneas porque se repite sobre los mismos cuatro objetos. Se cuenta por
*causas distintas*, no por líneas.

**Mira el nivel de severidad antes de citar nada.** Una línea `LOG` no es un
error. Presentar 300 líneas informativas como prueba invalida el análisis
entero.

**Sin línea base no hay anomalía.** Decir que 172 errores por hora es mucho
exige saber cuántos tiene un servidor sano. Si no se tiene esa referencia, se
dice que no se tiene. *(Esa referencia ya existe: **~16 `ERROR`/h y ~2 causas
distintas** en cliente, medida sobre la sesión del 11/08 en el vanilla con cero
mods. Detalle y salvedades en la [004](004-sintomas-sin-diagnosticar.md).)*

**Calcula el azar antes de declarar una correlación.** Un 40% de coincidencia
parece mucho y puede ser menos de lo que da el azar si las ventanas cubren media
línea temporal.

**Dos firmas juntas en un extracto no van emparejadas.** Se dio por hecho en la
[005](005-desincronizacion-al-conducir.md) porque aparecían cerca al leer el log,
y al sacar la distribución por minuto resultaron **casi disjuntas**. Si vas a
afirmar que dos cosas ocurren juntas, sácalas por minuto y míralo.

**Cuidado con el sesgo de detección.** Una ventana con más líneas de log tendrá
más de todo, incluida la señal que buscas. Normaliza en tasa —sucesos entre
muestras—, nunca en recuento absoluto. En la 005 esto casi produce la conclusión
falsa de que el servidor se había atascado: el minuto sospechoso tenía 6 parones
porque tenía 39 muestras, y en tasa no destacaba sobre minutos sin ninguna queja.

**Normaliza también por actividad, no solo por tiempo.** Un servidor con 12 h de
reloj y nadie dentro no es comparable con 2 h de cuatro jugadores. Mira las
conexiones antes de dividir por horas.

## Cómo conseguir datos del cliente

La mitad de los síntomas de este proyecto **no dejan rastro en el servidor**: el
mapa que no carga, los tirones, las correcciones de posición. Esos logs viven en
`%USERPROFILE%\Zomboid\Logs\` de cada jugador y hay que pedirlos.

Lo que funcionó en la 005 fue pasarle a un agente en la máquina del jugador un
encargo con cuatro cosas:

1. **Las ventanas horarias exactas** y en qué zona horaria están, para que las
   pueda cruzar sin adivinar.
2. **Qué se sabe ya desde el servidor**, para que no lo repita.
3. **Las reglas de arriba**, explícitas. Sin ellas devuelve recuentos de líneas.
4. **El encargo de REFUTAR**, con la lista concreta de hallazgos que tumbarían la
   hipótesis. Pedirle que confirme produce confirmación.

Dos avisos prácticos: **no hace falta administrador** —todo está en el perfil del
usuario, y elevar con otra cuenta hace que no encuentre nada—, y conviene
**cerrar el juego** antes, porque mantiene `console.txt` abierto en escritura.

Y una limitación que hay que decir siempre: **un cliente es un cliente**. Los
errores del servidor son la suma de todos los conectados, así que "aquí está
limpio" no significa "no pasó".
