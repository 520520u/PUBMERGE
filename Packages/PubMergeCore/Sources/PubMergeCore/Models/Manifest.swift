import Foundation

public struct JWManifest: Codable, Equatable, Sendable {
    public var name: String
    public var creationDate: String
    public var version: Int
    public var type: Int
    public var userDataBackup: UserDataBackup

    public init(
        name: String,
        creationDate: String,
        version: Int = 1,
        type: Int = 0,
        userDataBackup: UserDataBackup
    ) {
        self.name = name
        self.creationDate = creationDate
        self.version = version
        self.type = type
        self.userDataBackup = userDataBackup
    }

    public static func decode(from data: Data) throws -> JWManifest {
        let decoder = JSONDecoder()
        guard let parsed = try? decoder.decode(JWManifest.self, from: data) else {
            throw PubMergeError.invalidManifest
        }
        guard parsed.version == 1,
              !parsed.userDataBackup.hash.isEmpty,
              !parsed.userDataBackup.databaseName.isEmpty
        else {
            throw PubMergeError.invalidManifest
        }
        return parsed
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public struct UserDataBackup: Codable, Equatable, Sendable {
    public var lastModifiedDate: String
    public var hash: String
    public var databaseName: String
    public var schemaVersion: Int
    public var deviceName: String

    public init(
        lastModifiedDate: String,
        hash: String,
        databaseName: String = "userData.db",
        schemaVersion: Int,
        deviceName: String
    ) {
        self.lastModifiedDate = lastModifiedDate
        self.hash = hash
        self.databaseName = databaseName
        self.schemaVersion = schemaVersion
        self.deviceName = deviceName
    }
}

public enum SchemaSupport: Equatable, Sendable {
    case supported(Int)
    case upgradable(from: Int, to: Int)
    case unsupported(Int)

    public var canExport: Bool {
        switch self {
        case .supported, .upgradable:
            return true
        case .unsupported:
            return false
        }
    }

    public var version: Int {
        switch self {
        case .supported(let version), .upgradable(let version, _), .unsupported(let version):
            return version
        }
    }
}

public enum SchemaPolicy: Sendable {
    public static let current = 16
    public static let minimumReadable = 8

    public static func classify(_ version: Int) -> SchemaSupport {
        if version == current {
            return .supported(version)
        }
        if version >= minimumReadable && version < current {
            return .upgradable(from: version, to: current)
        }
        return .unsupported(version)
    }
}
