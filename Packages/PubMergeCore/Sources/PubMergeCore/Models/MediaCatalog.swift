import Foundation

public struct MediaCatalog: Equatable, Sendable {
    public var archives: [URL]
    public var names: [String]
    public var inlineFiles: [String: Data]

    public init(archives: [URL] = [], names: [String] = [], inlineFiles: [String: Data] = [:]) {
        self.archives = archives
        self.names = names
        self.inlineFiles = inlineFiles
    }

    public var isEmpty: Bool {
        names.isEmpty && inlineFiles.isEmpty
    }

    public func contains(_ name: String) -> Bool {
        inlineFiles[name] != nil || names.contains(name) || names.contains { Self.namesMatch($0, name) }
    }

    public mutating func formUnion(_ other: MediaCatalog) {
        for url in other.archives where !archives.contains(url) {
            archives.append(url)
        }
        var seen = Set(names)
        for name in other.names where seen.insert(name).inserted {
            names.append(name)
        }
        for (key, value) in other.inlineFiles where inlineFiles[key] == nil {
            inlineFiles[key] = value
        }
    }

    public func data(for name: String) throws -> Data {
        if let inline = inlineFiles[name] {
            return inline
        }
        if let inline = inlineFiles.first(where: { Self.namesMatch($0.key, name) })?.value {
            return inline
        }
        let candidates = [name, (name as NSString).lastPathComponent]
        for url in archives {
            for candidate in candidates where !candidate.isEmpty {
                if let data = try ZipArchive.extractFileIfPresent(named: candidate, from: url) {
                    return data
                }
            }
        }
        throw PubMergeError.zipFailure("Media file “\(name)” was not found in the original backup.")
    }

    static func namesMatch(_ entryName: String, _ wanted: String) -> Bool {
        if entryName == wanted { return true }
        if entryName == "./\(wanted)" { return true }
        if entryName.hasSuffix("/\(wanted)") { return true }
        let entryBase = (entryName as NSString).lastPathComponent
        let wantedBase = (wanted as NSString).lastPathComponent
        return !entryBase.isEmpty && entryBase == wantedBase
    }
}
