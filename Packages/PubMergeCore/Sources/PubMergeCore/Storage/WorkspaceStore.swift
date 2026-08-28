import CryptoKit
import Foundation

public struct WorkspaceStore: Sendable {
    public let rootURL: URL
    public var encryptTemporaryFiles: Bool

    public init(rootURL: URL? = nil, encryptTemporaryFiles: Bool = false) throws {
        let base = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PubMerge", isDirectory: true)
        guard let base else {
            throw PubMergeError.ioFailure("Application Support is not available.")
        }
        self.rootURL = base
        self.encryptTemporaryFiles = encryptTemporaryFiles
        try FileManager.default.createDirectory(at: originalsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportsURL, withIntermediateDirectories: true)
    }

    public var originalsURL: URL {
        rootURL.appendingPathComponent("Originals", isDirectory: true)
    }

    public var temporaryURL: URL {
        rootURL.appendingPathComponent("Temp", isDirectory: true)
    }

    public var exportsURL: URL {
        rootURL.appendingPathComponent("Exports", isDirectory: true)
    }

    public func copyOriginal(from source: URL, preferredName: String) throws -> URL {
        let safeName = sanitized(preferredName)
        let destination = uniqueURL(in: originalsURL, name: safeName)
        if source.standardizedFileURL == destination.standardizedFileURL {
            return destination
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: destination.path)
        return destination
    }

    public func temporaryFile(named name: String) -> URL {
        temporaryURL.appendingPathComponent(sanitized(name))
    }

    public func exportFile(named name: String) -> URL {
        uniqueURL(in: exportsURL, name: sanitized(name))
    }

    public func secureDeleteTemporaries() throws {
        try secureDeleteContents(of: temporaryURL)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
    }

    public func secureDeleteAllGenerated() throws {
        try secureDeleteTemporaries()
        try secureDeleteContents(of: exportsURL)
        try FileManager.default.createDirectory(at: exportsURL, withIntermediateDirectories: true)
    }

    public func writeTemporary(_ data: Data, named name: String) throws -> URL {
        let url = temporaryFile(named: name)
        if encryptTemporaryFiles {
            let sealed = try encrypt(data)
            try sealed.write(to: url, options: .atomic)
        } else {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    private func uniqueURL(in directory: URL, name: String) -> URL {
        var candidate = directory.appendingPathComponent(name)
        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(next)
            index += 1
        }
        return candidate
    }

    private func sanitized(_ name: String) -> String {
        let trimmed = (name as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars)
        return result.isEmpty ? "backup.jwlibrary" : result
    }

    private func secureDeleteContents(of directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        for url in urls {
            try overwriteThenRemove(url)
        }
    }

    private func overwriteThenRemove(_ url: URL) throws {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            let zeros = Data(repeating: 0, count: min(size, 1024 * 1024))
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                var remaining = size
                while remaining > 0 {
                    let chunk = min(remaining, zeros.count)
                    handle.write(zeros.prefix(chunk))
                    remaining -= chunk
                }
            }
        }
        try FileManager.default.removeItem(at: url)
    }

    private func encrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(size: .bits256)
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else {
            throw PubMergeError.ioFailure("Temporary encryption failed.")
        }
        var packed = Data()
        let raw = key.withUnsafeBytes { Data($0) }
        packed.append(UInt8(raw.count))
        packed.append(raw)
        packed.append(combined)
        return packed
    }
}
