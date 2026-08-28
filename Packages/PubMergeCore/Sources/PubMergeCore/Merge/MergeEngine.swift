import Foundation

public struct MergeEngine: Sendable {
    public init() {}

    public func preview(backups: [ImportedBackup], scope: MergeScope = .all, progress: WorkProgressHandler? = nil) throws -> MergePlan {
        guard backups.count >= 2 else { throw PubMergeError.emptyMerge }
        for backup in backups {
            if case .unsupported(let version) = backup.schema {
                throw PubMergeError.unsupportedSchema(version: version)
            }
        }

        var builder = MergeBuilder()
        ProgressReporting.emit(progress, fraction: 0.08, stage: .mergePrimary, detail: backups[0].displayName)
        builder.ingestPrimary(backups[0])
        var conflicts: [MergeConflict] = []
        var warnings: [MergeWarning] = []

        let secondaries = Array(backups.dropFirst())
        for (offset, backup) in secondaries.enumerated() {
            let fraction = 0.2 + 0.7 * Double(offset) / Double(max(secondaries.count, 1))
            ProgressReporting.emit(progress, fraction: fraction, stage: .mergeSecondary, detail: backup.displayName)
            let result = builder.mergeSecondary(backup, scope: scope)
            conflicts.append(contentsOf: result.conflicts)
            warnings.append(contentsOf: result.warnings)
        }

        builder.sanitizeDatabase()
        ProgressReporting.emit(progress, fraction: 0.95, stage: .compare)
        return MergePlan(
            base: builder.database,
            merged: builder.database,
            mediaFiles: scope.videos ? builder.mediaFiles : MediaCatalog(),
            conflicts: conflicts,
            decisions: [],
            warnings: warnings,
            primaryName: backups[0].displayName,
            sourceCount: backups.count,
            scope: scope
        )
    }

    public func apply(rule: MergeRule, to plan: MergePlan) -> MergePlan {
        var updated = plan
        for index in updated.conflicts.indices where updated.conflicts[index].resolution == nil {
            updated.conflicts[index].resolution = resolution(for: updated.conflicts[index], rule: rule)
        }
        return commit(updated)
    }

    public func resolve(conflictID: UUID, as resolution: ConflictResolution, in plan: MergePlan) -> MergePlan {
        var updated = plan
        if let index = updated.conflicts.firstIndex(where: { $0.id == conflictID }) {
            updated.conflicts[index].resolution = resolution
        }
        return commit(updated)
    }

    public func compare(backups: [ImportedBackup], plan: MergePlan, progress: WorkProgressHandler? = nil) -> ComparisonSnapshot {
        ProgressReporting.emit(progress, fraction: 0.2, stage: .compare)
        var conflictIndex: [String: MergeConflict] = [:]
        conflictIndex.reserveCapacity(plan.conflicts.count)
        for conflict in plan.conflicts {
            conflictIndex["\(conflict.kind.rawValue)|\(conflict.key)"] = conflict
        }

        var items: [ComparableItem] = []
        let estimated = backups.reduce(0) { $0 + $1.database.notes.count + $1.database.bookmarks.count + $1.database.tags.count }
        items.reserveCapacity(estimated + plan.conflicts.count)

        for backup in backups {
            var locationsByID: [Int: LocationRecord] = [:]
            locationsByID.reserveCapacity(backup.database.locations.count)
            for location in backup.database.locations {
                locationsByID[location.id] = location
            }

            if plan.scope.notes {
                for note in backup.database.notes {
                    let location = note.locationId.flatMap { locationsByID[$0] }
                    items.append(
                        ComparableItem(
                            id: "\(backup.sourceIndex)-note-\(note.guid)",
                            kind: .note,
                            status: status(for: .note, key: note.guid, conflicts: conflictIndex),
                            sourceName: backup.displayName,
                            title: note.title ?? String(note.content?.prefix(40) ?? "Note"),
                            detail: note.content ?? "",
                            publication: location?.keySymbol ?? "",
                            book: location?.bookNumber,
                            chapter: location?.chapterNumber,
                            modified: note.lastModified,
                            sourceIndex: backup.sourceIndex,
                            noteGuid: note.guid
                        )
                    )
                }
            }
            if plan.scope.bookmarks {
                for bookmark in backup.database.bookmarks {
                    items.append(
                        ComparableItem(
                            id: "\(backup.sourceIndex)-bookmark-\(bookmark.id)",
                            kind: .bookmark,
                            status: status(for: .bookmark, key: bookmark.slotKey, conflicts: conflictIndex),
                            sourceName: backup.displayName,
                            title: bookmark.title,
                            detail: bookmark.snippet ?? "",
                            publication: "",
                            book: nil,
                            chapter: nil,
                            modified: nil,
                            sourceIndex: backup.sourceIndex,
                            noteGuid: nil
                        )
                    )
                }
            }
            if plan.scope.tags {
                for tag in backup.database.tags {
                    items.append(
                        ComparableItem(
                            id: "\(backup.sourceIndex)-tag-\(tag.id)",
                            kind: .tag,
                            status: .identical,
                            sourceName: backup.displayName,
                            title: tag.name,
                            detail: "Type \(tag.type)",
                            publication: "",
                            book: nil,
                            chapter: nil,
                            modified: nil,
                            sourceIndex: backup.sourceIndex,
                            noteGuid: nil
                        )
                    )
                }
            }
        }

        var added = BackupStatistics()
        added.notes = plan.merged.notes.count
        added.userMarks = plan.merged.userMarks.count
        added.bookmarks = plan.merged.bookmarks.count
        added.tags = plan.merged.tags.count
        added.tagMaps = plan.merged.tagMaps.count
        added.inputFields = plan.merged.inputFields.count
        added.locations = plan.merged.locations.count
        added.mediaFiles = plan.merged.independentMedia.count

        ProgressReporting.emit(progress, fraction: 1, stage: .compare)
        return ComparisonSnapshot(
            items: items,
            totals: added,
            addedCounts: added,
            conflictCount: plan.conflicts.count
        )
    }

