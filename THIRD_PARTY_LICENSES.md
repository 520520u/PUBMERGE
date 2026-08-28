# Third-party software

PubMerge does not vendor third-party Swift packages.

System libraries used on Apple platforms:

- **SQLite** (`libsqlite3`) — public domain
- **zlib** — used to read and write DEFLATE ZIP archives compatible with `.jwlibrary`
- **CryptoKit** — SHA-256 and optional AES-GCM for temporary files

The original plan considered ZIPFoundation (MIT). A small ZIP reader/writer on top of system zlib was enough for `.jwlibrary` files (root entries, DEFLATE, no encryption), so no extra package was added.

This project does not include source code copied from JWLMerge, JW Sync, go-library-merger, JWLManager, jwl-backup-merge, or jw-notes-sync.
