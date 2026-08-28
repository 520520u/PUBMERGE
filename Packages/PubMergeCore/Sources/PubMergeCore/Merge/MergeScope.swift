import Foundation

public struct MergeScope: Equatable, Sendable {
    public var notes: Bool
    public var highlights: Bool
    public var bookmarks: Bool
    public var tags: Bool
    public var inputFields: Bool
    public var videos: Bool

    public static let all = MergeScope()

    public init(
        notes: Bool = true,
        highlights: Bool = true,
        bookmarks: Bool = true,
        tags: Bool = true,
        inputFields: Bool = true,
        videos: Bool = true
    ) {
        self.notes = notes
        self.highlights = highlights
        self.bookmarks = bookmarks
        self.tags = tags
        self.inputFields = inputFields
        self.videos = videos
    }

    public var isAll: Bool {
        notes && highlights && bookmarks && tags && inputFields && videos
    }

    public var isEmpty: Bool {
        !notes && !highlights && !bookmarks && !tags && !inputFields && !videos
    }

    public var selectedCount: Int {
        [notes, highlights, bookmarks, tags, inputFields, videos].filter(\.self).count
    }

    public var needsLocations: Bool {
        notes || highlights || bookmarks || inputFields || tags
    }

    public mutating func selectAll() {
        self = .all
    }

    public mutating func selectNone() {
        notes = false
        highlights = false
        bookmarks = false
        tags = false
        inputFields = false
        videos = false
    }

    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case notes
        case highlights
        case bookmarks
        case tags
        case inputFields
        case videos

        public var id: String { rawValue }
    }

    public subscript(category: Category) -> Bool {
        get {
            switch category {
            case .notes: return notes
            case .highlights: return highlights
            case .bookmarks: return bookmarks
            case .tags: return tags
            case .inputFields: return inputFields
            case .videos: return videos
            }
        }
        set {
            switch category {
            case .notes: notes = newValue
            case .highlights: highlights = newValue
            case .bookmarks: bookmarks = newValue
            case .tags: tags = newValue
            case .inputFields: inputFields = newValue
            case .videos: videos = newValue
            }
        }
    }
}
