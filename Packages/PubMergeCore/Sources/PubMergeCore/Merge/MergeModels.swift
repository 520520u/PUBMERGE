import Foundation

public enum MergeRule: String, CaseIterable, Identifiable, Sendable {
    case newest
    case primary
    case secondary
    case keepBothNotes

    public var id: String { rawValue }
}

public enum ConflictResolution: String, Equatable, Sendable {
    case left
    case right
    case newest
    case keepBoth
}

public enum ConflictPayload: Equatable, Sendable {
    case note(NoteRecord)
    case userMark(UserMarkRecord, ranges: [BlockRangeRecord])
    case bookmark(BookmarkRecord)
    case inputField(InputFieldRecord)

    public var kind: ItemKind {
        switch self {
        case .note: return .note
        case .userMark: return .userMark
        case .bookmark: return .bookmark
        case .inputField: return .inputField
        }
    }

    public var title: String {
        switch self {
        case .note(let note):
            return note.title?.isEmpty == false ? note.title! : String(note.content?.prefix(48) ?? "Note")
        case .userMark(let mark, _):
            return "Highlight \(mark.userMarkGuid.prefix(8))"
        case .bookmark(let bookmark):
            return bookmark.title
        case .inputField(let field):
            return field.textTag
        }
    }

    public var detail: String {
        switch self {
        case .note(let note):
            return note.content ?? ""
        case .userMark(let mark, let ranges):
            return "Color \(mark.colorIndex), style \(mark.styleIndex), version \(mark.version), ranges \(ranges.count)"
        case .bookmark(let bookmark):
            return bookmark.snippet ?? bookmark.title
        case .inputField(let field):
            return field.value
        }
    }
}

public struct ConflictSide: Equatable, Sendable {
    public var sourceIndex: Int
    public var sourceName: String
    public var payload: ConflictPayload
    public var modified: String?
}

public struct MergeConflict: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var key: String
    public var left: ConflictSide
    public var right: ConflictSide
    public var resolution: ConflictResolution?

    public var isResolved: Bool { resolution != nil }
}

public struct MergeDecision: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var kind: ItemKind
    public var key: String
    public var choice: ConflictResolution
    public var summary: String
}

public struct MergeWarning: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var message: String
}

public struct MergePlan: Equatable, Sendable {
    public var base: LibraryDatabase
    public var merged: LibraryDatabase
    public var mediaFiles: MediaCatalog
    public var conflicts: [MergeConflict]
    public var decisions: [MergeDecision]
    public var warnings: [MergeWarning]
    public var primaryName: String
    public var sourceCount: Int
    public var scope: MergeScope

    public var unresolvedCount: Int {
        conflicts.filter { !$0.isResolved }.count
    }

    public var canExport: Bool {
        unresolvedCount == 0
    }

    public mutating func updateNote(guid: String, title: String?, content: String?, modified: String, sourceIndex: Int? = nil) {
        _ = merged.updateNote(guid: guid, title: title, content: content, modified: modified)
        _ = base.updateNote(guid: guid, title: title, content: content, modified: modified)
        for index in conflicts.indices {
            if case .note(var note) = conflicts[index].left.payload, note.guid == guid {
                if sourceIndex == nil || conflicts[index].left.sourceIndex == sourceIndex {
                    note.title = title
                    note.content = content
                    note.lastModified = modified
                    conflicts[index].left.payload = .note(note)
                    conflicts[index].left.modified = modified
                }
            }
            if case .note(var note) = conflicts[index].right.payload, note.guid == guid {
                if sourceIndex == nil || conflicts[index].right.sourceIndex == sourceIndex {
                    note.title = title
                    note.content = content
                    note.lastModified = modified
                    conflicts[index].right.payload = .note(note)
                    conflicts[index].right.modified = modified
                }
            }
        }
    }

    public mutating func deleteNote(guid: String) {
        _ = merged.deleteNote(guid: guid)
        _ = base.deleteNote(guid: guid)
        conflicts.removeAll { conflict in
            conflict.left.noteGuid == guid || conflict.right.noteGuid == guid
        }
    }
}

extension ConflictSide {
    public var noteGuid: String? {
        if case .note(let note) = payload {
            return note.guid
        }
        return nil
    }
}

public struct ComparisonSnapshot: Equatable, Sendable {
    public var items: [ComparableItem]
    public var totals: BackupStatistics
    public var addedCounts: BackupStatistics
    public var conflictCount: Int
}
