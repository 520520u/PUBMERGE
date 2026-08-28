import Foundation

public struct LibraryDatabase: Equatable, Sendable {
    public var locations: [LocationRecord] = []
    public var notes: [NoteRecord] = []
    public var userMarks: [UserMarkRecord] = []
    public var blockRanges: [BlockRangeRecord] = []
    public var bookmarks: [BookmarkRecord] = []
    public var tags: [TagRecord] = []
    public var tagMaps: [TagMapRecord] = []
    public var inputFields: [InputFieldRecord] = []
    public var independentMedia: [IndependentMediaRecord] = []
    public var playlistItems: [PlaylistItemRecord] = []
    public var playlistItemIndependentMediaMaps: [PlaylistItemIndependentMediaMapRecord] = []
    public var playlistItemLocationMaps: [PlaylistItemLocationMapRecord] = []
    public var playlistItemMarkers: [PlaylistItemMarkerRecord] = []
    public var playlistItemMarkerBibleVerseMaps: [PlaylistItemMarkerBibleVerseMapRecord] = []
    public var playlistItemMarkerParagraphMaps: [PlaylistItemMarkerParagraphMapRecord] = []
    public var lastModified: String = JWTimestamps.nowISO()

    public init() {}

    public var statistics: BackupStatistics {
        BackupStatistics(
            notes: notes.count,
            userMarks: userMarks.count,
            blockRanges: blockRanges.count,
            bookmarks: bookmarks.count,
            tags: tags.count,
            tagMaps: tagMaps.count,
            inputFields: inputFields.count,
            locations: locations.count,
            playlistItems: playlistItems.count,
            mediaFiles: independentMedia.count
        )
    }

    public var hasPlaylists: Bool {
        !playlistItems.isEmpty || tags.contains { $0.type == 2 }
    }

    public mutating func sanitizeForeignKeys() {
        let locationIDs = Set(locations.map(\.id))
        let markIDs = Set(userMarks.map(\.id))
        let noteIDs = Set(notes.map(\.id))
        let tagIDs = Set(tags.map(\.id))
        let playlistIDs = Set(playlistItems.map(\.id))
        let mediaIDs = Set(independentMedia.map(\.id))

        blockRanges.removeAll { !markIDs.contains($0.userMarkId) }

        for index in notes.indices {
            if let markID = notes[index].userMarkId, !markIDs.contains(markID) {
                notes[index].userMarkId = nil
            }
            if let locationID = notes[index].locationId, !locationIDs.contains(locationID) {
                notes[index].locationId = nil
            }
        }

        bookmarks.removeAll {
            !locationIDs.contains($0.locationId) || !locationIDs.contains($0.publicationLocationId)
        }
        inputFields.removeAll { !locationIDs.contains($0.locationId) }
        tagMaps.removeAll { map in
            if !tagIDs.contains(map.tagId) { return true }
            if let noteID = map.noteId, !noteIDs.contains(noteID) { return true }
            if let locationID = map.locationId, !locationIDs.contains(locationID) { return true }
            if let playlistID = map.playlistItemId, !playlistIDs.contains(playlistID) { return true }
            return false
        }

        playlistItemIndependentMediaMaps.removeAll {
            !playlistIDs.contains($0.playlistItemId) || !mediaIDs.contains($0.independentMediaId)
        }
        playlistItemLocationMaps.removeAll {
            !playlistIDs.contains($0.playlistItemId) || !locationIDs.contains($0.locationId)
        }
        playlistItemMarkers.removeAll { !playlistIDs.contains($0.playlistItemId) }
        let markerIDs = Set(playlistItemMarkers.map(\.id))
        playlistItemMarkerBibleVerseMaps.removeAll { !markerIDs.contains($0.playlistItemMarkerId) }
        playlistItemMarkerParagraphMaps.removeAll { !markerIDs.contains($0.playlistItemMarkerId) }
    }

    @discardableResult
    public mutating func updateNote(guid: String, title: String?, content: String?, modified: String) -> Bool {
        guard let index = notes.firstIndex(where: { $0.guid == guid }) else { return false }
        notes[index].title = title
        notes[index].content = content
        notes[index].lastModified = modified
        lastModified = modified
        return true
    }

    @discardableResult
    public mutating func deleteNote(guid: String) -> Bool {
        guard notes.contains(where: { $0.guid == guid }) else { return false }
        notes.removeAll { $0.guid == guid }
        sanitizeForeignKeys()
        lastModified = JWTimestamps.nowISO()
        return true
    }
}

public struct ImportedBackup: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var originalFileName: String
    public var fileSize: Int64
    public var importedAt: Date
    public var originalBackupURL: URL
    public var manifest: JWManifest
    public var schema: SchemaSupport
    public var hashWarning: String?
    public var database: LibraryDatabase
    public var mediaFiles: MediaCatalog
    public var sourceIndex: Int

    public init(
        id: UUID = UUID(),
        displayName: String,
        originalFileName: String,
        fileSize: Int64,
        importedAt: Date = Date(),
        originalBackupURL: URL,
        manifest: JWManifest,
        schema: SchemaSupport,
        hashWarning: String? = nil,
        database: LibraryDatabase,
        mediaFiles: MediaCatalog = MediaCatalog(),
        sourceIndex: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFileName = originalFileName
        self.fileSize = fileSize
        self.importedAt = importedAt
        self.originalBackupURL = originalBackupURL
        self.manifest = manifest
        self.schema = schema
        self.hashWarning = hashWarning
        self.database = database
        self.mediaFiles = mediaFiles
        self.sourceIndex = sourceIndex
    }

    public var deviceName: String {
        manifest.userDataBackup.deviceName
    }

    public var creationDate: String {
        manifest.creationDate
    }

    public var statistics: BackupStatistics {
        database.statistics
    }

    public var canMerge: Bool {
        schema.canExport
    }
}

public enum ItemKind: String, Equatable, Sendable, CaseIterable, Identifiable {
    case note
    case userMark
    case bookmark
    case tag
    case tagMap
    case inputField
    case location

    public var id: String { rawValue }
}

public enum ConflictStatus: String, Equatable, Sendable, CaseIterable {
    case unique
    case identical
    case conflict
    case resolved
}

public struct ComparableItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ItemKind
    public var status: ConflictStatus
    public var sourceName: String
    public var title: String
    public var detail: String
    public var publication: String
    public var book: Int?
    public var chapter: Int?
    public var modified: String?
    public var sourceIndex: Int
    public var noteGuid: String?
}