    private func status(for kind: ItemKind, key: String, conflicts: [String: MergeConflict]) -> ConflictStatus {
        guard let conflict = conflicts["\(kind.rawValue)|\(key)"] else { return .unique }
        return conflict.isResolved ? .resolved : .conflict
    }

    private func resolution(for conflict: MergeConflict, rule: MergeRule) -> ConflictResolution {
        switch rule {
        case .primary:
            return .left
        case .secondary:
            return .right
        case .keepBothNotes:
            return conflict.kind == .note ? .keepBoth : .newest
        case .newest:
            return .newest
        }
    }

    private func commit(_ plan: MergePlan) -> MergePlan {
        var builder = MergeBuilder(seed: plan.base, media: plan.mediaFiles)
        var decisions = plan.decisions
        for conflict in plan.conflicts {
            guard let resolution = conflict.resolution else { continue }
            let choice = resolvedPayloads(conflict, resolution: resolution)
            for (offset, payload) in choice.payloads.enumerated() {
                builder.addResolved(payload, resolution: resolution, isAdditionalCopy: offset > 0)
            }
            if !decisions.contains(where: { $0.key == conflict.key && $0.kind == conflict.kind && $0.choice == resolution }) {
                decisions.append(
                    MergeDecision(
                        id: UUID(),
                        timestamp: Date(),
                        kind: conflict.kind,
                        key: conflict.key,
                        choice: resolution,
                        summary: choice.summary
                    )
                )
            }
        }
        builder.sanitizeDatabase()
        var updated = plan
        updated.merged = builder.database
        updated.mediaFiles = builder.mediaFiles
        updated.decisions = decisions
        return updated
    }

    private func resolvedPayloads(_ conflict: MergeConflict, resolution: ConflictResolution) -> (payloads: [ConflictPayload], summary: String) {
        let chosen: [ConflictSide]
        switch resolution {
        case .left:
            chosen = [conflict.left]
        case .right:
            chosen = [conflict.right]
        case .keepBoth:
            chosen = [conflict.left, conflict.right]
        case .newest:
            chosen = [newerSide(conflict)]
        }
        let summary = "\(conflict.kind.rawValue) \(conflict.key): \(resolution.rawValue)"
        return (chosen.map(\.payload), summary)
    }

    private func newerSide(_ conflict: MergeConflict) -> ConflictSide {
        switch (conflict.left.payload, conflict.right.payload) {
        case (.note(let left), .note(let right)):
            return JWTimestamps.compare(left.lastModified, right.lastModified) == .orderedAscending ? conflict.right : conflict.left
        case (.userMark(let left, _), .userMark(let right, _)):
            return right.version > left.version ? conflict.right : conflict.left
        default:
            return conflict.left
        }
    }
}

