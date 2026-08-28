import Foundation

public enum SyntheticBackupFactory {
    public static func bibleLocation(id: Int, book: Int, chapter: Int, title: String) -> LocationRecord {
        LocationRecord(
            id: id,
            bookNumber: book,
            chapterNumber: chapter,
            keySymbol: "nwtsty",
            mepsLanguage: 1,
            type: 0,
            title: title
        )
    }

    public static func note(
        id: Int,
        guid: String,
        locationId: Int,
        title: String,
        content: String,
        modified: String,
        created: String? = nil
    ) -> NoteRecord {
        NoteRecord(
            id: id,
            guid: guid,
            locationId: locationId,
            title: title,
            content: content,
            lastModified: modified,
            created: created ?? modified
        )
    }

    public static func makeLibrary(
        device: String,
        locations: [LocationRecord] = [],
        notes: [NoteRecord] = [],
        marks: [UserMarkRecord] = [],
        ranges: [BlockRangeRecord] = [],
        bookmarks: [BookmarkRecord] = [],
        tags: [TagRecord] = [],
        tagMaps: [TagMapRecord] = [],
        fields: [InputFieldRecord] = []
    ) -> LibraryDatabase {
        var database = LibraryDatabase()
        database.locations = locations
        database.notes = notes
        database.userMarks = marks
        database.blockRanges = ranges
        database.bookmarks = bookmarks
        database.tags = tags
        database.tagMaps = tagMaps
        database.inputFields = fields
        database.lastModified = JWTimestamps.nowISO()
        return database
    }

    public static func package(
        _ database: LibraryDatabase,
        fileName: String,
        deviceName: String,
        workspace: WorkspaceStore
    ) throws -> URL {
        let result = try JWLibraryExporter.export(
            ExportRequest(fileName: fileName, deviceName: deviceName, database: database),
            workspace: workspace
        )
        return result.fileURL
    }

    public static func pairForMergeTests(workspace: WorkspaceStore) throws -> (primary: URL, secondary: URL) {
        let matthew = bibleLocation(id: 1, book: 40, chapter: 5, title: "Matthew 5")
        let psalms = bibleLocation(id: 2, book: 19, chapter: 23, title: "Psalm 23")
        let sharedGUID = "11111111-1111-1111-1111-111111111111"
        let markGUID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

        let primary = makeLibrary(
            device: "iPhone",
            locations: [matthew, psalms],
            notes: [
                note(id: 1, guid: sharedGUID, locationId: 1, title: "Sermon", content: "Old wording", modified: "2024-01-01T10:00:00Z"),
                note(id: 2, guid: "22222222-2222-2222-2222-222222222222", locationId: 2, title: "Shepherd", content: "Primary only", modified: "2024-02-01T10:00:00Z")
            ],
            marks: [
                UserMarkRecord(id: 1, colorIndex: 1, locationId: 1, styleIndex: 0, userMarkGuid: markGUID, version: 1)
            ],
            ranges: [
                BlockRangeRecord(id: 1, blockType: 2, identifier: 3, startToken: 0, endToken: 4, userMarkId: 1)
            ],
            bookmarks: [
                BookmarkRecord(id: 1, locationId: 1, publicationLocationId: 1, slot: 0, title: "Matthew", snippet: "Primary")
            ],
            tags: [
                TagRecord(id: 1, type: 1, name: "Study"),
                TagRecord(id: 2, type: 1, name: "Ministry")
            ],
            tagMaps: [
                TagMapRecord(id: 1, noteId: 1, tagId: 1, position: 0)
            ],
            fields: [
                InputFieldRecord(locationId: 1, textTag: "q1", value: "Primary answer")
            ]
        )

        let secondary = makeLibrary(
            device: "iPad",
            locations: [matthew, psalms],
            notes: [
                note(id: 1, guid: sharedGUID, locationId: 1, title: "Sermon", content: "New wording", modified: "2025-06-01T10:00:00Z"),
                note(id: 3, guid: "33333333-3333-3333-3333-333333333333", locationId: 2, title: "Valley", content: "Secondary only", modified: "2025-03-01T10:00:00Z")
            ],
            marks: [
                UserMarkRecord(id: 1, colorIndex: 2, locationId: 1, styleIndex: 0, userMarkGuid: markGUID, version: 2)
            ],
            ranges: [
                BlockRangeRecord(id: 1, blockType: 2, identifier: 3, startToken: 0, endToken: 8, userMarkId: 1)
            ],
            bookmarks: [
                BookmarkRecord(id: 1, locationId: 2, publicationLocationId: 1, slot: 0, title: "Psalm", snippet: "Secondary")
            ],
            tags: [
                TagRecord(id: 1, type: 1, name: "Study"),
                TagRecord(id: 3, type: 1, name: "Family")
            ],
            tagMaps: [
                TagMapRecord(id: 1, noteId: 1, tagId: 1, position: 0)
            ],
            fields: [
                InputFieldRecord(locationId: 1, textTag: "q1", value: "Secondary answer")
            ]
        )

        let primaryURL = try package(primary, fileName: "PrimaryPhone.jwlibrary", deviceName: "iPhone", workspace: workspace)
        let secondaryURL = try package(secondary, fileName: "SecondaryPad.jwlibrary", deviceName: "iPad", workspace: workspace)
        return (primaryURL, secondaryURL)
    }
}
