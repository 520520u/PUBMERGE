import Foundation
import zlib

struct ZipEntry: Equatable, Sendable {
    var name: String
    var compression: UInt16
    var compressedSize: Int
    var uncompressedSize: Int
    var localHeaderOffset: Int
}

enum ZipArchive {
    static func unzip(_ data: Data) throws -> [String: Data] {
        let entries = try listEntries(in: data)
        var files: [String: Data] = [:]
        for entry in entries {
            files[entry.name] = try extract(entry, from: data)
        }
        return files
    }

    static func zip(_ files: [String: Data]) throws -> Data {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try zip(files, to: temporary)
        return try Data(contentsOf: temporary)
    }

    static func zip(_ files: [String: Data], to url: URL) throws {
        let writer = try ZipStreamingWriter(destination: url)
        for name in files.keys.sorted() {
            try writer.addFile(name: name, data: files[name] ?? Data())
        }
        try writer.finish()
    }

    static func listEntries(at url: URL) throws -> [ZipEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size >= 22 else { throw PubMergeError.notAZipArchive }

        let tailLength = min(size, UInt64(0xFFFF + 22))
        try handle.seek(toOffset: size - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard let eocd = findEOCD(in: tail) else {
            throw PubMergeError.notAZipArchive
        }
        try rejectZip64(eocd)

        try handle.seek(toOffset: UInt64(eocd.centralDirectoryOffset))
        let directoryLength = eocd.centralDirectorySize > 0
            ? eocd.centralDirectorySize
            : max(0, Int(size) - eocd.centralDirectoryOffset)
        let directory = try handle.read(upToCount: max(directoryLength, 46)) ?? Data()
        return try parseCentralDirectory(directory, entryCount: eocd.entryCount)
    }

    static func listEntries(in data: Data) throws -> [ZipEntry] {
        guard let eocd = findEOCD(in: data) else {
            throw PubMergeError.notAZipArchive
        }
        try rejectZip64(eocd)
        guard eocd.centralDirectoryOffset + 46 <= data.count || eocd.entryCount == 0 else {
            throw PubMergeError.zipFailure("Truncated central directory.")
        }
        let directory = data.suffix(from: eocd.centralDirectoryOffset)
        return try parseCentralDirectory(Data(directory), entryCount: eocd.entryCount)
    }

    static func extractFile(named name: String, from url: URL) throws -> Data {
        guard let data = try extractFileIfPresent(named: name, from: url) else {
            throw PubMergeError.zipFailure("ZIP entry “\(name)” is missing.")
        }
        return data
    }

    static func extractFileIfPresent(named name: String, from url: URL) throws -> Data? {
        let entries = try listEntries(at: url)
        guard let entry = entries.first(where: { MediaCatalog.namesMatch($0.name, name) }) else {
            return nil
        }
        return try extract(entry, from: url)
    }

    static func extractFiles(named names: [String], from url: URL) throws -> [String: Data] {
        let entries = try listEntries(at: url)
        var result: [String: Data] = [:]
        for name in names {
            if let entry = entries.first(where: { MediaCatalog.namesMatch($0.name, name) }) {
                result[name] = try extract(entry, from: url)
            }
        }
        return result
    }

    static func extract(_ entry: ZipEntry, from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(entry.localHeaderOffset))
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30, readUInt32(header, 0) == 0x04034b50 else {
            throw PubMergeError.zipFailure("Invalid local file header.")
        }
        let nameLength = Int(readUInt16(header, 26))
        let extraLength = Int(readUInt16(header, 28))
        try handle.seek(toOffset: UInt64(entry.localHeaderOffset + 30 + nameLength + extraLength))
        let compressed = try handle.read(upToCount: entry.compressedSize) ?? Data()
        guard compressed.count == entry.compressedSize else {
            throw PubMergeError.zipFailure("Compressed file data is truncated.")
        }
        return try decompress(compressed, method: entry.compression, expectedSize: entry.uncompressedSize)
    }

    private static func extract(_ entry: ZipEntry, from data: Data) throws -> Data {
        try extractFile(
            from: data,
            localHeaderOffset: entry.localHeaderOffset,
            compression: entry.compression,
            compressedSize: entry.compressedSize,
            uncompressedSize: entry.uncompressedSize
        )
    }

