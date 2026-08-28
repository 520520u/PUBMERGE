import Foundation

enum SchemaAdapter {
    static func loadDatabase(from url: URL) throws -> (LibraryDatabase, Int) {
        let db = try SQLiteDatabase(path: url.path, readOnly: true)
        defer { db.close() }

        let version = try db.userVersion()
        switch SchemaPolicy.classify(version) {
        case .unsupported:
            throw PubMergeError.unsupportedSchema(version: version)
        case .supported, .upgradable:
            break
        }

        var library = LibraryDatabase()
        library.locations = try readLocations(db)
        library.userMarks = try readUserMarks(db)
        library.blockRanges = try readBlockRanges(db)
        library.notes = try readNotes(db)
        library.bookmarks = try readBookmarks(db)
        library.tags = try readTags(db)
        library.tagMaps = try readTagMaps(db)
        library.inputFields = try readInputFields(db)
        library.independentMedia = try readIndependentMedia(db)
        library.playlistItems = try readPlaylistItems(db)
        library.playlistItemIndependentMediaMaps = try readPlaylistMediaMaps(db)
        library.playlistItemLocationMaps = try readPlaylistLocationMaps(db)
        library.playlistItemMarkers = try readPlaylistMarkers(db)
        library.playlistItemMarkerBibleVerseMaps = try readMarkerVerses(db)
        library.playlistItemMarkerParagraphMaps = try readMarkerParagraphs(db)
        if try db.tableExists("LastModified") {
            library.lastModified = try db.scalarString("SELECT LastModified FROM LastModified LIMIT 1;") ?? JWTimestamps.nowISO()
        }
        return (library, version)
    }

    private static func readLocations(_ db: SQLiteDatabase) throws -> [LocationRecord] {
        guard try db.tableExists("Location") else { return [] }
        let columns = try db.columns(of: "Location")
        return try db.query("SELECT * FROM Location;").map { row in
            LocationRecord(
                id: row.int("LocationId"),
                bookNumber: row.intOpt("BookNumber"),
                chapterNumber: row.intOpt("ChapterNumber"),
                documentId: row.intOpt("DocumentId"),
                track: row.intOpt("Track"),
                issueTagNumber: row.int("IssueTagNumber"),
                keySymbol: row.textOpt("KeySymbol"),
                mepsLanguage: row.intOpt("MepsLanguage"),
                type: row.int("Type"),
                title: row.textOpt("Title"),
                specialty: columns.contains("Specialty") ? row.textOpt("Specialty") : nil,
                edition: columns.contains("Edition") ? row.textOpt("Edition") : nil
            )
        }
    }

    private static func readNotes(_ db: SQLiteDatabase) throws -> [NoteRecord] {
        guard try db.tableExists("Note") else { return [] }
        let columns = try db.columns(of: "Note")
        return try db.query("SELECT * FROM Note;").map { row in
            let modified = row.text("LastModified")
            let created = columns.contains("Created") ? (row.textOpt("Created") ?? modified) : modified
            return NoteRecord(
                id: row.int("NoteId"),
                guid: row.text("Guid"),
                userMarkId: row.intOpt("UserMarkId"),
                locationId: row.intOpt("LocationId"),
                title: row.textOpt("Title"),
                content: row.textOpt("Content"),
                lastModified: modified,
                created: created,
                blockType: row.int("BlockType"),
                blockIdentifier: row.intOpt("BlockIdentifier")
            )
        }
    }

    private static func readUserMarks(_ db: SQLiteDatabase) throws -> [UserMarkRecord] {
        guard try db.tableExists("UserMark") else { return [] }
        return try db.query("SELECT * FROM UserMark;").map { row in
            UserMarkRecord(
                id: row.int("UserMarkId"),
                colorIndex: row.int("ColorIndex"),
                locationId: row.int("LocationId"),
                styleIndex: row.int("StyleIndex"),
                userMarkGuid: row.text("UserMarkGuid"),
                version: row.int("Version")
            )
        }
    }

    private static func readBlockRanges(_ db: SQLiteDatabase) throws -> [BlockRangeRecord] {
        guard try db.tableExists("BlockRange") else { return [] }
        return try db.query("SELECT * FROM BlockRange;").map { row in
            BlockRangeRecord(
                id: row.int("BlockRangeId"),
                blockType: row.int("BlockType"),
                identifier: row.int("Identifier"),
                startToken: row.intOpt("StartToken"),
                endToken: row.intOpt("EndToken"),
                userMarkId: row.int("UserMarkId")
            )
        }
    }

    private static func readBookmarks(_ db: SQLiteDatabase) throws -> [BookmarkRecord] {
        guard try db.tableExists("Bookmark") else { return [] }
        return try db.query("SELECT * FROM Bookmark;").map { row in
            BookmarkRecord(
                id: row.int("BookmarkId"),
                locationId: row.int("LocationId"),
                publicationLocationId: row.int("PublicationLocationId"),
                slot: row.int("Slot"),
                title: row.text("Title"),
                snippet: row.textOpt("Snippet"),
                blockType: row.int("BlockType"),
                blockIdentifier: row.intOpt("BlockIdentifier")
            )
        }
    }

    private static func readTags(_ db: SQLiteDatabase) throws -> [TagRecord] {
        guard try db.tableExists("Tag") else { return [] }
        return try db.query("SELECT * FROM Tag;").map { row in
            TagRecord(id: row.int("TagId"), type: row.int("Type"), name: row.text("Name"))
        }
    }

