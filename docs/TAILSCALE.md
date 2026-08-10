# Acceso por Tailscale

Alternativa a abrir puertos en el router. El servidor no se expone a Internet y
no sale en la lista publica: se entra por Tailscale, y quien no este autorizado
no encuentra la maquina. No es que le rechacen la conexion, es que para el no
existe.

En este documento, sustituye por lo tuyo:

| Marcador | Que es | Como se averigua |
| --- | --- | --- |
| `SERVIDOR` | nombre del nodo Tailscale que aloja el juego | `tailscale status` |
| `IP-TAILSCALE` | su IP dentro del tailnet (rango 100.64.0.0/10) | `tailscale ip -4` |

## Por que asi

Un servidor de Project Zomboid expuesto a Internet es un puerto UDP abierto las
24 horas contra un motor de juego. Por Tailscale la superficie expuesta es cero:
el trafico va cifrado extremo a extremo y solo entre nodos autorizados.

El modelo recomendado es **node sharing granular**, no meter a los jugadores en
la tailnet como miembros:

| | Invitarlos a la tailnet | Compartir solo esta maquina |
| --- | --- | --- |
| Que ven | todas las maquinas que permita la ACL | solo el servidor de juego |
| Cuentan para el limite de usuarios del plan | si | no |
| Si alguien deja el grupo | hay que revisar toda la politica | se quita su email de una lista |

## Las dos mitades del control de acceso

Hacen falta las dos. Cada una sin la otra no protege nada:

1. **El servidor escucha solo en la IP de Tailscale.** Lo fija `HOST_BIND_IP` en
   el `.env`. Sin esto el juego escucha tambien en la red local, y ahi ninguna
   ACL de Tailscale interviene: quien este en la misma WiFi entra por la puerta
   de al lado.
2. **La ACL de la tailnet.** Decide quien, de entre los que alcanzan la maquina,
   puede hablar con los puertos del juego. El fragmento a fusionar esta en
   [`tailscale/acl-fragment.hujson`](../tailscale/acl-fragment.hujson).

Comprobacion de la primera mitad, con el servidor levantado:

```bash
ss -ulpn | grep 1626
```

Debe aparecer `IP-TAILSCALE:16261`, **no** `0.0.0.0:16261`.

## Dar acceso a un jugador nuevo

Son **tres** pasos independientes, y los tres hacen falta. Saltarse cualquiera
produce un fallo distinto y ninguno da un mensaje de error util:

| Paso | Donde | Si falta |
| --- | --- | --- |
| 1. Compartir el nodo | Consola > Machines > `SERVIDOR` > `...` > Share | No ve la maquina en su `tailscale status` |
| 2. Anadir su email a la ACL | Politica, lista `src` del grant | La ve, pero no alcanza ningun puerto |
| 3. Firmar su nodo | `tailscale lock sign` (solo si hay Tailnet Lock) | Envia y no recibe: `tx` sube, `rx` se queda en 0 |

Antes de todo eso, el jugador necesita **una cuenta de Tailscale** (el plan
gratuito le sirve), el cliente instalado, y aceptar la invitacion del paso 1.

El paso 3 solo aplica si la tailnet tiene Tailnet Lock activado. Comprobarlo:

```bash
tailscale lock status
```

Si dice `Tailnet Lock is ENABLED`, lee la seccion siguiente: **no es opcional**.

## Tailnet Lock: el paso que nadie espera

Tailnet Lock impide que el servidor de coordinacion de Tailscale meta nodos
nuevos en tu red sin tu firma. Es una proteccion real, pero tiene una
consecuencia que no se anuncia por ningun lado: **cada dispositivo invitado
tiene que firmarse a mano**, y hasta entonces no puede hablar con nadie.

El sintoma es de los peores que hay, porque parece que funciona:

- El invitado ve el servidor en su `tailscale status`, incluso como `active`.
- Su contador `tx` sube: esta enviando paquetes.
- Su contador **`rx` se queda clavado en 0**: no recibe absolutamente nada.
- En el servidor no aparece ni un paquete, ni un intento, ni un rechazo.

Ese `tx` subiendo con `rx` a 0 es la firma inconfundible del problema.

### Como firmarlo

Los nodos bloqueados solo los ve **la maquina compartida**, porque el share es
por maquina: los demas nodos de tu tailnet no tienen ninguna relacion con los
dispositivos del invitado y por eso no los listan.

```bash
# EN EL SERVIDOR: ver quien esta bloqueado y con que clave
tailscale lock status
```

Al final sale la seccion de bloqueados, con una `nodekey:` por dispositivo.

```bash
# EN EL NODO FIRMANTE: firmar cada una
tailscale lock sign nodekey:<la-que-salio>
```

El nodo firmante es el que tiene una clave de confianza: en su `tailscale lock
status`, la linea `This node's tailnet-lock key` coincide con una de las
`Trusted signing keys` y aparece marcada como `(self)`. Firmar no requiere que
ese nodo conozca al invitado; la peticion va al servidor de coordinacion.