    private static func parseCentralDirectory(_ data: Data, entryCount: Int) throws -> [ZipEntry] {
        var entries: [ZipEntry] = []
        entries.reserveCapacity(entryCount)
        var offset = 0
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count else {
                throw PubMergeError.zipFailure("Truncated central directory.")
            }
            let signature = readUInt32(data, offset)
            guard signature == 0x02014b50 else {
                throw PubMergeError.zipFailure("Invalid central directory signature.")
            }
            let compression = readUInt16(data, offset + 10)
            let compressedSize = Int(readUInt32(data, offset + 20))
            let uncompressedSize = Int(readUInt32(data, offset + 24))
            let nameLength = Int(readUInt16(data, offset + 28))
            let extraLength = Int(readUInt16(data, offset + 30))
            let commentLength = Int(readUInt16(data, offset + 32))
            let localHeaderOffset = Int(readUInt32(data, offset + 42))
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localHeaderOffset == 0xFFFF_FFFF {
                throw PubMergeError.zipFailure("ZIP64 archives are not supported yet.")
            }
            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else {
                throw PubMergeError.zipFailure("Invalid file name in ZIP.")
            }
            let name = String(decoding: data[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            entries.append(
                ZipEntry(
                    name: name,
                    compression: compression,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private struct EOCD {
        var entryCount: Int
        var centralDirectorySize: Int
        var centralDirectoryOffset: Int
    }

    private static func findEOCD(in data: Data) -> EOCD? {
        let minimum = 22
        guard data.count >= minimum else { return nil }
        let maxComment = min(data.count - minimum, 0xFFFF)
        for comment in 0...maxComment {
            let offset = data.count - minimum - comment
            if readUInt32(data, offset) == 0x06054b50 {
                return EOCD(
                    entryCount: Int(readUInt16(data, offset + 10)),
                    centralDirectorySize: Int(readUInt32(data, offset + 12)),
                    centralDirectoryOffset: Int(readUInt32(data, offset + 16))
                )
            }
        }
        return nil
    }

    private static func rejectZip64(_ eocd: EOCD) throws {
        if eocd.entryCount == 0xFFFF || eocd.centralDirectoryOffset == 0xFFFF_FFFF || eocd.centralDirectorySize == 0xFFFF_FFFF {
            throw PubMergeError.zipFailure("ZIP64 archives are not supported yet.")
        }
    }

    private static func extractFile(
        from data: Data,
        localHeaderOffset: Int,
        compression: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data {
        guard localHeaderOffset + 30 <= data.count, readUInt32(data, localHeaderOffset) == 0x04034b50 else {
            throw PubMergeError.zipFailure("Invalid local file header.")
        }
        let nameLength = Int(readUInt16(data, localHeaderOffset + 26))
        let extraLength = Int(readUInt16(data, localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + nameLength + extraLength
        guard dataStart + compressedSize <= data.count else {
            throw PubMergeError.zipFailure("Compressed file data is truncated.")
        }
        let compressed = data[dataStart..<(dataStart + compressedSize)]
        return try decompress(Data(compressed), method: compression, expectedSize: uncompressedSize)
    }

    private static func decompress(_ compressed: Data, method: UInt16, expectedSize: Int) throws -> Data {
        switch method {
        case 0:
            return compressed
        case 8:
            return try inflateRaw(compressed, expectedSize: expectedSize)
        default:
            throw PubMergeError.zipFailure("Unsupported ZIP compression method \(method).")
        }
    }

    static func deflateRaw(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }
        var stream = z_stream()
        let status = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            throw PubMergeError.zipFailure("deflateInit failed.")
        }
        defer { deflateEnd(&stream) }

        return try data.withUnsafeBytes { raw in
            guard let pointer = raw.bindMemory(to: Bytef.self).baseAddress else {
                throw PubMergeError.zipFailure("deflate source was empty.")
            }
            stream.next_in = UnsafeMutablePointer(mutating: pointer)
            stream.avail_in = uInt(data.count)
            var output = Data()
            var buffer = [Bytef](repeating: 0, count: min(65_536, max(1024, data.count / 2 + 64)))
            while true {
                let result: Int32 = buffer.withUnsafeMutableBufferPointer { dest in
                    stream.next_out = dest.baseAddress
                    stream.avail_out = uInt(dest.count)
                    return deflate(&stream, Z_FINISH)
                }
                output.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
                if result == Z_STREAM_END {
                    return output
                }
                if result != Z_OK {
                    throw PubMergeError.zipFailure("deflate failed with status \(result).")
                }
            }
        }
    }

    static func inflateRaw(_ data: Data, expectedSize: Int) throws -> Data {
        if data.isEmpty { return Data() }
        var stream = z_stream()
        let status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            throw PubMergeError.zipFailure("inflateInit failed.")
        }
        defer { inflateEnd(&stream) }

        return try data.withUnsafeBytes { raw in
            guard let pointer = raw.bindMemory(to: Bytef.self).baseAddress else {
                throw PubMergeError.zipFailure("inflate source was empty.")
            }
            stream.next_in = UnsafeMutablePointer(mutating: pointer)
            stream.avail_in = uInt(data.count)
            var output = Data()
            output.reserveCapacity(max(expectedSize, 64))
            var buffer = [Bytef](repeating: 0, count: min(65_536, max(1024, expectedSize > 0 ? min(expectedSize, 65_536) : 4096)))
            while true {
                let result: Int32 = buffer.withUnsafeMutableBufferPointer { dest in
                    stream.next_out = dest.baseAddress
                    stream.avail_out = uInt(dest.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                output.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
                if result == Z_STREAM_END {
                    return output
                }
                if result != Z_OK {
                    throw PubMergeError.zipFailure("inflate failed with status \(result).")
                }
            }
        }
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            let pointer = raw.bindMemory(to: Bytef.self).baseAddress
            return UInt32(crc32(0, pointer, uInt(data.count)))
        }
    }
}

final class ZipStreamingWriter {
    private let handle: FileHandle
    private var central = Data()
    private var entryCount = 0
    private var localBytesWritten: UInt64 = 0
    private var finished = false

    init(destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw PubMergeError.ioFailure("Could not create \(destination.lastPathComponent).")
        }
        handle = try FileHandle(forWritingTo: destination)
    }

    func addFile(name: String, data: Data) throws {
        let nameData = Data(name.utf8)
        let compressed = try ZipArchive.deflateRaw(data)
        let crc = ZipArchive.checksum(data)
        guard compressed.count <= Int(UInt32.max), data.count <= Int(UInt32.max), localBytesWritten <= UInt64(UInt32.max) else {
            throw PubMergeError.zipFailure("The archive exceeds the ZIP32 size limit.")
        }
        let localOffset = UInt32(localBytesWritten)
        var local = Data()
        local.append(contentsOf: u32(0x04034b50))
        local.append(contentsOf: u16(20))
        local.append(contentsOf: u16(0))
        local.append(contentsOf: u16(8))
        local.append(contentsOf: u16(0))
        local.append(contentsOf: u16(0))
        local.append(contentsOf: u32(crc))
        local.append(contentsOf: u32(UInt32(compressed.count)))
        local.append(contentsOf: u32(UInt32(data.count)))
        local.append(contentsOf: u16(UInt16(nameData.count)))
        local.append(contentsOf: u16(0))
        local.append(nameData)
        local.append(compressed)
        try handle.write(contentsOf: local)
        localBytesWritten += UInt64(local.count)

        central.append(contentsOf: u32(0x02014b50))
        central.append(contentsOf: u16(20))
        central.append(contentsOf: u16(20))
        central.append(contentsOf: u16(0))
        central.append(contentsOf: u16(8))
        central.append(contentsOf: u16(0))
        central.append(contentsOf: u16(0))
        central.append(contentsOf: u32(crc))
        central.append(contentsOf: u32(UInt32(compressed.count)))
        central.append(contentsOf: u32(UInt32(data.count)))
        central.append(contentsOf: u16(UInt16(nameData.count)))
        central.append(contentsOf: u16(0))
        central.append(contentsOf: u16(0))
        central.append(contentsOf: u16(0))
        central.append(contentsOf: u16(0))
        central.append(contentsOf: u32(0))
        central.append(contentsOf: u32(localOffset))
        central.append(nameData)
        entryCount += 1
    }

    func finish() throws {
        guard !finished else { return }
        finished = true
        guard entryCount <= Int(UInt16.max), central.count <= Int(UInt32.max), localBytesWritten <= UInt64(UInt32.max) else {
            throw PubMergeError.zipFailure("The archive exceeds the ZIP32 size limit.")
        }
        var footer = central
        footer.append(contentsOf: u32(0x06054b50))
        footer.append(contentsOf: u16(0))
        footer.append(contentsOf: u16(0))
        footer.append(contentsOf: u16(UInt16(entryCount)))
        footer.append(contentsOf: u16(UInt16(entryCount)))
        footer.append(contentsOf: u32(UInt32(central.count)))
        footer.append(contentsOf: u32(UInt32(localBytesWritten)))
        footer.append(contentsOf: u16(0))
        try handle.write(contentsOf: footer)
        try handle.close()
    }

    deinit {
        if !finished {
            try? handle.close()
        }
    }
}

private func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

private func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16
        | UInt32(data[offset + 3]) << 24
}

private func u16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
}

private func u32(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ]
}
