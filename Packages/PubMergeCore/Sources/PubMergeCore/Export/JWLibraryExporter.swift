import Foundation

public struct ExportRequest: Sendable {
    public var fileName: String
    public var deviceName: String
    public var database: LibraryDatabase
    public var mediaFiles: MediaCatalog
    public var includeMedia: Bool

    public init(fileName: String, deviceName: String = "PubMerge", database: LibraryDatabase, mediaFiles: MediaCatalog = MediaCatalog(), includeMedia: Bool = true) {
        self.fileName = fileName.hasSuffix(".jwlibrary") ? fileName : "\(fileName).jwlibrary"
        self.deviceName = deviceName
        self.database = database
        self.mediaFiles = mediaFiles
        self.includeMedia = includeMedia
    }
}

public struct ExportResult: Sendable {
    public var fileURL: URL
    public var manifest: JWManifest
    public var hash: String
    public var validation: ValidationReport
}

public enum JWLibraryExporter {
    public static func export(
        _ request: ExportRequest,
        workspace: WorkspaceStore,
        progress: WorkProgressHandler? = nil
    ) throws -> ExportResult {
        ProgressReporting.emit(progress, fraction: 0.04, stage: .writeDatabase)
        var library = request.database
        library.sanitizeForeignKeys()
        let dbURL = workspace.temporaryFile(named: "\(UUID().uuidString)-export.db")
        try writeDatabase(library, to: dbURL)
        let dbData = try Data(contentsOf: dbURL)
        let hash = SHA256Hash.hex(of: dbData)
        let creationDate = JWTimestamps.todayDateOnly()
        let modified = JWTimestamps.nowISO()
        let manifest = JWManifest(
            name: request.fileName,
            creationDate: creationDate,
            userDataBackup: UserDataBackup(
                lastModifiedDate: modified,
                hash: hash,
                databaseName: "userData.db",
                schemaVersion: SchemaV16.userVersion,
                deviceName: request.deviceName
            )
        )

        ProgressReporting.emit(progress, fraction: 0.12, stage: .packageArchive)
        let destination = workspace.exportFile(named: request.fileName)
        let writer = try ZipStreamingWriter(destination: destination)
        try writer.addFile(name: "manifest.json", data: try manifest.encoded())
        try writer.addFile(name: "userData.db", data: dbData)

        let mediaEntries = request.includeMedia ? mediaFilesToPack(from: request.database, catalog: request.mediaFiles) : []
        for (index, entry) in mediaEntries.enumerated() {
            let fraction = 0.15 + 0.75 * Double(index) / Double(max(mediaEntries.count, 1))
            ProgressReporting.emit(progress, fraction: fraction, stage: .packageMedia, detail: "\(index + 1)/\(mediaEntries.count)")
            try writer.addFile(name: entry.zipName, data: entry.data)
        }
        try writer.finish()

        ProgressReporting.emit(progress, fraction: 0.94, stage: .validate)
        let report = try BackupValidator.validate(file: destination)
        guard report.isValid else {
            throw PubMergeError.exportValidationFailed(report.issues)
        }
        try? FileManager.default.removeItem(at: dbURL)
        ProgressReporting.emit(progress, fraction: 1, stage: .validate)
        return ExportResult(fileURL: destination, manifest: manifest, hash: hash, validation: report)
    }

    private static func mediaFilesToPack(from database: LibraryDatabase, catalog: MediaCatalog) -> [(zipName: String, data: Data)] {
        var packed: [String: Data] = [:]
        var wanted = Set(database.independentMedia.map(\.filePath))
        wanted.formUnion(database.independentMedia.map(\.originalFilename))
        wanted.formUnion(database.playlistItems.compactMap(\.thumbnailFilePath))
        wanted.formUnion(catalog.inlineFiles.keys)
        for name in wanted where !name.isEmpty {
            guard packed[name] == nil, let data = try? catalog.data(for: name) else { continue }
            packed[name] = data
        }
        for media in database.independentMedia where packed[media.filePath] == nil {
            if let data = packed[media.originalFilename] ?? (try? catalog.data(for: media.originalFilename)) {
                packed[media.filePath] = data
            }
        }
        return packed.keys.sorted().compactMap { name in
            packed[name].map { (name, $0) }
        }
    }

