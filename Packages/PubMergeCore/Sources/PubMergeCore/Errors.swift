import Foundation

public enum PubMergeError: Error, LocalizedError, Equatable, Sendable {
    case notAZipArchive
    case missingManifest
    case invalidManifest
    case missingDatabase
    case corruptDatabase
    case hashMismatch(expected: String, actual: String)
    case unsupportedSchema(version: Int)
    case schemaMismatch(manifest: Int, database: Int)
    case foreignKeyViolation(String)
    case exportValidationFailed([String])
    case ioFailure(String)
    case zipFailure(String)
    case sqliteFailure(String)
    case unresolvedConflicts(Int)
    case emptyMerge
    case originalFileUnchangedRequired

    public var errorDescription: String? {
        switch self {
        case .notAZipArchive:
            return "The selected file is not a valid .jwlibrary archive."
        case .missingManifest:
            return "The archive does not contain manifest.json."
        case .invalidManifest:
            return "manifest.json is missing required fields or is not valid JSON."
        case .missingDatabase:
            return "The archive does not contain userData.db."
        case .corruptDatabase:
            return "The SQLite database could not be opened or is corrupt."
        case .hashMismatch(let expected, let actual):
            return "The database hash does not match the manifest (expected \(expected), found \(actual))."
        case .unsupportedSchema(let version):
            return "Database schema version \(version) is not supported. PubMerge can read schema 16 and safely upgrade 8–15. Newer versions are blocked to avoid a corrupt restore."
        case .schemaMismatch(let manifest, let database):
            return "The manifest schema (\(manifest)) does not match PRAGMA user_version (\(database))."
        case .foreignKeyViolation(let detail):
            return "Foreign key check failed: \(detail)"
        case .exportValidationFailed(let issues):
            return "The exported file failed validation: \(issues.joined(separator: "; "))"
        case .ioFailure(let detail):
            return "A file operation failed: \(detail)"
        case .zipFailure(let detail):
            return "The ZIP archive could not be processed: \(detail)"
        case .sqliteFailure(let detail):
            return "A database error occurred: \(detail)"
        case .unresolvedConflicts(let count):
            return "There are \(count) unresolved conflicts. Resolve them before exporting."
        case .emptyMerge:
            return "Import at least two valid backups before merging."
        case .originalFileUnchangedRequired:
            return "Original backup files are never modified."
        }
    }
}
