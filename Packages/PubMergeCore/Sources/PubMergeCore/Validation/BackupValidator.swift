import Foundation

public struct ValidationReport: Equatable, Sendable {
    public var issues: [String]
    public var schemaVersion: Int
    public var hash: String
    public var journalMode: String
    public var tableCount: Int
    public var statistics: BackupStatistics

    public var isValid: Bool { issues.isEmpty }
}

public enum BackupValidator {
    public static func validate(file url: URL) throws -> ValidationReport {
        let extracted = try ZipArchive.extractFiles(named: ["manifest.json", "userData.db"], from: url)
        guard let manifestData = extracted["manifest.json"] else {
            return ValidationReport(issues: ["Missing manifest.json"], schemaVersion: 0, hash: "", journalMode: "", tableCount: 0, statistics: BackupStatistics())
        }
        let manifest: JWManifest
        do {
            manifest = try JWManifest.decode(from: manifestData)
        } catch {
            return ValidationReport(issues: ["Invalid manifest.json"], schemaVersion: 0, hash: "", journalMode: "", tableCount: 0, statistics: BackupStatistics())
        }
        let databaseData: Data?
        if let exact = extracted[manifest.userDataBackup.databaseName] ?? extracted["userData.db"] {
            databaseData = exact
        } else {
            databaseData = try ZipArchive.extractFileIfPresent(named: manifest.userDataBackup.databaseName, from: url)
        }
        guard let dbData = databaseData else {
            return ValidationReport(issues: ["Missing userData.db"], schemaVersion: manifest.userDataBackup.schemaVersion, hash: "", journalMode: "", tableCount: 0, statistics: BackupStatistics())
        }
        return try validate(database: dbData, manifest: manifest)
    }

    public static func validate(archive data: Data) throws -> ValidationReport {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jwlibrary")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        return try validate(file: temporary)
    }

    public static func validate(database dbData: Data, manifest: JWManifest) throws -> ValidationReport {
        var issues: [String] = []
        let hash = SHA256Hash.hex(of: dbData)
        if hash.caseInsensitiveCompare(manifest.userDataBackup.hash) != .orderedSame {
            issues.append("Manifest hash does not match userData.db.")
        }
        if !manifest.name.lowercased().hasSuffix(".jwlibrary") {
            issues.append("Manifest name must end with .jwlibrary.")
        }
        if manifest.creationDate.count != 10 {
            issues.append("creationDate must be YYYY-MM-DD.")
        }
        if manifest.userDataBackup.schemaVersion != SchemaV16.userVersion {
            issues.append("Exported schemaVersion must be \(SchemaV16.userVersion).")
        }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).db")
        try dbData.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }

        let db: SQLiteDatabase
        do {
            db = try SQLiteDatabase(path: temp.path, readOnly: true)
        } catch {
            issues.append("SQLite database could not be opened.")
            return ValidationReport(issues: issues, schemaVersion: 0, hash: hash, journalMode: "", tableCount: 0, statistics: BackupStatistics())
        }
        defer { db.close() }

        let version = try db.userVersion()
        if version != SchemaV16.userVersion {
            issues.append("PRAGMA user_version is \(version), expected \(SchemaV16.userVersion).")
        }
        let journal = try db.journalMode().lowercased()
        if journal != "delete" {
            issues.append("journal_mode is \(journal), expected delete.")
        }
        for table in SchemaV16.requiredTables {
            if try !db.tableExists(table) {
                issues.append("Missing table \(table).")
            }
        }
        let violations = try db.foreignKeyViolations()
        issues.append(contentsOf: violations.map { "Foreign key: \($0)" })

        let (library, _) = (try? SchemaAdapter.loadDatabase(from: temp)) ?? (LibraryDatabase(), version)
        let tableCount = try db.scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
        return ValidationReport(
            issues: issues,
            schemaVersion: version,
            hash: hash,
            journalMode: journal,
            tableCount: tableCount,
            statistics: library.statistics
        )
    }
}