struct MergeBuilder {
    private(set) var database = LibraryDatabase()
    private(set) var mediaFiles = MediaCatalog()
    private var locationByKey: [String: Int] = [:]
    private var tagByKey: [String: Int] = [:]
    private var noteByGUID: [String: Int] = [:]
    private var markByGUID: [String: Int] = [:]
    private var bookmarkBySlot: [String: String] = [:]
    private var fieldByKey: [String: String] = [:]
    private var tagMapKeys: Set<String> = []
    private var tagMapPositions: Set<String> = []
    private var maxPositionByTag: [Int: Int] = [:]
    private var rangesByMark: [Int: [String]] = [:]
    private var rangeRecordsByMark: [Int: [BlockRangeRecord]] = [:]
    private var locationsByID: [Int: Int] = [:]
    private var notesByID: [Int: Int] = [:]
    private var marksByID: [Int: Int] = [:]
    private var bookmarksBySlotIndex: [String: Int] = [:]
    private var fieldsByKeyIndex: [String: Int] = [:]
    private var mediaByHash: [String: Int] = [:]
    private var noteIDs: Set<Int> = []
    private var locationIDs: Set<Int> = []
    private var markIDs: Set<Int> = []
    private var playlistIDs: Set<Int> = []
    private var nextLocation = 1
    private var nextNote = 1
    private var nextMark = 1
    private var nextRange = 1
    private var nextBookmark = 1
    private var nextTag = 1
    private var nextTagMap = 1
    private var nextMedia = 1
    private var nextPlaylist = 1
    private var nextMarker = 1

    init() {}

    init(seed: LibraryDatabase, media: MediaCatalog) {
        database = seed
        mediaFiles = media
        nextLocation = (seed.locations.map(\.id).max() ?? 0) + 1
        nextNote = (seed.notes.map(\.id).max() ?? 0) + 1
        nextMark = (seed.userMarks.map(\.id).max() ?? 0) + 1
        nextRange = (seed.blockRanges.map(\.id).max() ?? 0) + 1
        nextBookmark = (seed.bookmarks.map(\.id).max() ?? 0) + 1
        nextTag = (seed.tags.map(\.id).max() ?? 0) + 1
        nextTagMap = (seed.tagMaps.map(\.id).max() ?? 0) + 1
        nextMedia = (seed.independentMedia.map(\.id).max() ?? 0) + 1
        nextPlaylist = (seed.playlistItems.map(\.id).max() ?? 0) + 1
        nextMarker = (seed.playlistItemMarkers.map(\.id).max() ?? 0) + 1
        for (index, location) in seed.locations.enumerated() {
            locationByKey[location.naturalKey] = location.id
            locationsByID[location.id] = index
            locationIDs.insert(location.id)
        }
        for tag in seed.tags { tagByKey[tag.nameKey] = tag.id }
        for (index, note) in seed.notes.enumerated() {
            noteByGUID[note.guid] = note.id
            notesByID[note.id] = index
            noteIDs.insert(note.id)
        }
        for (index, mark) in seed.userMarks.enumerated() {
            markByGUID[mark.userMarkGuid] = mark.id
            marksByID[mark.id] = index
            markIDs.insert(mark.id)
        }
        for (index, bookmark) in seed.bookmarks.enumerated() {
            bookmarkBySlot[bookmark.slotKey] = bookmark.contentKey
            bookmarksBySlotIndex[bookmark.slotKey] = index
        }
        for (index, field) in seed.inputFields.enumerated() {
            fieldByKey[field.fieldKey] = field.value
            fieldsByKeyIndex[field.fieldKey] = index
        }
        for media in seed.independentMedia {
            mediaByHash[media.hash] = media.id
        }
        for map in seed.tagMaps {
            tagMapKeys.insert(map.associationKey)
            tagMapPositions.insert(positionKey(tagId: map.tagId, position: map.position))
            maxPositionByTag[map.tagId] = max(maxPositionByTag[map.tagId] ?? -1, map.position)
        }
        for range in seed.blockRanges {
            rangesByMark[range.userMarkId, default: []].append(range.rangeKey)
            rangeRecordsByMark[range.userMarkId, default: []].append(range)
        }
        playlistIDs = Set(seed.playlistItems.map(\.id))
    }

    mutating func sanitizeDatabase() {
        database.sanitizeForeignKeys()
        noteIDs = Set(database.notes.map(\.id))
        locationIDs = Set(database.locations.map(\.id))
        markIDs = Set(database.userMarks.map(\.id))
        playlistIDs = Set(database.playlistItems.map(\.id))
        notesByID = Dictionary(uniqueKeysWithValues: database.notes.enumerated().map { ($0.element.id, $0.offset) })
        marksByID = Dictionary(uniqueKeysWithValues: database.userMarks.enumerated().map { ($0.element.id, $0.offset) })
        locationsByID = Dictionary(uniqueKeysWithValues: database.locations.enumerated().map { ($0.element.id, $0.offset) })
    }

