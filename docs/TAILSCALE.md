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

1. **Que se cree una cuenta de Tailscale** (el plan gratuito le sirve) e instale
   el cliente.
2. **Compartir la maquina**: consola de Tailscale > Machines > `SERVIDOR` > menu
   `...` > Share. Sale un enlace de invitacion que se le pasa.
3. **Anadir su email** a la lista `src` del grant de jugadores en la politica.
4. Que acepte la invitacion y conecte el cliente.

Los pasos 2 y 3 son ambos necesarios y hacen cosas distintas: el share hace que
la maquina exista para el, la ACL decide a que puerto puede hablar. Con solo el
share no llega a ningun sitio; con solo la ACL no ve la maquina.

## Como se conecta el jugador

En el juego: **Join > Add server**, y ahi como direccion la `IP-TAILSCALE` del
servidor, con puerto **16261**. El 16262 tiene que estar permitido en la ACL
pero no se teclea nunca: lo usa el motor por su cuenta.

Con `PZ_PUBLIC=false` el servidor no sale en la lista publica, asi que hay que
anadirlo a mano. Si hay `PZ_SERVER_PASSWORD`, se la tienes que pasar aparte.

## Quitarle el acceso a alguien

Quitar su email de la lista `src` **y** revocar el share desde la consola. Con
lo primero deja de poder hablar con el juego; con lo segundo deja de ver la
maquina.

## Diagnostico

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
