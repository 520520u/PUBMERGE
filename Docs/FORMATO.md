# Formato `.jwlibrary`

Un archivo `.jwlibrary` es un ZIP comprimido con DEFLATE. En la raíz contiene:

- `manifest.json`
- `userData.db` (SQLite)
- archivos multimedia opcionales referenciados por listas de reproducción

## Manifiesto

Campos relevantes:

- `name` — debe terminar en `.jwlibrary`
- `creationDate` — `YYYY-MM-DD`
- `version` — `1`
- `type` — `0`
- `userDataBackup.hash` — SHA-256 en hexadecimal de los bytes crudos de `userData.db`
- `userDataBackup.schemaVersion` — versión del esquema SQLite
- `userDataBackup.databaseName` — normalmente `userData.db`
- `userDataBackup.deviceName` — nombre del dispositivo que creó la copia

Si el hash no coincide, JW Library puede rechazar la restauración sin un mensaje claro.

## Esquema

PubMerge escribe **esquema 16** (`PRAGMA user_version = 16`) y `journal_mode=DELETE`.

Tablas principales y claves de fusión:

- `Location` — clave natural (libro, capítulo, documento, idioma, tipo, specialty, edition)
- `Note` — `Guid` (incluye `Created` y `LastModified`)
- `UserMark` — `UserMarkGuid`
- `BlockRange` — sigue a su marca
- `Bookmark` — `PublicationLocationId` + `Slot`
- `Tag` — `Type` + `Name`
- `TagMap` — asociación remapeada, sin duplicados
- `InputField` — `LocationId` + `TextTag`
- Tablas de playlist y `IndependentMedia` — se conservan de la copia principal en el MVP

La salida incluye los índices y triggers de `LastModified` que espera JW Library.

## Adaptadores

- 16: lectura y escritura completas
- 8–15: lectura de notas, marcas, marcadores y etiquetas; aviso; exportación como 16
- >16 o desconocido: se bloquea la exportación

## Validación previa a exportar

- ZIP DEFLATE
- hash del manifiesto = hash del `userData.db`
- `user_version = 16`
- `journal_mode = delete`
- tablas requeridas presentes
- `PRAGMA foreign_key_check` vacío