    private func resolvedUserMarkID(_ incomingID: Int?, incomingMarksByID: [Int: UserMarkRecord]) -> Int? {
        guard let incomingID else { return nil }
        if let guid = incomingMarksByID[incomingID]?.userMarkGuid, let existing = markByGUID[guid] {
            return existing
        }
        return markIDs.contains(incomingID) ? incomingID : nil
    }

    private func clampedNote(_ note: NoteRecord) -> NoteRecord {
        var copy = note
        if let markID = copy.userMarkId, !markIDs.contains(markID) {
            copy.userMarkId = nil
        }
        if let locationID = copy.locationId, !locationIDs.contains(locationID) {
            copy.locationId = nil
        }
        return copy
    }

    mutating func ingestPrimary(_ backup: ImportedBackup) {
        let maps = remap(backup.database, includePlaylists: true)
        mediaFiles = backup.mediaFiles
        apply(maps.database)
    }

    mutating func mergeSecondary(_ backup: ImportedBackup, scope: MergeScope = .all) -> (conflicts: [MergeConflict], warnings: [MergeWarning]) {
        var conflicts: [MergeConflict] = []
        var warnings: [MergeWarning] = []
        let incoming = remap(backup.database, includePlaylists: false, scope: scope)
        if scope.videos {
            mediaFiles.formUnion(backup.mediaFiles)
        }
        let incomingRanges = Dictionary(grouping: incoming.database.blockRanges, by: \.userMarkId)
        var incomingNotesByID: [Int: NoteRecord] = [:]
        incomingNotesByID.reserveCapacity(incoming.database.notes.count)
        for note in incoming.database.notes {
            incomingNotesByID[note.id] = note
        }
        var incomingMarksByID: [Int: UserMarkRecord] = [:]
        incomingMarksByID.reserveCapacity(incoming.database.userMarks.count)
        for mark in incoming.database.userMarks {
            incomingMarksByID[mark.id] = mark
        }

        if scope.needsLocations {
            for location in incoming.database.locations {
                _ = addLocation(location)
            }
        }
        if scope.tags {
            for tag in incoming.database.tags where tag.type != 2 {
                _ = addTag(tag)
            }
        }
        if scope.videos {
            for media in incoming.database.independentMedia {
                _ = addMedia(media)
            }
        }

        if scope.highlights {
        for mark in incoming.database.userMarks {
            let ranges = incomingRanges[mark.id] ?? []
            if let existingID = markByGUID[mark.userMarkGuid],
               let existingIndex = marksByID[existingID] {
                let existing = database.userMarks[existingIndex]
                let existingRanges = rangeRecordsByMark[existing.id] ?? []
                if existing.colorIndex == mark.colorIndex,
                   existing.styleIndex == mark.styleIndex,
                   existing.version == mark.version,
                   existing.locationId == mark.locationId,
                   Set(existingRanges.map(\.rangeKey)) == Set(ranges.map(\.rangeKey)) {
                    continue
                }
                conflicts.append(
                    MergeConflict(
                        id: UUID(),
                        kind: .userMark,
                        key: mark.userMarkGuid,
                        left: ConflictSide(sourceIndex: 0, sourceName: "Primary", payload: .userMark(existing, ranges: existingRanges), modified: nil),
                        right: ConflictSide(sourceIndex: backup.sourceIndex, sourceName: backup.displayName, payload: .userMark(mark, ranges: ranges), modified: nil),
                        resolution: nil
                    )
                )
            } else {
                addMark(mark, ranges: ranges)
            }
        }
        }

        if scope.notes {
        for note in incoming.database.notes {
            var copy = note
            copy.userMarkId = resolvedUserMarkID(note.userMarkId, incomingMarksByID: incomingMarksByID)
            if let existingID = noteByGUID[copy.guid],
               let existingIndex = notesByID[existingID] {
                let existing = database.notes[existingIndex]
                if existing.bodyKey == copy.bodyKey {
                    if JWTimestamps.compare(copy.lastModified, existing.lastModified) == .orderedDescending {
                        database.notes[existingIndex].lastModified = copy.lastModified
                    }
                    continue
                }
                conflicts.append(
                    MergeConflict(
                        id: UUID(),
                        kind: .note,
                        key: copy.guid,
                        left: ConflictSide(sourceIndex: 0, sourceName: "Primary", payload: .note(existing), modified: existing.lastModified),
                        right: ConflictSide(sourceIndex: backup.sourceIndex, sourceName: backup.displayName, payload: .note(copy), modified: copy.lastModified),
                        resolution: nil
                    )
                )
            } else {
                addNote(copy)
            }
        }
        }

        if scope.bookmarks {
        for bookmark in incoming.database.bookmarks {
            if let existingContent = bookmarkBySlot[bookmark.slotKey] {
                if existingContent == bookmark.contentKey {
                    continue
                }
                if let index = bookmarksBySlotIndex[bookmark.slotKey] {
                    let existing = database.bookmarks[index]
                    conflicts.append(
                        MergeConflict(
                            id: UUID(),
                            kind: .bookmark,
                            key: bookmark.slotKey,
                            left: ConflictSide(sourceIndex: 0, sourceName: "Primary", payload: .bookmark(existing), modified: nil),
                            right: ConflictSide(sourceIndex: backup.sourceIndex, sourceName: backup.displayName, payload: .bookmark(bookmark), modified: nil),
                            resolution: nil
                        )
                    )
                }
            } else {
                addBookmark(bookmark)
            }
        }
        }

        if scope.inputFields {
        for field in incoming.database.inputFields {
            if let existingValue = fieldByKey[field.fieldKey] {
                if existingValue == field.value { continue }
                if let index = fieldsByKeyIndex[field.fieldKey] {
                    let existing = database.inputFields[index]
                    conflicts.append(
                        MergeConflict(
                            id: UUID(),
                            kind: .inputField,
                            key: field.fieldKey,
                            left: ConflictSide(sourceIndex: 0, sourceName: "Primary", payload: .inputField(existing), modified: nil),
                            right: ConflictSide(sourceIndex: backup.sourceIndex, sourceName: backup.displayName, payload: .inputField(field), modified: nil),
                            resolution: nil
                        )
                    )
                }
            } else {
                addField(field)
            }
        }
        }

        if scope.tags {
        for var map in incoming.database.tagMaps where map.playlistItemId == nil {
            if let noteID = map.noteId,
               let incomingNote = incomingNotesByID[noteID],
               let existingNoteID = noteByGUID[incomingNote.guid] {
                map.noteId = existingNoteID
            }
            addTagMap(map)
        }
        }

        if scope.videos && backup.database.hasPlaylists {
            warnings.append(
                MergeWarning(
                    id: UUID(),
                    message: "Playlists from “\(backup.displayName)” were kept only if they belong to the primary copy. Full playlist merging will arrive in a later version."
                )
            )
        }

        return (conflicts, warnings)
    }

