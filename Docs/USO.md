# Guía de uso de PubMerge

## Antes de empezar

- PubMerge no modifica nunca tus archivos originales. Al importar, guarda una copia de solo lectura en su carpeta de respaldo.
- JW Library **no fusiona**: al restaurar, sustituye todo lo que haya en el dispositivo.
- Crea siempre una copia de seguridad del dispositivo **antes** de restaurar el archivo fusionado.

## Importar

1. Pulsa **Importar copias** o arrastra archivos `.jwlibrary` a la zona indicada.
2. En iPhone o iPad también puedes compartir un archivo desde la app Archivos hacia PubMerge.
3. La primera copia de la lista es la **principal**. Las demás son secundarias.
4. Revisa dispositivo, fecha, tamaño y recuento de notas, marcas, marcadores y etiquetas.

Si el esquema es antiguo (8–15), PubMerge puede leerlo y avisar de que exportará como esquema 16. Si el esquema es más nuevo que 16, la app **no exporta** para no generar un archivo corrupto.

## Comparar

Pulsa **Comparar y fusionar**. Verás un resumen de elementos únicos y los conflictos detectados. Puedes filtrar por tipo, estado o texto.

## Resolver conflictos

Un conflicto aparece cuando la misma nota, marca, marcador o respuesta existe en dos copias con contenido distinto.

Puedes:

- elegir la versión de la izquierda (principal) o de la derecha
- elegir la más reciente
- conservar ambas notas (la segunda recibe un identificador nuevo; no se concatenan)
- aplicar una regla a todos los conflictos pendientes

Las decisiones quedan en el registro de la sesión.

## Exportar y restaurar

1. Elige un nombre descriptivo, por ejemplo `Fusion-iPhone-iPad-2026-08-25.jwlibrary`.
2. Pulsa **Validar y exportar**. PubMerge recalcula el hash, comprueba las claves foráneas y verifica el esquema.
3. Restaura el archivo en cada dispositivo:

### iPhone e iPad

JW Library → Estudio personal → menú de tres puntos → Copia de seguridad y restauración → Restaurar.

### Mac

JW Library → Estudio personal → Copia de seguridad y restauración → Restaurar.

## Privacidad

En Ajustes puedes cifrar archivos temporales y eliminarlos de forma segura. PubMerge no necesita Internet después de instalarse.
