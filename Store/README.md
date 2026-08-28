# Material para App Store Connect

## Capturas (`Screenshots/`)

Formato JPEG, sin transparencia, RGB. Tamaños oficiales:

| Carpeta | Uso en Connect | Tamaño |
|---|---|---|
| `iPhone-6.9/` | iPhone 6.9" (cubre el resto de iPhone) | 1320 × 2868 |
| `iPad-13/` | iPad 13" (cubre el resto de iPad) | 2064 × 2752 |
| `Mac/` | macOS (16:10) | 2880 × 1800 |

Orden sugerido al subirlas:

1. Import
2. Compare
3. Conflicts
4. Export
5. Settings

No hace falta vídeo de vista previa. Si más adelante grabas uno: 15–30 s, mismo tamaño que las capturas.

## Textos

Copia los campos de `LISTING.md` (iOS y macOS, en / es / zh-Hans / zh-Hant).

## Privacidad y soporte

Tras publicar GitHub Pages desde `main` (carpeta raíz, como HAOCHI):

- Soporte: https://520520u.github.io/PUBMERGE/
- Privacidad: https://520520u.github.io/PUBMERGE/privacy.html

Las capturas de Mac son JPEG 2880×1800 (formato 16:10 exigido). Si más adelante puedes capturar la ventana nativa de Mac, sustituye `Store/Screenshots/Mac/`.

## Regenerar capturas (Mac, Debug)

```bash
xcodebuild -project PubMerge.xcodeproj -scheme PubMerge -destination 'platform=macOS' -configuration Debug build
APP="$(ls -d "$HOME/Library/Developer/Xcode/DerivedData/PubMerge-"*/Build/Products/Debug/PubMerge.app | head -1)"
"$APP/Contents/MacOS/PubMerge" -demoExportScreenshots "$(pwd)/Store/Screenshots"
```