    mutating func addResolved(_ payload: ConflictPayload, resolution: ConflictResolution, isAdditionalCopy: Bool) {
        switch payload {
        case .note(var note):
            if isAdditionalCopy {
                note.guid = UUID().uuidString.lowercased()
                addNote(note)
            } else if noteByGUID[note.guid] != nil {
                if resolution == .right || resolution == .newest {
                    replaceNote(note)
                }
            } else {
                addNote(note)
            }
        case .userMark(let mark, let ranges):
            if markByGUID[mark.userMarkGuid] != nil {
                if resolution == .right || resolution == .newest {
                    replaceMark(mark, ranges: ranges)
                }
            } else {
                addMark(mark, ranges: ranges)
            }
        case .bookmark(var bookmark):
            if bookmarkBySlot[bookmark.slotKey] != nil {
                if resolution == .keepBoth || isAdditionalCopy {
                    bookmark.slot = nextFreeSlot(publicationLocationId: bookmark.publicationLocationId)
                    addBookmark(bookmark)
                } else if resolution == .right || resolution == .newest {
                    replaceBookmark(bookmark)
                }
            } else {
                addBookmark(bookmark)
            }
        case .inputField(let field):
            if fieldByKey[field.fieldKey] != nil {
                if resolution == .right || resolution == .newest {
                    replaceField(field)
                }
            } else {
                addField(field)
            }
        }
    }

    private mutating func apply(_ incoming: LibraryDatabase) {
        for location in incoming.locations { _ = addLocation(location) }
        for tag in incoming.tags { _ = addTag(tag) }
        for media in incoming.independentMedia { _ = addMedia(media) }
        let rangesByMarkID = Dictionary(grouping: incoming.blockRanges, by: \.userMarkId)
        for mark in incoming.userMarks {
            addMark(mark, ranges: rangesByMarkID[mark.id] ?? [])
        }
        for note in incoming.notes { addNote(note) }
        for bookmark in incoming.bookmarks { addBookmark(bookmark) }
        for field in incoming.inputFields { addField(field) }
        database.playlistItems = incoming.playlistItems
        database.playlistItemIndependentMediaMaps = incoming.playlistItemIndependentMediaMaps
        database.playlistItemLocationMaps = incoming.playlistItemLocationMaps
        database.playlistItemMarkers = incoming.playlistItemMarkers
        database.playlistItemMarkerBibleVerseMaps = incoming.playlistItemMarkerBibleVerseMaps
        database.playlistItemMarkerParagraphMaps = incoming.playlistItemMarkerParagraphMaps
        playlistIDs = Set(incoming.playlistItems.map(\.id))
        nextPlaylist = (database.playlistItems.map(\.id).max() ?? 0) + 1
        nextMarker = (database.playlistItemMarkers.map(\.id).max() ?? 0) + 1
        for map in incoming.tagMaps { addTagMap(map) }
    }

