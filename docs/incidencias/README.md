# Incidencias

Una incidencia por fichero, numerada. Formato de issue: síntoma, evidencia,
causa, propuesta, y **qué no está probado**.

Existen porque el resto de `docs/` describe cómo funciona el montaje, y esto es
otra cosa: lo que está roto, con las pruebas en la mano y sin haberlo tocado
todavía. Investigar y arreglar son fases distintas y conviene que se vean
separadas en el historial.

| # | Incidencia | Estado |
| --- | --- | --- |
| [001](001-cadaveres-no-looteables.md) | Cadáveres que no aparecen como contenedor y no se pueden registrar | Diagnosticada, propuesta lista |
| [002](002-bicycle-api-inexistente.md) | Bicycle! llama a una API que 42.20 eliminó | Diagnosticada, impacto sin determinar |
| [003](003-mtu-tailscale-fragmentacion.md) | MTU del contenedor mayor que el de la ruta real | Confirmada, impacto sin determinar |
| [004](004-sintomas-sin-diagnosticar.md) | Tres síntomas más, sin causa identificada | Abierta |

## Cómo se investiga aquí

Tres reglas que salieron de equivocarse en esta misma investigación, y que
conviene respetar en la siguiente:

**El error más numeroso no es el más importante.** Un fallo puede generar miles
de líneas porque se repite sobre los mismos cuatro objetos. Se cuenta por
*causas distintas*, no por líneas.

**Mira el nivel de severidad antes de citar nada.** Una línea `LOG` no es un
error. Presentar 300 líneas informativas como prueba invalida el análisis
entero.

**Sin línea base no hay anomalía.** Decir que 172 errores por hora es mucho
exige saber cuántos tiene un servidor sano. Si no se tiene esa referencia, se
dice que no se tiene.

Y para correlaciones temporales: calcula qué esperarías **por azar** antes de
declarar que dos cosas van juntas. Un 40% de coincidencia parece mucho y puede
ser menos de lo que da el azar si las ventanas cubren media línea temporal.
