import Foundation

public struct ImportOptions: Sendable {
    public var allowHashMismatch: Bool
    public var copyOriginals: Bool

    public init(allowHashMismatch: Bool = true, copyOriginals: Bool = true) {
        self.allowHashMismatch = allowHashMismatch
        self.copyOriginals = copyOriginals
    }
}

public enum JWLibraryArchive {
    public static func importBackup(
        from sourceURL: URL,
        workspace: WorkspaceStore,
        sourceIndex: Int,
        options: ImportOptions = ImportOptions(),
        progress: WorkProgressHandler? = nil
    ) throws -> ImportedBackup {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0

        ProgressReporting.emit(progress, fraction: 0.08, stage: .copyOriginal)
        let originalCopy = options.copyOriginals
            ? try workspace.copyOriginal(from: sourceURL, preferredName: sourceURL.lastPathComponent)
            : sourceURL

        ProgressReporting.emit(progress, fraction: 0.18, stage: .listArchive)
        let entries = try ZipArchive.listEntries(at: originalCopy)

        ProgressReporting.emit(progress, fraction: 0.28, stage: .extractDatabase)
        let extracted = try ZipArchive.extractFiles(named: ["manifest.json", "userData.db"], from: originalCopy)
        guard let manifestData = extracted["manifest.json"] else {
            throw PubMergeError.missingManifest
        }
        let manifest = try JWManifest.decode(from: manifestData)
        let databaseName = manifest.userDataBackup.databaseName
        let databaseData: Data
        if let exact = extracted[databaseName] ?? extracted["userData.db"] {
            databaseData = exact
        } else if let extra = try ZipArchive.extractFileIfPresent(named: databaseName, from: originalCopy) {
            databaseData = extra
        } else {
            throw PubMergeError.missingDatabase
        }

        let actualHash = SHA256Hash.hex(of: databaseData)
        var hashWarning: String?
        if actualHash.caseInsensitiveCompare(manifest.userDataBackup.hash) != .orderedSame {
            if options.allowHashMismatch {
                hashWarning = "The stored hash does not match the database. The original file was not modified."
            } else {
                throw PubMergeError.hashMismatch(expected: manifest.userDataBackup.hash, actual: actualHash)
            }
        }

        let extractedDB = workspace.temporaryFile(named: "\(UUID().uuidString)-userData.db")
        try databaseData.write(to: extractedDB, options: .atomic)

        ProgressReporting.emit(progress, fraction: 0.55, stage: .readDatabase)
        let (database, userVersion) = try SchemaAdapter.loadDatabase(from: extractedDB)
        if userVersion != manifest.userDataBackup.schemaVersion && abs(userVersion - manifest.userDataBackup.schemaVersion) > 0 {
            if userVersion == 0 {
                throw PubMergeError.corruptDatabase
            }
        }

        let schema = SchemaPolicy.classify(max(userVersion, manifest.userDataBackup.schemaVersion))
        if case .unsupported(let version) = schema {
            throw PubMergeError.unsupportedSchema(version: version)
        }

        let reserved = Set(["manifest.json", "./manifest.json", databaseName, "userData.db"])
        let mediaNames = entries
            .map(\.name)
            .filter { !reserved.contains($0) && !$0.hasSuffix("/") && !$0.hasPrefix("__MACOSX") }

        try? FileManager.default.removeItem(at: extractedDB)
        ProgressReporting.emit(progress, fraction: 1, stage: .readDatabase)

        return ImportedBackup(
            displayName: manifest.userDataBackup.deviceName.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : manifest.userDataBackup.deviceName,
            originalFileName: sourceURL.lastPathComponent,
            fileSize: fileSize,
            originalBackupURL: originalCopy,
            manifest: manifest,
            schema: schema,
            hashWarning: hashWarning,
            database: database,
            mediaFiles: MediaCatalog(archives: [originalCopy], names: mediaNames),
            sourceIndex: sourceIndex
        )
    }

    public static func inspect(data: Data) throws -> JWManifest {
        let files = try ZipArchive.unzip(data)
        guard let manifestData = files["manifest.json"] else {
            throw PubMergeError.missingManifest
        }
        return try JWManifest.decode(from: manifestData)
    }
}