    private mutating func remap(_ source: LibraryDatabase, includePlaylists: Bool, scope: MergeScope = .all) -> (database: LibraryDatabase, location: [Int: Int], mark: [Int: Int], note: [Int: Int], tag: [Int: Int]) {
        var output = LibraryDatabase()
        var locationMap: [Int: Int] = [:]
        var markMap: [Int: Int] = [:]
        var noteMap: [Int: Int] = [:]
        var tagMap: [Int: Int] = [:]
        var mediaMap: [Int: Int] = [:]
        var emittedLocations = Set<Int>()

        if includePlaylists || scope.needsLocations {
            for location in source.locations {
                let newID = addLocation(location)
                locationMap[location.id] = newID
                if emittedLocations.insert(newID).inserted, let index = locationsByID[newID] {
                    output.locations.append(database.locations[index])
                }
            }
        }

        if includePlaylists || scope.tags {
            for tag in source.tags {
                if !includePlaylists && tag.type == 2 { continue }
                let newID = addTag(tag)
                tagMap[tag.id] = newID
            }
        }

        if includePlaylists || scope.videos {
            for media in source.independentMedia {
                let newID = addMedia(media)
                mediaMap[media.id] = newID
            }
        }

        if includePlaylists || scope.highlights {
            for mark in source.userMarks {
                var copy = mark
                copy.locationId = locationMap[mark.locationId] ?? mark.locationId
                copy.id = nextMark
                nextMark += 1
                markMap[mark.id] = copy.id
                output.userMarks.append(copy)
            }

            for range in source.blockRanges {
                var copy = range
                copy.userMarkId = markMap[range.userMarkId] ?? range.userMarkId
                copy.id = nextRange
                nextRange += 1
                output.blockRanges.append(copy)
            }
        }

        if includePlaylists || scope.notes {
            for note in source.notes {
                var copy = note
                copy.locationId = copy.locationId.flatMap { locationMap[$0] } ?? copy.locationId
                if includePlaylists || scope.highlights {
                    copy.userMarkId = copy.userMarkId.flatMap { markMap[$0] } ?? copy.userMarkId
                } else {
                    copy.userMarkId = nil
                }
                copy.id = nextNote
                nextNote += 1
                noteMap[note.id] = copy.id
                output.notes.append(copy)
            }
        }

        if includePlaylists || scope.bookmarks {
            for bookmark in source.bookmarks {
                var copy = bookmark
                copy.locationId = locationMap[bookmark.locationId] ?? bookmark.locationId
                copy.publicationLocationId = locationMap[bookmark.publicationLocationId] ?? bookmark.publicationLocationId
                copy.id = nextBookmark
                nextBookmark += 1
                output.bookmarks.append(copy)
            }
        }

        if includePlaylists || scope.inputFields {
            for field in source.inputFields {
                var copy = field
                copy.locationId = locationMap[field.locationId] ?? field.locationId
                output.inputFields.append(copy)
            }
        }

        if includePlaylists || scope.tags {
            for map in source.tagMaps where map.playlistItemId == nil {
                var copy = map
                copy.locationId = copy.locationId.flatMap { locationMap[$0] } ?? copy.locationId
                copy.noteId = copy.noteId.flatMap { noteMap[$0] } ?? copy.noteId
                copy.tagId = tagMap[map.tagId] ?? map.tagId
                copy.id = nextTagMap
                nextTagMap += 1
                output.tagMaps.append(copy)
            }
        }

        if includePlaylists {
            var playlistMap: [Int: Int] = [:]
            var markerMap: [Int: Int] = [:]
            for item in source.playlistItems {
                var copy = item
                copy.id = nextPlaylist
                nextPlaylist += 1
                playlistMap[item.id] = copy.id
                output.playlistItems.append(copy)
            }
            output.playlistItemIndependentMediaMaps = source.playlistItemIndependentMediaMaps.map {
                PlaylistItemIndependentMediaMapRecord(
                    playlistItemId: playlistMap[$0.playlistItemId] ?? $0.playlistItemId,
                    independentMediaId: mediaMap[$0.independentMediaId] ?? $0.independentMediaId,
                    durationTicks: $0.durationTicks
                )
            }
            output.playlistItemLocationMaps = source.playlistItemLocationMaps.map {
                PlaylistItemLocationMapRecord(
                    playlistItemId: playlistMap[$0.playlistItemId] ?? $0.playlistItemId,
                    locationId: locationMap[$0.locationId] ?? $0.locationId,
                    majorMultimediaType: $0.majorMultimediaType,
                    baseDurationTicks: $0.baseDurationTicks
                )
            }
            for marker in source.playlistItemMarkers {
                var copy = marker
                copy.playlistItemId = playlistMap[marker.playlistItemId] ?? marker.playlistItemId
                copy.id = nextMarker
                nextMarker += 1
                markerMap[marker.id] = copy.id
                output.playlistItemMarkers.append(copy)
            }
            output.playlistItemMarkerBibleVerseMaps = source.playlistItemMarkerBibleVerseMaps.map {
                PlaylistItemMarkerBibleVerseMapRecord(
                    playlistItemMarkerId: markerMap[$0.playlistItemMarkerId] ?? $0.playlistItemMarkerId,
                    verseId: $0.verseId
                )
            }
            output.playlistItemMarkerParagraphMaps = source.playlistItemMarkerParagraphMaps.map {
                PlaylistItemMarkerParagraphMapRecord(
                    playlistItemMarkerId: markerMap[$0.playlistItemMarkerId] ?? $0.playlistItemMarkerId,
                    mepsDocumentId: $0.mepsDocumentId,
                    paragraphIndex: $0.paragraphIndex,
                    markerIndexWithinParagraph: $0.markerIndexWithinParagraph
                )
            }
            output.tagMaps.append(contentsOf: source.tagMaps.compactMap { map in
                guard let playlistID = map.playlistItemId, let newPlaylist = playlistMap[playlistID] else { return nil }
                var copy = map
                copy.playlistItemId = newPlaylist
                copy.tagId = tagMap[map.tagId] ?? map.tagId
                copy.id = nextTagMap
                nextTagMap += 1
                return copy
            })
        }

        return (output, locationMap, markMap, noteMap, tagMap)
    }