### Dos trampas al firmar

**La nodekey rota.** Un cliente rechazado reintenta y regenera su clave. Si
tardas entre mirar y firmar, obtendras `node not found` y habra que repetirlo
con la nueva. Haz los dos comandos seguidos.

**No le digas al invitado que reinicie Tailscale.** Un `down`/`up`, un cierre de
sesion o una reinstalacion generan clave nueva e invalidan la firma que acabas
de hacer. Mientras firmas, que no toque nada.

## Como se conecta el jugador

En el juego: **Join > Add server**, con puerto **16261**. El 16262 tiene que
estar permitido en la ACL pero no se teclea nunca: lo usa el motor por su
cuenta, y apuntar ahi produce una conexion que no llega a ningun sitio.

**La direccion NO es la que ves tu.** Un nodo compartido aparece en el tailnet
del invitado con una direccion propia, distinta de la que tiene en el tuyo. Cada
jugador tiene que mirar la suya:

```bash
tailscale status     # en la maquina del jugador
```

La linea del servidor lleva su IP y su nombre completo. Esa IP es la que va en
el juego. Es un detalle que cuesta horas de diagnostico si no se sabe, porque el
sintoma es "no conecta" sin ningun error.

Con `PZ_PUBLIC=false` el servidor no sale en la lista publica, asi que hay que
anadirlo a mano. Si hay `PZ_SERVER_PASSWORD`, se la tienes que pasar aparte.

### Por IP, no por nombre

Para el juego se usa la **IP**, no el nombre DNS. Motivo: el juego escucha solo
en IPv4, mientras que otros servicios de la maquina pueden escuchar tambien en
IPv6. Si el nombre resuelve a IPv6, el juego no responde y no hay ningun aviso.

Esto explica una asimetria que despista: un servicio publicado con `tailscale
serve` (Calibre, por ejemplo) exige **el nombre** y falla por IP, porque Serve
termina TLS con un certificado emitido para ese nombre. Son dos cosas distintas
con reglas opuestas, y conviene no extrapolar de una a la otra.

## Quitarle el acceso a alguien

Quitar su email de la lista `src` **y** revocar el share desde la consola. Con
lo primero deja de poder hablar con el juego; con lo segundo deja de ver la
maquina.

## Diagnostico

Antes de nada, la tabla de sintomas. Cada fallo de los tres pasos tiene una
firma propia, y distinguirlas ahorra horas:

| Sintoma en la maquina del jugador | Causa |
| --- | --- |
| El servidor no sale en `tailscale status` | Falta el share, o no acepto la invitacion |
| Sale, `tx` sube y **`rx` a 0** | Tailnet Lock: su nodo no esta firmado |
| Conecta a otros puertos pero no al juego | ACL: falta su email, o la regla es tcp en vez de udp |
| Todo bien pero el juego no entra | Direccion equivocada: esta usando tu IP y no la suya |

En el servidor, la comprobacion que separa "no llega nada" de "llega y se
rechaza":

```bash
docker compose logs pz | grep "initiating a connection"
```

Si no aparece **ni una linea**, el problema es de red o de acceso y no del
juego: los paquetes no estan llegando. Si aparece pero nunca le sigue
`Connected new client`, entonces si es el handshake del juego.

**"No me aparece la maquina"** — o no ha aceptado la invitacion de share, o se
revoco. Que ejecute `tailscale status` y compruebe si el servidor sale en su
lista.

**Ve la maquina pero el juego no conecta** — es la ACL o el bind. Por orden:

```bash
# En la maquina del jugador: hay ruta hasta el nodo?
tailscale ping SERVIDOR

# En el servidor: esta el juego escuchando donde debe?
ss -ulpn | grep 1626

# En el servidor: el servidor de juego esta vivo?
./scripts/rcon.sh players
```

Si `tailscale ping` responde pero el juego no entra, el sospechoso es el grant:
revisa que los puertos esten como **udp**, no tcp. Una regla tcp se ve perfecta
y no sirve de nada.

**Se conecta y le echa sin decir por que** — eso ya no es red. Mira la seccion
de diagnostico de [OPERACIONES.md](OPERACIONES.md), en particular lo de
`steamclient.so`.

## Limitacion conocida con Docker rootless

Si el servidor corre en Docker **rootless**, el reenvio de puertos UDP lo hace
RootlessKit en espacio de usuario y no conserva la IP de origen. En el log de
Project Zomboid todos los jugadores apareceran viniendo de la misma direccion,
con puertos distintos.

Consecuencia practica: **banear por IP no sirve**, hay que banear por Steam ID o
por usuario. No es grave, porque el acceso ya esta limitado antes: para llegar
al servidor hay que estar en la lista de la ACL.

Si hiciera falta la IP real, la salida es instalar `passt` y anadir al servicio
de usuario de Docker:

```
DOCKERD_ROOTLESS_ROOTLESSKIT_NET=pasta
DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER=implicit
```

Con Docker normal (rootful) esto no pasa: el reenvio lo hace el kernel y la IP
de origen se conserva.