    private static func readTagMaps(_ db: SQLiteDatabase) throws -> [TagMapRecord] {
        guard try db.tableExists("TagMap") else { return [] }
        return try db.query("SELECT * FROM TagMap;").map { row in
            TagMapRecord(
                id: row.int("TagMapId"),
                playlistItemId: row.intOpt("PlaylistItemId"),
                locationId: row.intOpt("LocationId"),
                noteId: row.intOpt("NoteId"),
                tagId: row.int("TagId"),
                position: row.int("Position")
            )
        }
    }

    private static func readInputFields(_ db: SQLiteDatabase) throws -> [InputFieldRecord] {
        guard try db.tableExists("InputField") else { return [] }
        return try db.query("SELECT * FROM InputField;").map { row in
            InputFieldRecord(
                locationId: row.int("LocationId"),
                textTag: row.text("TextTag"),
                value: row.text("Value")
            )
        }
    }

    private static func readIndependentMedia(_ db: SQLiteDatabase) throws -> [IndependentMediaRecord] {
        guard try db.tableExists("IndependentMedia") else { return [] }
        return try db.query("SELECT * FROM IndependentMedia;").map { row in
            IndependentMediaRecord(
                id: row.int("IndependentMediaId"),
                originalFilename: row.text("OriginalFilename"),
                filePath: row.text("FilePath"),
                mimeType: row.text("MimeType"),
                hash: row.text("Hash")
            )
        }
    }

    private static func readPlaylistItems(_ db: SQLiteDatabase) throws -> [PlaylistItemRecord] {
        guard try db.tableExists("PlaylistItem") else { return [] }
        let columns = try db.columns(of: "PlaylistItem")
        return try db.query("SELECT * FROM PlaylistItem;").compactMap { row in
            guard columns.contains("Accuracy") else { return nil }
            return PlaylistItemRecord(
                id: row.int("PlaylistItemId"),
                label: row.text("Label"),
                startTrimOffsetTicks: row.intOpt("StartTrimOffsetTicks"),
                endTrimOffsetTicks: row.intOpt("EndTrimOffsetTicks"),
                accuracy: row.int("Accuracy"),
                endAction: row.int("EndAction"),
                thumbnailFilePath: row.textOpt("ThumbnailFilePath")
            )
        }
    }

    private static func readPlaylistMediaMaps(_ db: SQLiteDatabase) throws -> [PlaylistItemIndependentMediaMapRecord] {
        guard try db.tableExists("PlaylistItemIndependentMediaMap") else { return [] }
        return try db.query("SELECT * FROM PlaylistItemIndependentMediaMap;").map { row in
            PlaylistItemIndependentMediaMapRecord(
                playlistItemId: row.int("PlaylistItemId"),
                independentMediaId: row.int("IndependentMediaId"),
                durationTicks: row.int("DurationTicks")
            )
        }
    }

    private static func readPlaylistLocationMaps(_ db: SQLiteDatabase) throws -> [PlaylistItemLocationMapRecord] {
        guard try db.tableExists("PlaylistItemLocationMap") else { return [] }
        return try db.query("SELECT * FROM PlaylistItemLocationMap;").map { row in
            PlaylistItemLocationMapRecord(
                playlistItemId: row.int("PlaylistItemId"),
                locationId: row.int("LocationId"),
                majorMultimediaType: row.int("MajorMultimediaType"),
                baseDurationTicks: row.intOpt("BaseDurationTicks")
            )
        }
    }

    private static func readPlaylistMarkers(_ db: SQLiteDatabase) throws -> [PlaylistItemMarkerRecord] {
        guard try db.tableExists("PlaylistItemMarker") else { return [] }
        return try db.query("SELECT * FROM PlaylistItemMarker;").map { row in
            PlaylistItemMarkerRecord(
                id: row.int("PlaylistItemMarkerId"),
                playlistItemId: row.int("PlaylistItemId"),
                label: row.text("Label"),
                startTimeTicks: row.int("StartTimeTicks"),
                durationTicks: row.int("DurationTicks"),
                endTransitionDurationTicks: row.int("EndTransitionDurationTicks")
            )
        }
    }

    private static func readMarkerVerses(_ db: SQLiteDatabase) throws -> [PlaylistItemMarkerBibleVerseMapRecord] {
        guard try db.tableExists("PlaylistItemMarkerBibleVerseMap") else { return [] }
        return try db.query("SELECT * FROM PlaylistItemMarkerBibleVerseMap;").map { row in
            PlaylistItemMarkerBibleVerseMapRecord(
                playlistItemMarkerId: row.int("PlaylistItemMarkerId"),
                verseId: row.int("VerseId")
            )
        }
    }

    private static func readMarkerParagraphs(_ db: SQLiteDatabase) throws -> [PlaylistItemMarkerParagraphMapRecord] {
        guard try db.tableExists("PlaylistItemMarkerParagraphMap") else { return [] }
        return try db.query("SELECT * FROM PlaylistItemMarkerParagraphMap;").map { row in
            PlaylistItemMarkerParagraphMapRecord(
                playlistItemMarkerId: row.int("PlaylistItemMarkerId"),
                mepsDocumentId: row.int("MepsDocumentId"),
                paragraphIndex: row.int("ParagraphIndex"),
                markerIndexWithinParagraph: row.int("MarkerIndexWithinParagraph")
            )
        }
    }
}

private extension Dictionary where Key == String, Value == SQLiteValue {
    func int(_ key: String) -> Int {
        self[key]?.intValue ?? 0
    }

    func intOpt(_ key: String) -> Int? {
        self[key]?.intValue
    }

    func text(_ key: String) -> String {
        self[key]?.textValue ?? ""
    }

    func textOpt(_ key: String) -> String? {
        self[key]?.textValue
    }
}