    public static func writeDatabase(_ library: LibraryDatabase, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let db = try SQLiteDatabase(path: url.path, readOnly: false)
        defer { db.close() }
        try db.execute("PRAGMA foreign_keys=OFF;")
        try db.execute(SchemaV16.createTablesSQL)
        try db.execute(SchemaV16.indexesSQL)
        try db.insert("INSERT INTO LastModified(LastModified) VALUES (?);", binds: [.text(library.lastModified)])
        try db.insert("INSERT INTO PlaylistItemAccuracy(PlaylistItemAccuracyId, Description) VALUES (?, ?);", binds: [.int(1), .text("Accurate")])
        try db.insert("INSERT INTO PlaylistItemAccuracy(PlaylistItemAccuracyId, Description) VALUES (?, ?);", binds: [.int(2), .text("NeedsUserVerification")])
        try insertAll(library, into: db)
        try db.execute(SchemaV16.triggersSQL)
        try db.setUserVersion(SchemaV16.userVersion)
        try db.execute("PRAGMA journal_mode=DELETE;")
        try db.execute("PRAGMA foreign_keys=ON;")
        let violations = try db.foreignKeyViolations()
        if !violations.isEmpty {
            throw PubMergeError.foreignKeyViolation(violations.joined(separator: ", "))
        }
    }

