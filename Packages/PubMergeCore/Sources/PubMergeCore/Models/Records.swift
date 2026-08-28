import Foundation

public struct LocationRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var bookNumber: Int?
    public var chapterNumber: Int?
    public var documentId: Int?
    public var track: Int?
    public var issueTagNumber: Int
    public var keySymbol: String?
    public var mepsLanguage: Int?
    public var type: Int
    public var title: String?
    public var specialty: String?
    public var edition: String?

    public init(
        id: Int,
        bookNumber: Int? = nil,
        chapterNumber: Int? = nil,
        documentId: Int? = nil,
        track: Int? = nil,
        issueTagNumber: Int = 0,
        keySymbol: String? = nil,
        mepsLanguage: Int? = nil,
        type: Int,
        title: String? = nil,
        specialty: String? = nil,
        edition: String? = nil
    ) {
        self.id = id
        self.bookNumber = bookNumber
        self.chapterNumber = chapterNumber
        self.documentId = documentId
        self.track = track
        self.issueTagNumber = issueTagNumber
        self.keySymbol = keySymbol
        self.mepsLanguage = mepsLanguage
        self.type = type
        self.title = title
        self.specialty = specialty
        self.edition = edition
    }

    public var naturalKey: String {
        [
            token(bookNumber),
            token(chapterNumber),
            token(documentId),
            token(track),
            String(issueTagNumber),
            keySymbol ?? "!",
            token(mepsLanguage),
            String(type),
            specialty ?? "!",
            edition ?? "!"
        ].joined(separator: "_")
    }

    public func preferringTitle(from other: LocationRecord) -> LocationRecord {
        var copy = self
        let current = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let incoming = other.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current.isEmpty && !incoming.isEmpty {
            copy.title = other.title
        }
        return copy
    }
}

public struct NoteRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var guid: String
    public var userMarkId: Int?
    public var locationId: Int?
    public var title: String?
    public var content: String?
    public var lastModified: String
    public var created: String
    public var blockType: Int
    public var blockIdentifier: Int?

    public init(
        id: Int,
        guid: String,
        userMarkId: Int? = nil,
        locationId: Int? = nil,
        title: String? = nil,
        content: String? = nil,
        lastModified: String,
        created: String,
        blockType: Int = 0,
        blockIdentifier: Int? = nil
    ) {
        self.id = id
        self.guid = guid
        self.userMarkId = userMarkId
        self.locationId = locationId
        self.title = title
        self.content = content
        self.lastModified = lastModified
        self.created = created
        self.blockType = blockType
        self.blockIdentifier = blockIdentifier
    }

    public var bodyKey: String {
        "\(title ?? "")\u{1e}\(content ?? "")\u{1e}\(blockType)\u{1e}\(blockIdentifier.map(String.init) ?? "!")"
    }
}

public struct UserMarkRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var colorIndex: Int
    public var locationId: Int
    public var styleIndex: Int
    public var userMarkGuid: String
    public var version: Int

    public init(
        id: Int,
        colorIndex: Int,
        locationId: Int,
        styleIndex: Int,
        userMarkGuid: String,
        version: Int
    ) {
        self.id = id
        self.colorIndex = colorIndex
        self.locationId = locationId
        self.styleIndex = styleIndex
        self.userMarkGuid = userMarkGuid
        self.version = version
    }

    public var appearanceKey: String {
        "\(colorIndex)_\(styleIndex)_\(version)_\(locationId)"
    }
}

public struct BlockRangeRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var blockType: Int
    public var identifier: Int
    public var startToken: Int?
    public var endToken: Int?
    public var userMarkId: Int

    public init(
        id: Int,
        blockType: Int,
        identifier: Int,
        startToken: Int? = nil,
        endToken: Int? = nil,
        userMarkId: Int
    ) {
        self.id = id
        self.blockType = blockType
        self.identifier = identifier
        self.startToken = startToken
        self.endToken = endToken
        self.userMarkId = userMarkId
    }

    public var rangeKey: String {
        "\(blockType)_\(identifier)_\(token(startToken))_\(token(endToken))"
    }
}

public struct BookmarkRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var locationId: Int
    public var publicationLocationId: Int
    public var slot: Int
    public var title: String
    public var snippet: String?
    public var blockType: Int
    public var blockIdentifier: Int?

    public init(
        id: Int,
        locationId: Int,
        publicationLocationId: Int,
        slot: Int,
        title: String,
        snippet: String? = nil,
        blockType: Int = 0,
        blockIdentifier: Int? = nil
    ) {
        self.id = id
        self.locationId = locationId
        self.publicationLocationId = publicationLocationId
        self.slot = slot
        self.title = title
        self.snippet = snippet
        self.blockType = blockType
        self.blockIdentifier = blockIdentifier
    }

    public var slotKey: String {
        "\(publicationLocationId)_\(slot)"
    }

    public var contentKey: String {
        "\(locationId)_\(title)_\(snippet ?? "")_\(blockType)_\(token(blockIdentifier))"
    }
}

