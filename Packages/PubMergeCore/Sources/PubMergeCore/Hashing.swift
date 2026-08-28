import CryptoKit
import Foundation

public enum SHA256Hash: Sendable {
    public static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hex(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum JWTimestamps: Sendable {
    public static func nowISO() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date()).replacingOccurrences(of: "\\.\\d+Z$", with: "Z", options: .regularExpression)
    }

    public static func todayDateOnly() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    public static func compare(_ left: String, _ right: String) -> ComparisonResult {
        normalized(left).compare(normalized(right))
    }

    public static func newer(_ left: String, _ right: String) -> String {
        compare(left, right) == .orderedDescending ? left : right
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "T")
            .replacingOccurrences(of: "+00:00", with: "Z")
    }
}
