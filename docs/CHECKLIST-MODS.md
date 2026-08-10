# Checklist de comprobación de mods

Que un mod cargue no significa que funcione. El servidor solo detecta errores de
arranque; todo lo demás falla en silencio dentro del juego.

Esta lista es para repartir entre varios y comprobarlo de verdad. **Hazlo con al
menos dos jugadores conectados**: el multijugador es donde los mods se rompen, y
casi ninguno de estos autores tiene un servidor para probar.

Marca lo que falle y dilo, aunque parezca una tontería.

---

## Inventario y saqueo

- [x] **Proximity Inventory** — Mata unos zombis y quédate entre varios
      contenedores. Al abrir el inventario debes poder saquearlo todo de golpe
      sin ir uno por uno. Mira también los atajos de teclado en las opciones.
      *Verificado: muestra el contenido de contenedores cercanos, incluidas las
      bolsas anidadas dentro de ellos. Pendiente probarlo sobre un montón de
      cadáveres, que es su otro caso de uso.*
- [x] **CleanUI** — Los paneles se ven compactos. Prueba: buscar por nombre y por
      categoría (clic derecho en la lupa cambia el modo), *Transfer All* / *Take
      All*, reordenar contenedores arrastrando sus iconos, y el botón de ordenar.
      *Verificado. La reordenación funciona solo en el panel del jugador, no en
      los contenedores cercanos: es así por diseño, su documentación dice
      "in the player inventory panel".*
- [x] **Nested Containers** — Mete una bolsa dentro de la mochila. Debes poder ver
      lo que hay dentro **sin sacarla**. Comprueba además que esas bolsas
      anidadas aparecen en el saqueo por proximidad: es lo que depende de que el
      orden de carga sea correcto.
      *Verificado por completo: se ve dentro de una bolsa anidada en el propio
      inventario y también dentro de un contenedor del mundo. Esto confirma que
      `nm_nested_containers` carga antes que `ProximityInventory`, que es lo
      que exige su autor.*
- [ ] **Manage Containers** — Asigna una categoría a un armario de la base y
      descarga el botín. Debe repartirse solo.
- [x] **Better Sorting** — Las categorías de objetos están reorganizadas y los
      nombres son más claros que en el juego base.
- [x] **Split Items** — Divide una pila de objetos en dos.
- [x] **Modern Status** — Clic derecho en el botón del corazón abre el menú de
      Modern Status. Carga un preset. Deben estar los 33 indicadores.
      *Verificado: los 33 salen, y aparece* Mugre corporal *de la integración con
      Take A Bath And Shower.*

## Construir, fabricar y cocinar

- [x] **Neat Building** — El menú de construcción sale por categorías, con
      iconos y filtros. **Importante:** no debe añadir objetos construibles
      nuevos. Llevamos la variante *solo interfaz* a propósito; si aparecen
      piezas nuevas, algo va mal.
      *Lo de las piezas verificado en los ficheros, no a ojo: la variante completa
      trae 1752 scripts con entidades construibles; `Neat_Building_UIOnly` trae
      **cero**. No puede anadir piezas aunque quisiera. Queda por confirmar en
      juego solo que el menu se vea organizado por categorias.*
- [x] **Neat Crafting** — Menú de artesanía reorganizado. Prueba la lupa para
      buscar la receta de un ingrediente que te falte.
- [ ] **Project Cook** — Ponte en un fogón o con una olla. Debe salir el panel de
      cocina, sobre todo con recetas evolutivas: sopas, guisos, ensaladas.

## Supervivencia

- [x] **Realistic Temperature** — La temperatura dentro de un edificio debe
      diferir de la de fuera. Cierra puertas y ventanas y comprueba que cambia.
      **Se lee en un reloj digital equipado**, no en Modern Status: el mod
      reimplementa esa interfaz para meter ahi sus valores, y por eso depende de
      `LuaDigitalWatchUI`. El indicador *Temperatura* de Modern Status es la
      corporal, que es otra cosa.
      *Verificado: cambia al entrar y salir de un edificio.*
- [x] **Starving Zombies** — Deja un cadáver a la vista y espera. Los zombis
      deben acercarse a comérselo. Ve manchado de sangre y comprueba que te
      detectan desde más lejos.
- [ ] **Comfy Sleeping** — Duerme con la mochila puesta y luego sin ella. La
      calidad del descanso debe ser distinta.
- [x] **Take A Bath And Shower** — Úsate una bañera o una ducha. El indicador
      *Mugre corporal* debe bajar.
- [x] **Beds Have Blankets** — Explora una zona **nueva**. Algunas camas deben
      tener mantas. En zonas ya visitadas no aparecerán: solo se aplica al
      generar el terreno.
- [x] **Replace Bandage** — Con una venda sucia puesta, cámbiala por una limpia
      en una sola acción.
- [ ] **Cat's eye in the Dark** — Crea un personaje con el rasgo *Cat's Eye* y
      comprueba que ves algo de noche.

## Combate y movilidad

- [x] **Buttstroke** — Con un arma de fuego equipada, ataca cuerpo a cuerpo. Debe
      dar un culatazo.
- [x] **Run and Reload** — Recarga mientras corres.
- [ ] **Bicycle!** — Consigue una bicicleta y móntala. Debes ir más rápido.
- [ ] **Trailers!** — Engancha un remolque a un coche. Prueba a quitar y colocar
      sus piezas 3D.