public struct TagRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var type: Int
    public var name: String

    public init(id: Int, type: Int, name: String) {
        self.id = id
        self.type = type
        self.name = name
    }

    public var nameKey: String {
        "\(type)_\(name.lowercased())"
    }
}

public struct TagMapRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var playlistItemId: Int?
    public var locationId: Int?
    public var noteId: Int?
    public var tagId: Int
    public var position: Int

    public init(
        id: Int,
        playlistItemId: Int? = nil,
        locationId: Int? = nil,
        noteId: Int? = nil,
        tagId: Int,
        position: Int
    ) {
        self.id = id
        self.playlistItemId = playlistItemId
        self.locationId = locationId
        self.noteId = noteId
        self.tagId = tagId
        self.position = position
    }

    public var associationKey: String {
        "\(token(playlistItemId))_\(token(locationId))_\(token(noteId))_\(tagId)"
    }
}

public struct InputFieldRecord: Equatable, Sendable {
    public var locationId: Int
    public var textTag: String
    public var value: String

    public init(locationId: Int, textTag: String, value: String) {
        self.locationId = locationId
        self.textTag = textTag
        self.value = value
    }

    public var fieldKey: String {
        "\(locationId)_\(textTag)"
    }
}

public struct IndependentMediaRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var originalFilename: String
    public var filePath: String
    public var mimeType: String
    public var hash: String

    public init(id: Int, originalFilename: String, filePath: String, mimeType: String, hash: String) {
        self.id = id
        self.originalFilename = originalFilename
        self.filePath = filePath
        self.mimeType = mimeType
        self.hash = hash
    }
}

public struct PlaylistItemRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var label: String
    public var startTrimOffsetTicks: Int?
    public var endTrimOffsetTicks: Int?
    public var accuracy: Int
    public var endAction: Int
    public var thumbnailFilePath: String?

    public init(
        id: Int,
        label: String,
        startTrimOffsetTicks: Int? = nil,
        endTrimOffsetTicks: Int? = nil,
        accuracy: Int,
        endAction: Int,
        thumbnailFilePath: String? = nil
    ) {
        self.id = id
        self.label = label
        self.startTrimOffsetTicks = startTrimOffsetTicks
        self.endTrimOffsetTicks = endTrimOffsetTicks
        self.accuracy = accuracy
        self.endAction = endAction
        self.thumbnailFilePath = thumbnailFilePath
    }
}

public struct PlaylistItemIndependentMediaMapRecord: Equatable, Sendable {
    public var playlistItemId: Int
    public var independentMediaId: Int
    public var durationTicks: Int
}

public struct PlaylistItemLocationMapRecord: Equatable, Sendable {
    public var playlistItemId: Int
    public var locationId: Int
    public var majorMultimediaType: Int
    public var baseDurationTicks: Int?
}

public struct PlaylistItemMarkerRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var playlistItemId: Int
    public var label: String
    public var startTimeTicks: Int
    public var durationTicks: Int
    public var endTransitionDurationTicks: Int
}

public struct PlaylistItemMarkerBibleVerseMapRecord: Equatable, Sendable {
    public var playlistItemMarkerId: Int
    public var verseId: Int
}

public struct PlaylistItemMarkerParagraphMapRecord: Equatable, Sendable {
    public var playlistItemMarkerId: Int
    public var mepsDocumentId: Int
    public var paragraphIndex: Int
    public var markerIndexWithinParagraph: Int
}

public struct BackupStatistics: Equatable, Sendable {
    public var notes: Int
    public var userMarks: Int
    public var blockRanges: Int
    public var bookmarks: Int
    public var tags: Int
    public var tagMaps: Int
    public var inputFields: Int
    public var locations: Int
    public var playlistItems: Int
    public var mediaFiles: Int

    public init(
        notes: Int = 0,
        userMarks: Int = 0,
        blockRanges: Int = 0,
        bookmarks: Int = 0,
        tags: Int = 0,
        tagMaps: Int = 0,
        inputFields: Int = 0,
        locations: Int = 0,
        playlistItems: Int = 0,
        mediaFiles: Int = 0
    ) {
        self.notes = notes
        self.userMarks = userMarks
        self.blockRanges = blockRanges
        self.bookmarks = bookmarks
        self.tags = tags
        self.tagMaps = tagMaps
        self.inputFields = inputFields
        self.locations = locations
        self.playlistItems = playlistItems
        self.mediaFiles = mediaFiles
    }
}

private func token(_ value: Int?) -> String {
    value.map(String.init) ?? "!"
}