    private mutating func addLocation(_ location: LocationRecord) -> Int {
        if let existing = locationByKey[location.naturalKey] {
            if let index = locationsByID[existing] {
                database.locations[index] = database.locations[index].preferringTitle(from: location)
            }
            return existing
        }
        var copy = location
        copy.id = nextLocation
        nextLocation += 1
        locationByKey[copy.naturalKey] = copy.id
        locationsByID[copy.id] = database.locations.count
        locationIDs.insert(copy.id)
        database.locations.append(copy)
        return copy.id
    }

    private mutating func addTag(_ tag: TagRecord) -> Int {
        if let existing = tagByKey[tag.nameKey] {
            return existing
        }
        var copy = tag
        copy.id = nextTag
        nextTag += 1
        tagByKey[copy.nameKey] = copy.id
        database.tags.append(copy)
        return copy.id
    }

    private mutating func addMedia(_ media: IndependentMediaRecord) -> Int {
        if let existing = mediaByHash[media.hash],
           database.independentMedia.contains(where: { $0.id == existing && $0.filePath == media.filePath }) {
            return existing
        }
        var copy = media
        copy.id = nextMedia
        nextMedia += 1
        mediaByHash[copy.hash] = copy.id
        database.independentMedia.append(copy)
        return copy.id
    }

    private mutating func addMark(_ mark: UserMarkRecord, ranges: [BlockRangeRecord]) {
        if markByGUID[mark.userMarkGuid] != nil { return }
        var copy = mark
        if markIDs.contains(copy.id) || copy.id == 0 {
            copy.id = nextMark
            nextMark += 1
        } else {
            nextMark = max(nextMark, copy.id + 1)
        }
        markByGUID[copy.userMarkGuid] = copy.id
        marksByID[copy.id] = database.userMarks.count
        markIDs.insert(copy.id)
        database.userMarks.append(copy)
        for range in ranges {
            var item = range
            item.userMarkId = copy.id
            item.id = nextRange
            nextRange += 1
            database.blockRanges.append(item)
            rangesByMark[copy.id, default: []].append(item.rangeKey)
            rangeRecordsByMark[copy.id, default: []].append(item)
        }
    }

