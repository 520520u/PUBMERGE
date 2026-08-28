# PubMerge

Aplicación nativa para iPhone, iPad y Mac que importa, compara, fusiona y exporta copias `.jwlibrary` **en local**. No usa servidores, cuentas ni analítica.

PubMerge es un proyecto independiente. No está afiliado, respaldado ni conectado con Watch Tower Bible and Tract Society of Pennsylvania. “JW Library” es una marca de Watch Tower.

## Requisitos

- Xcode 16 o posterior (probado con Xcode 26)
- macOS 14+ para ejecutar la app de Mac y las pruebas
- iOS / iPadOS 17+ para ejecutar en dispositivo o simulador

## Abrir y compilar

```bash
cd "ruta/a/PUBMERGE"
xcodegen generate   # regenera PubMerge.xcodeproj si editas project.yml
open PubMerge.xcodeproj
```

En Xcode:

1. Elige el destino **PubMerge** y un simulador iOS, un iPad o **My Mac**.
2. Firma el destino con tu equipo de desarrollo si vas a instalarlo en un dispositivo.
3. Pulsa Run.

## Pruebas

Desde el paquete del motor (recomendado):

```bash
cd Packages/PubMergeCore
swift test
```

Las pruebas usan copias **sintéticas**, sin datos personales. Comprueban importación, deduplicación, conflictos, etiquetas, notas, exportación y un round-trip (exportar → volver a importar).

## Uso breve

1. En cada dispositivo, crea una copia en JW Library (Estudio personal → Copia de seguridad y restauración).
2. Abre PubMerge e importa **al menos dos** archivos `.jwlibrary` (selector, arrastrar y soltar, o Abrir con).
3. Pulsa **Comparar y fusionar**.
4. Resuelve los conflictos uno a uno o aplica una regla a todos.
5. Exporta un archivo nuevo. PubMerge lo valida antes de ofrecerlo.
6. Restaura ese archivo en JW Library. **La restauración sustituye los datos del dispositivo.** Haz primero una copia del aparato.

Web y política de privacidad: [https://520520u.github.io/PUBMERGE/](https://520520u.github.io/PUBMERGE/).  
Ficha y capturas para App Store Connect: [Store/README.md](Store/README.md).
Sitio en la raíz del repo (`index.html`, `privacy.html`), igual que HAOCHI.

Guía más detallada: [Docs/USO.md](Docs/USO.md).  
Formato interno: [Docs/FORMATO.md](Docs/FORMATO.md).

## Arquitectura

- `App/` — interfaz SwiftUI multiplataforma
- `Packages/PubMergeCore/` — importación ZIP, SQLite, fusión, exportación y validación
- Sin dependencias externas: ZIP con zlib del sistema, SHA-256 con CryptoKit, SQLite del sistema

## Licencia

Código de PubMerge: ver [LICENSE](LICENSE).  
Este proyecto no incluye código de herramientas de terceros incompatibles con sus licencias.
