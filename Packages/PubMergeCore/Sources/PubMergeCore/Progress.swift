import Foundation

public enum WorkStage: String, Sendable {
    case importCopies
    case copyOriginal
    case listArchive
    case extractDatabase
    case readDatabase
    case mergePrimary
    case mergeSecondary
    case compare
    case writeDatabase
    case packageArchive
    case packageMedia
    case validate
    case export

    public var localizationKey: String {
        switch self {
        case .importCopies: return "progress_import"
        case .copyOriginal: return "progress_copy_original"
        case .listArchive: return "progress_list_archive"
        case .extractDatabase: return "progress_extract_database"
        case .readDatabase: return "progress_read_database"
        case .mergePrimary: return "progress_merge_primary"
        case .mergeSecondary: return "progress_merge_secondary"
        case .compare: return "progress_build_compare"
        case .writeDatabase: return "progress_write_database"
        case .packageArchive: return "progress_package_archive"
        case .packageMedia: return "progress_package_media"
        case .validate: return "progress_validate"
        case .export: return "progress_export"
        }
    }
}

public struct WorkProgress: Sendable, Equatable {
    public var fraction: Double
    public var stage: WorkStage
    public var detail: String?

    public init(fraction: Double, stage: WorkStage, detail: String? = nil) {
        self.fraction = min(max(fraction, 0), 1)
        self.stage = stage
        self.detail = detail
    }
}

public typealias WorkProgressHandler = @Sendable (WorkProgress) -> Void

enum ProgressReporting {
    static func emit(_ handler: WorkProgressHandler?, fraction: Double, stage: WorkStage, detail: String? = nil) {
        handler?(WorkProgress(fraction: fraction, stage: stage, detail: detail))
    }
}
