import Foundation
import Testing
@testable import PubMergeCore

struct PubMergeCoreTests {
    private func workspace() throws -> WorkspaceStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PubMergeTests-\(UUID().uuidString)", isDirectory: true)
        return try WorkspaceStore(rootURL: url)
    }

    @Test func zipRoundTrip() throws {
        let files = ["manifest.json": Data("{\"ok\":true}".utf8), "userData.db": Data("sqlite".utf8)]
        let archived = try ZipArchive.zip(files)
        let unpacked = try ZipArchive.unzip(archived)
        #expect(unpacked["manifest.json"] == files["manifest.json"])
        #expect(unpacked["userData.db"] == files["userData.db"])
    }

    @Test func importValidatesAndNeverTouchesOriginal() throws {
        let store = try workspace()
        let (primary, _) = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        let originalBytes = try Data(contentsOf: primary)
        let imported = try JWLibraryArchive.importBackup(from: primary, workspace: store, sourceIndex: 0)
        #expect(imported.database.notes.count == 2)
        #expect(imported.database.tags.count == 2)
        #expect(imported.schema.canExport)
        #expect(try Data(contentsOf: primary) == originalBytes)
        #expect(FileManager.default.fileExists(atPath: imported.originalBackupURL.path))
    }

    @Test func mergeKeepsUniqueNotesAndTags() throws {
        let store = try workspace()
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        let left = try JWLibraryArchive.importBackup(from: pair.primary, workspace: store, sourceIndex: 0)
        let right = try JWLibraryArchive.importBackup(from: pair.secondary, workspace: store, sourceIndex: 1)
        let engine = MergeEngine()
        var plan = try engine.preview(backups: [left, right])
        #expect(plan.merged.notes.contains { $0.content == "Primary only" })
        #expect(plan.merged.notes.contains { $0.content == "Secondary only" })
        #expect(plan.merged.tags.map(\.name).sorted() == ["Family", "Ministry", "Study"])
        #expect(plan.conflicts.contains { $0.kind == .note })
        #expect(plan.conflicts.contains { $0.kind == .userMark })
        #expect(plan.conflicts.contains { $0.kind == .bookmark })
        #expect(plan.conflicts.contains { $0.kind == .inputField })

        plan = engine.apply(rule: .newest, to: plan)
        #expect(plan.unresolvedCount == 0)
        #expect(plan.merged.notes.contains { $0.content == "New wording" })
        #expect(!plan.merged.notes.contains { $0.content == "Old wording" })
        #expect(plan.merged.userMarks.contains { $0.version == 2 && $0.colorIndex == 2 })
        #expect(!plan.decisions.isEmpty)
    }

    @Test func keepBothNotesCreatesSecondGuid() throws {
        let store = try workspace()
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        let left = try JWLibraryArchive.importBackup(from: pair.primary, workspace: store, sourceIndex: 0)
        let right = try JWLibraryArchive.importBackup(from: pair.secondary, workspace: store, sourceIndex: 1)
        let engine = MergeEngine()
        var plan = try engine.preview(backups: [left, right])
        if let noteConflict = plan.conflicts.first(where: { $0.kind == .note }) {
            plan = engine.resolve(conflictID: noteConflict.id, as: .keepBoth, in: plan)
        }
        plan = engine.apply(rule: .primary, to: plan)
        let sermonNotes = plan.merged.notes.filter { $0.title == "Sermon" }
        #expect(sermonNotes.count == 2)
        #expect(Set(sermonNotes.map(\.guid)).count == 2)
    }

    @Test func exportValidatesAndReimports() throws {
        let store = try workspace()
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        let left = try JWLibraryArchive.importBackup(from: pair.primary, workspace: store, sourceIndex: 0)
        let right = try JWLibraryArchive.importBackup(from: pair.secondary, workspace: store, sourceIndex: 1)
        let engine = MergeEngine()
        let plan = engine.apply(rule: .newest, to: try engine.preview(backups: [left, right]))
        let exported = try JWLibraryExporter.export(
            ExportRequest(fileName: "Merged.jwlibrary", deviceName: "PubMerge", database: plan.merged, mediaFiles: plan.mediaFiles),
            workspace: store
        )
        #expect(exported.validation.isValid)
        #expect(exported.validation.schemaVersion == 16)
        #expect(exported.manifest.userDataBackup.hash == exported.hash)

        let reimported = try JWLibraryArchive.importBackup(from: exported.fileURL, workspace: store, sourceIndex: 2)
        #expect(reimported.database.notes.count == plan.merged.notes.count)
        #expect(reimported.database.tags.count == plan.merged.tags.count)
        #expect(reimported.database.userMarks.count == plan.merged.userMarks.count)
        #expect(reimported.hashWarning == nil)
    }

    @Test func rejectsUnknownSchema() throws {
        let store = try workspace()
        var library = SyntheticBackupFactory.makeLibrary(device: "Old")
        library.locations = [SyntheticBackupFactory.bibleLocation(id: 1, book: 40, chapter: 1, title: "Matthew 1")]
        let url = try SyntheticBackupFactory.package(library, fileName: "Unknown.jwlibrary", deviceName: "Old", workspace: store)
        var data = try Data(contentsOf: url)
        var files = try ZipArchive.unzip(data)
        var manifest = try JWManifest.decode(from: files["manifest.json"]!)
        manifest.userDataBackup.schemaVersion = 99
        files["manifest.json"] = try manifest.encoded()
        let dbURL = store.temporaryFile(named: "rewrite.db")
        try files["userData.db"]!.write(to: dbURL)
        let db = try SQLiteDatabase(path: dbURL.path, readOnly: false)
        try db.setUserVersion(99)
        db.close()
        files["userData.db"] = try Data(contentsOf: dbURL)
        files["manifest.json"] = try {
            var updated = manifest
            updated.userDataBackup.hash = SHA256Hash.hex(of: files["userData.db"]!)
            return try updated.encoded()
        }()
        data = try ZipArchive.zip(files)
        let broken = store.exportFile(named: "Broken.jwlibrary")
        try data.write(to: broken)
        #expect(throws: PubMergeError.self) {
            _ = try JWLibraryArchive.importBackup(from: broken, workspace: store, sourceIndex: 0)
        }
    }

    @Test func mergeRespectsNotesOnlyScope() throws {
        let store = try workspace()
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        let left = try JWLibraryArchive.importBackup(from: pair.primary, workspace: store, sourceIndex: 0)
        let right = try JWLibraryArchive.importBackup(from: pair.secondary, workspace: store, sourceIndex: 1)
        let engine = MergeEngine()
        let scope = MergeScope(notes: true, highlights: false, bookmarks: false, tags: false, inputFields: false, videos: false)
        var plan = try engine.preview(backups: [left, right], scope: scope)
        #expect(plan.scope == scope)
        #expect(plan.merged.notes.contains { $0.content == "Primary only" })
        #expect(plan.merged.notes.contains { $0.content == "Secondary only" })
        #expect(plan.conflicts.contains { $0.kind == .note })
        #expect(!plan.conflicts.contains { $0.kind == .userMark })
        #expect(!plan.conflicts.contains { $0.kind == .bookmark })
        #expect(!plan.conflicts.contains { $0.kind == .inputField })
        #expect(plan.merged.userMarks.contains { $0.version == 1 })
        #expect(!plan.merged.userMarks.contains { $0.version == 2 })
        #expect(plan.merged.tags.map(\.name).sorted() == ["Ministry", "Study"])
        #expect(!plan.merged.notes.contains { $0.userMarkId != nil && $0.content == "Secondary only" })
        plan = engine.apply(rule: .newest, to: plan)
        #expect(plan.merged.notes.contains { $0.content == "New wording" })
        let snapshot = engine.compare(backups: [left, right], plan: plan)
        #expect(snapshot.items.allSatisfy { $0.kind == .note })
    }

    @Test func mergeScopeCanKeepPrimaryOnly() throws {
        let store = try workspace()
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        let left = try JWLibraryArchive.importBackup(from: pair.primary, workspace: store, sourceIndex: 0)
        let right = try JWLibraryArchive.importBackup(from: pair.secondary, workspace: store, sourceIndex: 1)
        let plan = try MergeEngine().preview(
            backups: [left, right],
            scope: MergeScope(notes: false, highlights: false, bookmarks: false, tags: false, inputFields: false, videos: false)
        )
        #expect(plan.conflicts.isEmpty)
        #expect(plan.merged.notes.contains { $0.content == "Primary only" })
        #expect(!plan.merged.notes.contains { $0.content == "Secondary only" })
        #expect(plan.merged.notes.contains { $0.content == "Old wording" })
        #expect(plan.mediaFiles.isEmpty)
    }

    @Test func notesAttachedToSharedHighlightsExportCleanly() throws {
        let location = SyntheticBackupFactory.bibleLocation(id: 1, book: 40, chapter: 5, title: "Matthew 5")
        let markGUID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        var left = LibraryDatabase()
        left.locations = [location]
        left.userMarks = [
            UserMarkRecord(id: 1, colorIndex: 1, locationId: 1, styleIndex: 0, userMarkGuid: markGUID, version: 1)
        ]
        left.blockRanges = [
            BlockRangeRecord(id: 1, blockType: 2, identifier: 3, startToken: 0, endToken: 4, userMarkId: 1)
        ]
        left.notes = [
            SyntheticBackupFactory.note(id: 1, guid: "note-left", locationId: 1, title: "Left", content: "Left unique", modified: "2024-01-01T00:00:00Z")
        ]
        left.notes[0].userMarkId = 1

        var right = LibraryDatabase()
        right.locations = [location]
        right.userMarks = [
            UserMarkRecord(id: 1, colorIndex: 1, locationId: 1, styleIndex: 0, userMarkGuid: markGUID, version: 1)
        ]
        right.blockRanges = [
            BlockRangeRecord(id: 1, blockType: 2, identifier: 3, startToken: 0, endToken: 4, userMarkId: 1)
        ]
        right.notes = [
            SyntheticBackupFactory.note(id: 2, guid: "note-right", locationId: 1, title: "Right", content: "Right unique", modified: "2025-01-01T00:00:00Z")
        ]
        right.notes[0].userMarkId = 1

        let engine = MergeEngine()
        let plan = try engine.preview(backups: [
            imported(left, index: 0, name: "Left"),
            imported(right, index: 1, name: "Right")
        ])
        #expect(plan.merged.notes.count == 2)
        let markIDs = Set(plan.merged.userMarks.map(\.id))
        #expect(plan.merged.notes.allSatisfy { note in
            note.userMarkId == nil || markIDs.contains(note.userMarkId!)
        })
        #expect(plan.merged.notes.contains { $0.content == "Right unique" && $0.userMarkId != nil })

        let store = try workspace()
        let exported = try JWLibraryExporter.export(
            ExportRequest(fileName: "FKCheck.jwlibrary", database: plan.merged, mediaFiles: plan.mediaFiles),
            workspace: store
        )
        #expect(exported.validation.isValid)
    }

    @Test func primaryPlaylistsKeepTheirItemsAfterMerge() throws {
        var left = LibraryDatabase()
        left.locations = [SyntheticBackupFactory.bibleLocation(id: 1, book: 40, chapter: 1, title: "Matthew 1")]
        left.tags = [
            TagRecord(id: 1, type: 2, name: "Ministry videos"),
            TagRecord(id: 2, type: 1, name: "Study")
        ]
        left.independentMedia = [
            IndependentMediaRecord(id: 1, originalFilename: "clip.mp4", filePath: "clip.mp4", mimeType: "video/mp4", hash: "abc123")
        ]
        left.playlistItems = [
            PlaylistItemRecord(id: 1, label: "Clip one", accuracy: 1, endAction: 0, thumbnailFilePath: "clip.mp4")
        ]
        left.playlistItemIndependentMediaMaps = [
            PlaylistItemIndependentMediaMapRecord(playlistItemId: 1, independentMediaId: 1, durationTicks: 1_000)
        ]
        left.tagMaps = [
            TagMapRecord(id: 1, playlistItemId: 1, tagId: 1, position: 0)
        ]

        var right = LibraryDatabase()
        right.locations = left.locations
        right.notes = [
            SyntheticBackupFactory.note(id: 1, guid: "note-right", locationId: 1, title: "R", content: "Secondary only", modified: "2025-01-01T00:00:00Z")
        ]

        let plan = try MergeEngine().preview(backups: [
            imported(left, index: 0, name: "Left"),
            imported(right, index: 1, name: "Right")
        ])
        #expect(plan.merged.playlistItems.count == 1)
        #expect(plan.merged.tagMaps.contains { $0.playlistItemId != nil })
        #expect(plan.merged.playlistItemIndependentMediaMaps.count == 1)
        #expect(plan.merged.tags.contains { $0.type == 2 && $0.name == "Ministry videos" })

        let store = try workspace()
        var catalog = MediaCatalog()
        catalog.inlineFiles["clip.mp4"] = Data(repeating: 9, count: 64)
        let exported = try JWLibraryExporter.export(
            ExportRequest(fileName: "Playlists.jwlibrary", database: plan.merged, mediaFiles: catalog),
            workspace: store
        )
        #expect(exported.validation.isValid)
        let reimported = try JWLibraryArchive.importBackup(from: exported.fileURL, workspace: store, sourceIndex: 2)
        #expect(reimported.database.playlistItems.count == 1)
        #expect(reimported.database.tagMaps.contains { $0.playlistItemId != nil })
        #expect(reimported.database.playlistItemIndependentMediaMaps.count == 1)
        #expect(reimported.mediaFiles.names.contains("clip.mp4"))
    }

    @Test func emptyMergeRequiresTwoBackups() throws {
        let engine = MergeEngine()
        #expect(throws: PubMergeError.self) {
            _ = try engine.preview(backups: [])
        }
    }

    @Test func zipFileExtractReadsOnlyRequestedEntries() throws {
        let store = try workspace()
        let files = [
            "manifest.json": Data("{\"ok\":true}".utf8),
            "userData.db": Data("sqlite".utf8),
            "clip.mp4": Data(repeating: 7, count: 2048)
        ]
        let url = store.temporaryFile(named: "partial.zip")
        try ZipArchive.zip(files, to: url)
        let names = try ZipArchive.listEntries(at: url).map(\.name).sorted()
        #expect(names == ["clip.mp4", "manifest.json", "userData.db"])
        #expect(try ZipArchive.extractFile(named: "userData.db", from: url) == files["userData.db"])
        #expect(try ZipArchive.extractFileIfPresent(named: "missing.bin", from: url) == nil)
    }

    @Test func importDoesNotLoadMediaIntoMemory() throws {
        let store = try workspace()
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        var files = try ZipArchive.unzip(try Data(contentsOf: pair.primary))
        files["clip.mp4"] = Data(repeating: 3, count: 4096)
        let url = store.exportFile(named: "WithMedia.jwlibrary")
        try ZipArchive.zip(files, to: url)
        let imported = try JWLibraryArchive.importBackup(from: url, workspace: store, sourceIndex: 0)
        #expect(imported.mediaFiles.inlineFiles.isEmpty)
        #expect(imported.mediaFiles.names.contains("clip.mp4"))
        #expect(imported.database.notes.count == 2)
    }

    @Test func mergeLargeMarkSetsCompletes() throws {
        let location = SyntheticBackupFactory.bibleLocation(id: 1, book: 40, chapter: 1, title: "Matthew 1")
        var left = LibraryDatabase()
        var right = LibraryDatabase()
        left.locations = [location]
        right.locations = [location]
        for index in 1...4000 {
            left.userMarks.append(
                UserMarkRecord(id: index, colorIndex: 1, locationId: 1, styleIndex: 0, userMarkGuid: "left-\(index)", version: 1)
            )
            left.blockRanges.append(
                BlockRangeRecord(id: index, blockType: 2, identifier: index, startToken: 0, endToken: 4, userMarkId: index)
            )
            right.userMarks.append(
                UserMarkRecord(id: index, colorIndex: 1, locationId: 1, styleIndex: 0, userMarkGuid: "right-\(index)", version: 1)
            )
            right.blockRanges.append(
                BlockRangeRecord(id: index, blockType: 2, identifier: index, startToken: 0, endToken: 4, userMarkId: index)
            )
        }
        left.userMarks.append(
            UserMarkRecord(id: 5001, colorIndex: 1, locationId: 1, styleIndex: 0, userMarkGuid: "shared-mark", version: 1)
        )
        left.blockRanges.append(
            BlockRangeRecord(id: 5001, blockType: 2, identifier: 1, startToken: 0, endToken: 2, userMarkId: 5001)
        )
        right.userMarks.append(
            UserMarkRecord(id: 5001, colorIndex: 3, locationId: 1, styleIndex: 1, userMarkGuid: "shared-mark", version: 2)
        )
        right.blockRanges.append(
            BlockRangeRecord(id: 5001, blockType: 2, identifier: 1, startToken: 0, endToken: 8, userMarkId: 5001)
        )

        let engine = MergeEngine()
        var plan = try engine.preview(backups: [
            imported(left, index: 0, name: "Left"),
            imported(right, index: 1, name: "Right")
        ])
        #expect(plan.merged.userMarks.count == 8001)
        #expect(plan.conflicts.contains { $0.kind == .userMark && $0.key == "shared-mark" })
        plan = engine.apply(rule: .newest, to: plan)
        #expect(plan.unresolvedCount == 0)
        #expect(plan.merged.userMarks.contains { $0.userMarkGuid == "shared-mark" && $0.version == 2 })
        let snapshot = engine.compare(backups: [
            imported(left, index: 0, name: "Left"),
            imported(right, index: 1, name: "Right")
        ], plan: plan)
        #expect(!snapshot.items.contains { $0.kind == .userMark })
    }

    @Test func noteEditAndDeleteUpdateLibraryAndPlan() throws {
        var library = LibraryDatabase()
        library.notes = [
            SyntheticBackupFactory.note(id: 1, guid: "note-edit", locationId: 1, title: "Old", content: "Old body", modified: "2024-01-01T00:00:00Z")
        ]
        library.tags = [TagRecord(id: 1, type: 0, name: "Study")]
        library.tagMaps = [TagMapRecord(id: 1, noteId: 1, tagId: 1, position: 0)]
        let didUpdate = library.updateNote(guid: "note-edit", title: "New", content: "New body", modified: "2026-01-01T00:00:00Z")
        #expect(didUpdate)
        #expect(library.notes[0].title == "New")
        #expect(library.notes[0].content == "New body")
        let didDelete = library.deleteNote(guid: "note-edit")
        #expect(didDelete)
        #expect(library.notes.isEmpty)
        #expect(library.tagMaps.isEmpty)

        let store = try workspace()
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: store)
        let left = try JWLibraryArchive.importBackup(from: pair.primary, workspace: store, sourceIndex: 0)
        let right = try JWLibraryArchive.importBackup(from: pair.secondary, workspace: store, sourceIndex: 1)
        let engine = MergeEngine()
        var plan = try engine.preview(backups: [left, right])
        let snapshot = engine.compare(backups: [left, right], plan: plan)
        #expect(snapshot.items.contains { $0.kind == .note && $0.noteGuid != nil })
        plan.updateNote(guid: "22222222-2222-2222-2222-222222222222", title: "Edited", content: "Edited body", modified: "2026-08-28T00:00:00Z")
        #expect(plan.merged.notes.contains { $0.guid == "22222222-2222-2222-2222-222222222222" && $0.title == "Edited" })
        plan.deleteNote(guid: "22222222-2222-2222-2222-222222222222")
        #expect(!plan.merged.notes.contains { $0.guid == "22222222-2222-2222-2222-222222222222" })
    }

    private func imported(_ database: LibraryDatabase, index: Int, name: String) -> ImportedBackup {
        ImportedBackup(
            displayName: name,
            originalFileName: "\(name).jwlibrary",
            fileSize: 1,
            originalBackupURL: URL(fileURLWithPath: "/tmp/\(name).jwlibrary"),
            manifest: JWManifest(
                name: "\(name).jwlibrary",
                creationDate: "2026-01-01",
                userDataBackup: UserDataBackup(
                    lastModifiedDate: "2026-01-01T00:00:00Z",
                    hash: "abc",
                    schemaVersion: 16,
                    deviceName: name
                )
            ),
            schema: .supported(16),
            database: database,
            mediaFiles: MediaCatalog(),
            sourceIndex: index
        )
    }
}
