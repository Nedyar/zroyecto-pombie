# 003 — El contenedor anuncia un MTU mayor que el de la ruta real

**Estado:** desajuste confirmado · **descartado como causa de la [005](005-desincronizacion-al-conducir.md)** · nada aplicado
**Componente:** infraestructura de este despliegue, no el juego ni los mods

> **Puesto a prueba el 13/08/2026 y no se disparó.** Durante la sesión completa
> del 12/08 —18 h, cuatro jugadores, con los episodios que investiga la 005
> dentro— el contador `FragOKs` del host **no se movió de 154**, con la máquina
> arrancada desde hacía 6 días. Cero datagramas fragmentados en toda la sesión.
> El desajuste sigue siendo real y sigue mereciendo arreglarse, pero **no explica
> ninguno de los síntomas reportados**.

## Síntoma

Ninguno atribuible directamente. Es una incoherencia de configuración
encontrada al investigar la desincronización de objetos, y es **nuestra**, no de
un tercero.

## Evidencia

```
contenedor (donde escribe el juego)   MTU 1500
tailscale0 (por donde sale de verdad) MTU 1280   <-- mas pequeño
LAN                                   MTU 1500
```

El juego escribe datagramas creyendo que dispone de 1500 bytes, pero la ruta
real hacia los jugadores pasa por WireGuard, que da 1280. Los que superan ese
tamaño hay que fragmentarlos.

Contadores de fragmentación IP del host:

```
FragOKs      154      datagramas que hubo que partir
FragCreates  308      fragmentos generados (≈2 por datagrama)
FragFails      0
```

Y en el socket del juego, dentro del contenedor, **cero pérdidas**:

```
Udp: InDatagrams 4125805  InErrors 0  RcvbufErrors 0  SndbufErrors 0
```

## Por qué importa aunque el volumen sea bajo

Un datagrama UDP fragmentado se pierde **entero** si se pierde uno solo de sus
fragmentos, y UDP no retransmite. En un juego, los paquetes grandes suelen ser
precisamente los de estado del mundo: creación de objetos, sincronización de
zonas. Perder uno no da error en ningún sitio; simplemente el cliente nunca se
entera de que ese objeto existe, y a partir de ahí acumula errores por cada
actualización posterior que reciba sobre él.

Eso encajaría con el patrón observado en el cliente: **pocos objetos
desconocidos generando miles de líneas de error**. Pero 154 datagramas
fragmentados es poco para explicar el volumen, así que como causa principal es
flojo.

## Lo que NO está probado

- **Que se haya perdido un solo fragmento.** `FragFails=0` y no hay pérdidas en
  el socket. No hay medición de pérdida extremo a extremo.
- ~~Que la fragmentación tenga relación con ninguno de los síntomas reportados.~~
  **Resuelto en negativo**: no hubo fragmentación durante la sesión que produjo
  los síntomas, así que no puede ser la causa. Ver el aviso de arriba.
- Cuántos de los paquetes del juego superan realmente 1280 bytes. El dato de que
  `FragOKs` lleve clavado en 154 sugiere que **casi ninguno**, lo cual reduce
  todavía más la urgencia del arreglo.

## Propuesta

Fijar el MTU del contenedor a 1280 para que coincida con la ruta real.

**El argumento no es que arregle nada**, sino que el desajuste es objetivamente
incorrecto para este despliegue: el juego está tomando decisiones de tamaño de
paquete con un número que no corresponde a la ruta. Corregirlo elimina la
fragmentación de raíz y, de paso, descarta una variable de las investigaciones
siguientes.

Es un cambio de una línea en `docker-compose.yml` y requiere reinicio. Después,
`FragOKs` debería dejar de crecer, lo cual es comprobable sin pedirle nada a
nadie.

## Nota de contexto

Este despliegue corre con **Docker rootless**, donde el reenvío de puertos UDP
lo hace RootlessKit en espacio de usuario. Es otra capa en la ruta que no existe
en un Docker normal. No hay evidencia de que pierda paquetes —los contadores
están limpios—, pero conviene recordarlo si aparece más desincronización: es una
diferencia real respecto a un despliegue convencional. Ver
[OPERACIONES.md](../OPERACIONES.md), sección de Docker rootless.