    private mutating func replaceMark(_ mark: UserMarkRecord, ranges: [BlockRangeRecord]) {
        guard let existingID = markByGUID[mark.userMarkGuid],
              let index = marksByID[existingID]
        else {
            addMark(mark, ranges: ranges)
            return
        }
        var copy = mark
        copy.id = existingID
        database.userMarks[index] = copy
        database.blockRanges.removeAll { $0.userMarkId == existingID }
        rangesByMark[existingID] = []
        rangeRecordsByMark[existingID] = []
        for range in ranges {
            var item = range
            item.userMarkId = existingID
            item.id = nextRange
            nextRange += 1
            database.blockRanges.append(item)
            rangesByMark[existingID, default: []].append(item.rangeKey)
            rangeRecordsByMark[existingID, default: []].append(item)
        }
    }

    private mutating func addNote(_ note: NoteRecord) {
        if noteByGUID[note.guid] != nil { return }
        var copy = clampedNote(note)
        if noteIDs.contains(copy.id) || copy.id == 0 {
            copy.id = nextNote
            nextNote += 1
        } else {
            nextNote = max(nextNote, copy.id + 1)
        }
        noteByGUID[copy.guid] = copy.id
        notesByID[copy.id] = database.notes.count
        noteIDs.insert(copy.id)
        database.notes.append(copy)
    }

    private mutating func replaceNote(_ note: NoteRecord) {
        guard let existingID = noteByGUID[note.guid],
              let index = notesByID[existingID]
        else {
            addNote(note)
            return
        }
        var copy = clampedNote(note)
        copy.id = existingID
        if copy.userMarkId == nil {
            copy.userMarkId = database.notes[index].userMarkId.flatMap { markIDs.contains($0) ? $0 : nil }
        }
        database.notes[index] = copy
    }

    private mutating func replaceBookmark(_ bookmark: BookmarkRecord) {
        guard let index = bookmarksBySlotIndex[bookmark.slotKey] else {
            addBookmark(bookmark)
            return
        }
        var copy = bookmark
        copy.id = database.bookmarks[index].id
        database.bookmarks[index] = copy
        bookmarkBySlot[copy.slotKey] = copy.contentKey
    }

    private mutating func replaceField(_ field: InputFieldRecord) {
        if let index = fieldsByKeyIndex[field.fieldKey] {
            database.inputFields[index] = field
            fieldByKey[field.fieldKey] = field.value
        } else {
            addField(field)
        }
    }

    private mutating func addBookmark(_ bookmark: BookmarkRecord) {
        if bookmarkBySlot[bookmark.slotKey] != nil { return }
        var copy = bookmark
        copy.id = nextBookmark
        nextBookmark += 1
        bookmarkBySlot[copy.slotKey] = copy.contentKey
        bookmarksBySlotIndex[copy.slotKey] = database.bookmarks.count
        database.bookmarks.append(copy)
    }

    private mutating func addField(_ field: InputFieldRecord) {
        if fieldByKey[field.fieldKey] != nil { return }
        fieldByKey[field.fieldKey] = field.value
        fieldsByKeyIndex[field.fieldKey] = database.inputFields.count
        database.inputFields.append(field)
    }

    private mutating func addTagMap(_ map: TagMapRecord) {
        if let noteID = map.noteId, !noteIDs.contains(noteID) { return }
        if let locationID = map.locationId, !locationIDs.contains(locationID) { return }
        if let playlistID = map.playlistItemId, !playlistIDs.contains(playlistID) { return }
        if tagMapKeys.contains(map.associationKey) { return }
        var copy = map
        copy.id = nextTagMap
        nextTagMap += 1
        let occupied = positionKey(tagId: copy.tagId, position: copy.position)
        if tagMapPositions.contains(occupied) {
            copy.position = (maxPositionByTag[copy.tagId] ?? -1) + 1
        }
        tagMapKeys.insert(copy.associationKey)
        tagMapPositions.insert(positionKey(tagId: copy.tagId, position: copy.position))
        maxPositionByTag[copy.tagId] = max(maxPositionByTag[copy.tagId] ?? -1, copy.position)
        database.tagMaps.append(copy)
    }

    private func nextFreeSlot(publicationLocationId: Int) -> Int {
        let used = Set(database.bookmarks.filter { $0.publicationLocationId == publicationLocationId }.map(\.slot))
        var slot = 0
        while used.contains(slot) { slot += 1 }
        return slot
    }

    private func positionKey(tagId: Int, position: Int) -> String {
        "\(tagId)|\(position)"
    }
}