- [ ] **Throw your bag across** — Clic derecho en una bolsa y lánzala por encima
      de una valla o a través de una ventana.

## Ropa y aspecto

- [x] **Improved Hair Menu** — El menú de peinados y barbas se navega bien, en la
      creación de personaje y en la pantalla de personaje.
      *Verificado: sale la rejilla con vistas previas 3D.*
- [x] **Spongie's Hair** — Hay peinados nuevos disponibles.
      *Verificado: el menú de cortar pelo ofrece 2 páginas con más de 150
      estilos; el juego base tiene unos 30.*
- [x] **Tariq's Beards** — Deben salir 47 barbas, con las largas: Thor, Kratos,
      Bandholz, vikingas y trenzadas. Si no aparece ninguna, es que no tienes el
      zip instalado en tu carpeta local.
      *Verificado en la creación de personaje.*
- [ ] **Spongie's Hairstyle Unlocker** — **La comprobación más importante de este
      bloque.** Córtate el pelo y comprueba que puedes elegir cualquier peinado
      de la misma longitud, no solo los cortos. Si solo te deja los de siempre,
      el orden de carga está mal.
      *Sin cerrar. El menú ofrece muchísimos estilos, incluidos largos, lo que
      apunta a que funciona, pero falta confirmar que alguno sea de la MISMA
      longitud que el que se lleva puesto. Ojo: las barbas no cuentan — el mod
      habla de* hairstyles*, y afeitar solo va hacia menos pelo por diseño.*
- [x] **Equip Clothing While Moving** — Ponte una prenda mientras caminas o
      apuntas.

## Common Sense

Es el que más funciones trae, así que va aparte.

- [x] Forzar con palanca: puertas de edificio, de garaje, reforzadas, ventanas y
      puertas de vehículo.
- [x] Interfaz de arma: con un arma equipada debe verse munición, estado y
      condición.
- [x] Equipar desde el suelo por menú contextual — armas, ropa y mochilas.
      **Esta sustituye a Right Click To Wear, que quitamos.** Si no funciona,
      nos hemos quedado sin las dos.
      *Verificado, funciona.*
- [x] Linterna de mano enganchada al cinturón.
- [x] Abrir latas con cuchillo, destornillador, tenedor o cuchara.
- [ ] Desinfectar una venda sucia con alcohol.
- [x] Fabricar sábanas a partir de ropa.
- [x] Sus opciones aparecen en los ajustes de sandbox.
      *Verificado en el fichero: el bloque `CommonSense` tiene sus 17 opciones
      (palanca por tipo de puerta, dificultad, estadisticas de arma, filtro de
      color, heridas al abrir latas, bala a mano). En servidor dedicado no hay
      interfaz en juego: se editan en `config/SandboxVars.lua`.*

## Libros y mapa

- [x] **Reading+** — Lee mientras caminas. Siéntate en un buen sofá y comprueba
      que lees más rápido. Encola varios libros de una vez.
- [x] **Has Been Read** — Los libros sin leer o a medias salen marcados de forma
      distinta.
- [ ] **Map Symbol Size Slider** — Hay un control de tamaño en el menú de
      símbolos del mapa.
- [ ] **Map Symbols Plus** — Están los símbolos dibujados a mano, con las
      chinchetas de *seguro*, *peligro* y *desconocido*.

## Los que no se comprueban solos

Estos no hacen nada por sí mismos: si funcionan los de arriba, funcionan ellos.

| Mod | Se comprueba a través de |
| --- | --- |
| NeatUI Framework | CleanUI, Neat Crafting, Neat Building, Project Cook, Modern Status |
| that DAMN Library | Trailers! |
| Target Square: On Load Commands | Beds Have Blankets |
| Lua Digital Watch Framework | Realistic Temperature |
| Fluffy Hair | Ponte un sombrero: el peinado no debe deformarse |

---

## Fallos que ya conocemos

No hace falta reportarlos, están detectados. Si comprobáis alguno y **sí**
funciona, eso sí es noticia.

| Mod | Qué falla | Origen |
| --- | --- | --- |
| **Bicycle!** | El almacenamiento de la bici (cesta o alforjas) probablemente no funcione | Le falta un módulo interno: `BicycleContainerManager` |
| **Beds Have Blankets** | Fabricar mantas no funcionará | Usa `recipecode`, un módulo que Build 42 eliminó |
| **Beds Have Blankets** | Las mantas salen **dobladas sobre la cama**, no puestas. Comprobado: 5 de 5 camas, cuando su ajuste dice que debería ser 1 de cada 20 | Declara su dependencia como `require=TargetSquareOnLoad`, **con barra invertida**. Si se compara literal, nunca casa con el ID real y el mod actúa como si la dependencia no existiera |
| **Tariq's Beards** | Los nombres de las 47 barbas salen sin traducir: `IGUI_Beard_Santatest` en vez de "Santa" | El mod solo trae traducciones en inglés, y el juego está en español. Solo afecta al nombre; el modelo se ve bien |

Ninguno de los tres tumba el servidor. Son funciones que no están, no errores.

El de las traducciones lo podemos arreglar nosotros añadiendo un `Translate/ES/`
al port, si acabamos publicándolo.

---

## Si algo falla

Apunta **qué mod, qué hacías y qué esperabas que pasara**. Con eso se puede
reproducir; con "el inventario va raro" no.

Si el juego se cierra o te echa del servidor, dilo enseguida y no vuelvas a
entrar hasta que se mire: puede haber quedado algo a medio guardar.