    private static func insertAll(_ library: LibraryDatabase, into db: SQLiteDatabase) throws {
        for location in library.locations {
            try db.insert(
                "INSERT INTO Location(LocationId, BookNumber, ChapterNumber, DocumentId, Track, IssueTagNumber, KeySymbol, MepsLanguage, Type, Title, Specialty, Edition) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                binds: [
                    .int(location.id),
                    .optional(location.bookNumber),
                    .optional(location.chapterNumber),
                    .optional(location.documentId),
                    .optional(location.track),
                    .int(location.issueTagNumber),
                    .optional(location.keySymbol),
                    .optional(location.mepsLanguage),
                    .int(location.type),
                    .optional(location.title),
                    .optional(location.specialty),
                    .optional(location.edition)
                ]
            )
        }
        for media in library.independentMedia {
            try db.insert(
                "INSERT INTO IndependentMedia(IndependentMediaId, OriginalFilename, FilePath, MimeType, Hash) VALUES (?, ?, ?, ?, ?);",
                binds: [.int(media.id), .text(media.originalFilename), .text(media.filePath), .text(media.mimeType), .text(media.hash)]
            )
        }
        for mark in library.userMarks {
            try db.insert(
                "INSERT INTO UserMark(UserMarkId, ColorIndex, LocationId, StyleIndex, UserMarkGuid, Version) VALUES (?, ?, ?, ?, ?, ?);",
                binds: [.int(mark.id), .int(mark.colorIndex), .int(mark.locationId), .int(mark.styleIndex), .text(mark.userMarkGuid), .int(mark.version)]
            )
        }
        for range in library.blockRanges {
            try db.insert(
                "INSERT INTO BlockRange(BlockRangeId, BlockType, Identifier, StartToken, EndToken, UserMarkId) VALUES (?, ?, ?, ?, ?, ?);",
                binds: [.int(range.id), .int(range.blockType), .int(range.identifier), .optional(range.startToken), .optional(range.endToken), .int(range.userMarkId)]
            )
        }
        for note in library.notes {
            try db.insert(
                "INSERT INTO Note(NoteId, Guid, UserMarkId, LocationId, Title, Content, LastModified, Created, BlockType, BlockIdentifier) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                binds: [
                    .int(note.id),
                    .text(note.guid),
                    .optional(note.userMarkId),
                    .optional(note.locationId),
                    .optional(note.title),
                    .optional(note.content),
                    .text(note.lastModified),
                    .text(note.created),
                    .int(note.blockType),
                    .optional(note.blockIdentifier)
                ]
            )
        }
        for bookmark in library.bookmarks {
            try db.insert(
                "INSERT INTO Bookmark(BookmarkId, LocationId, PublicationLocationId, Slot, Title, Snippet, BlockType, BlockIdentifier) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
                binds: [
                    .int(bookmark.id),
                    .int(bookmark.locationId),
                    .int(bookmark.publicationLocationId),
                    .int(bookmark.slot),
                    .text(bookmark.title),
                    .optional(bookmark.snippet),
                    .int(bookmark.blockType),
                    .optional(bookmark.blockIdentifier)
                ]
            )
        }
        for field in library.inputFields {
            try db.insert(
                "INSERT INTO InputField(LocationId, TextTag, Value) VALUES (?, ?, ?);",
                binds: [.int(field.locationId), .text(field.textTag), .text(field.value)]
            )
        }
        for tag in library.tags {
            try db.insert(
                "INSERT INTO Tag(TagId, Type, Name) VALUES (?, ?, ?);",
                binds: [.int(tag.id), .int(tag.type), .text(tag.name)]
            )
        }
        for item in library.playlistItems {
            try db.insert(
                "INSERT INTO PlaylistItem(PlaylistItemId, Label, StartTrimOffsetTicks, EndTrimOffsetTicks, Accuracy, EndAction, ThumbnailFilePath) VALUES (?, ?, ?, ?, ?, ?, ?);",
                binds: [
                    .int(item.id),
                    .text(item.label),
                    .optional(item.startTrimOffsetTicks),
                    .optional(item.endTrimOffsetTicks),
                    .int(item.accuracy),
                    .int(item.endAction),
                    .optional(item.thumbnailFilePath)
                ]
            )
        }
        for map in library.tagMaps {
            try db.insert(
                "INSERT INTO TagMap(TagMapId, PlaylistItemId, LocationId, NoteId, TagId, Position) VALUES (?, ?, ?, ?, ?, ?);",
                binds: [
                    .int(map.id),
                    .optional(map.playlistItemId),
                    .optional(map.locationId),
                    .optional(map.noteId),
                    .int(map.tagId),
                    .int(map.position)
                ]
            )
        }
        for map in library.playlistItemIndependentMediaMaps {
            try db.insert(
                "INSERT INTO PlaylistItemIndependentMediaMap(PlaylistItemId, IndependentMediaId, DurationTicks) VALUES (?, ?, ?);",
                binds: [.int(map.playlistItemId), .int(map.independentMediaId), .int(map.durationTicks)]
            )
        }
        for map in library.playlistItemLocationMaps {
            try db.insert(
                "INSERT INTO PlaylistItemLocationMap(PlaylistItemId, LocationId, MajorMultimediaType, BaseDurationTicks) VALUES (?, ?, ?, ?);",
                binds: [.int(map.playlistItemId), .int(map.locationId), .int(map.majorMultimediaType), .optional(map.baseDurationTicks)]
            )
        }
        for marker in library.playlistItemMarkers {
            try db.insert(
                "INSERT INTO PlaylistItemMarker(PlaylistItemMarkerId, PlaylistItemId, Label, StartTimeTicks, DurationTicks, EndTransitionDurationTicks) VALUES (?, ?, ?, ?, ?, ?);",
                binds: [.int(marker.id), .int(marker.playlistItemId), .text(marker.label), .int(marker.startTimeTicks), .int(marker.durationTicks), .int(marker.endTransitionDurationTicks)]
            )
        }
        for map in library.playlistItemMarkerBibleVerseMaps {
            try db.insert(
                "INSERT INTO PlaylistItemMarkerBibleVerseMap(PlaylistItemMarkerId, VerseId) VALUES (?, ?);",
                binds: [.int(map.playlistItemMarkerId), .int(map.verseId)]
            )
        }
        for map in library.playlistItemMarkerParagraphMaps {
            try db.insert(
                "INSERT INTO PlaylistItemMarkerParagraphMap(PlaylistItemMarkerId, MepsDocumentId, ParagraphIndex, MarkerIndexWithinParagraph) VALUES (?, ?, ?, ?);",
                binds: [.int(map.playlistItemMarkerId), .int(map.mepsDocumentId), .int(map.paragraphIndex), .int(map.markerIndexWithinParagraph)]
            )
        }
    }
}
