import Foundation
import ZIPFoundation

public struct PackageArchiveLimits: Equatable, Sendable {
    public var maximumEntryCount: Int
    public var maximumPathLength: Int
    public var maximumPathDepth: Int
    public var maximumCompressedBytes: UInt64
    public var maximumExpandedBytes: UInt64
    public var maximumExpansionRatio: Double

    public init(
        maximumEntryCount: Int = 2_000,
        maximumPathLength: Int = 1_024,
        maximumPathDepth: Int = 32,
        maximumCompressedBytes: UInt64 = 256 * 1_024 * 1_024,
        maximumExpandedBytes: UInt64 = 1_024 * 1_024 * 1_024,
        maximumExpansionRatio: Double = 100
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumPathLength = maximumPathLength
        self.maximumPathDepth = maximumPathDepth
        self.maximumCompressedBytes = maximumCompressedBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.maximumExpansionRatio = maximumExpansionRatio
    }
}

public struct PackageArchivePreflight: Equatable, Sendable {
    public let entryCount: Int
    public let compressedBytes: UInt64
    public let expandedBytes: UInt64

    public init(entryCount: Int, compressedBytes: UInt64, expandedBytes: UInt64) {
        self.entryCount = entryCount
        self.compressedBytes = compressedBytes
        self.expandedBytes = expandedBytes
    }
}

public enum PackageArchiveError: Error, Equatable {
    case invalidFileExtension
    case unreadableArchive
    case encryptedArchive
    case unsafePath(String)
    case duplicatePath(String)
    case symlink(String)
    case unsupportedEntry(String)
    case tooManyEntries
    case pathTooLong(String)
    case pathTooDeep(String)
    case compressedSizeExceeded
    case expandedSizeExceeded
    case expansionRatioExceeded(String)
    case extractionFailed
}

public protocol PackageArchiveValidating: Sendable {
    @discardableResult
    func validateAndExtract(archiveURL: URL, to destinationURL: URL) throws -> PackageArchivePreflight
}

public struct ZIPPackageArchiveValidator: PackageArchiveValidating, Sendable {
    public let limits: PackageArchiveLimits

    public init(limits: PackageArchiveLimits = PackageArchiveLimits()) {
        self.limits = limits
    }

    @discardableResult
    public func validateAndExtract(archiveURL: URL, to destinationURL: URL) throws -> PackageArchivePreflight {
        guard archiveURL.pathExtension == "notchkitextension" else {
            throw PackageArchiveError.invalidFileExtension
        }
        let rawEntries = try CentralDirectoryScanner.scan(archiveURL)
        guard rawEntries.count <= limits.maximumEntryCount else {
            throw PackageArchiveError.tooManyEntries
        }
        var seen = Set<String>()
        var compressed: UInt64 = 0
        var expanded: UInt64 = 0
        for entry in rawEntries {
            try validate(entry: entry, seen: &seen)
            let (newCompressed, compressedOverflow) = compressed.addingReportingOverflow(entry.compressedSize)
            let (newExpanded, expandedOverflow) = expanded.addingReportingOverflow(entry.expandedSize)
            guard !compressedOverflow, newCompressed <= limits.maximumCompressedBytes else {
                throw PackageArchiveError.compressedSizeExceeded
            }
            guard !expandedOverflow, newExpanded <= limits.maximumExpandedBytes else {
                throw PackageArchiveError.expandedSizeExceeded
            }
            compressed = newCompressed
            expanded = newExpanded
            if entry.expandedSize > 0 {
                guard entry.compressedSize > 0,
                      Double(entry.expandedSize) / Double(entry.compressedSize) <= limits.maximumExpansionRatio
                else { throw PackageArchiveError.expansionRatioExceeded(entry.path) }
            }
        }

        do {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            let entries = Array(archive)
            // ZIPFoundation omits encrypted entries while iterating.
            guard entries.count == rawEntries.count else { throw PackageArchiveError.encryptedArchive }
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            for entry in entries {
                guard entry.type != .symlink else { throw PackageArchiveError.symlink(entry.path) }
                _ = try archive.extract(entry, to: destinationURL.appendingPathComponent(entry.path))
            }
        } catch let error as PackageArchiveError {
            throw error
        } catch {
            throw PackageArchiveError.extractionFailed
        }
        return PackageArchivePreflight(
            entryCount: rawEntries.count,
            compressedBytes: compressed,
            expandedBytes: expanded
        )
    }

    private func validate(entry: RawZIPEntry, seen: inout Set<String>) throws {
        let path = entry.path
        guard !entry.encrypted else { throw PackageArchiveError.encryptedArchive }
        guard path.utf8.count <= limits.maximumPathLength else {
            throw PackageArchiveError.pathTooLong(path)
        }
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.contains("\0"),
              !path.hasPrefix("~"),
              !(path.count >= 2 && path[path.index(after: path.startIndex)] == ":")
        else { throw PackageArchiveError.unsafePath(path) }
        var components = path.split(separator: "/", omittingEmptySubsequences: false)
        if path.hasSuffix("/") { components.removeLast() }
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw PackageArchiveError.unsafePath(path)
        }
        guard components.count <= limits.maximumPathDepth else {
            throw PackageArchiveError.pathTooDeep(path)
        }
        let normalized = components.joined(separator: "/")
        guard seen.insert(normalized).inserted else { throw PackageArchiveError.duplicatePath(path) }
        guard entry.compressionMethod == 0 || entry.compressionMethod == 8 else {
            throw PackageArchiveError.unsupportedEntry(path)
        }
        switch entry.kind {
        case .file, .directory: break
        case .symlink: throw PackageArchiveError.symlink(path)
        case .unsupported: throw PackageArchiveError.unsupportedEntry(path)
        }
    }
}

private struct RawZIPEntry {
    enum Kind { case file, directory, symlink, unsupported }
    let path: String
    let compressedSize: UInt64
    let expandedSize: UInt64
    let compressionMethod: UInt16
    let encrypted: Bool
    let kind: Kind
}

private enum CentralDirectoryScanner {
    static func scan(_ url: URL) throws -> [RawZIPEntry] {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw PackageArchiveError.unreadableArchive }
        guard data.count >= 22,
              let end = stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1)
                .first(where: { data.u32($0) == 0x06054b50 })
        else { throw PackageArchiveError.unreadableArchive }
        let count = Int(data.u16(end + 10))
        var offset = Int(data.u32(end + 16))
        var result: [RawZIPEntry] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard offset >= 0, offset + 46 <= data.count, data.u32(offset) == 0x02014b50 else {
                throw PackageArchiveError.unreadableArchive
            }
            let flags = data.u16(offset + 8)
            let method = data.u16(offset + 10)
            let compressed = UInt64(data.u32(offset + 20))
            let expanded = UInt64(data.u32(offset + 24))
            let nameLength = Int(data.u16(offset + 28))
            let extraLength = Int(data.u16(offset + 30))
            let commentLength = Int(data.u16(offset + 32))
            let endName = offset + 46 + nameLength
            guard endName <= data.count,
                  let path = String(data: data[(offset + 46)..<endName], encoding: (flags & 0x800) != 0 ? .utf8 : .isoLatin1)
            else { throw PackageArchiveError.unreadableArchive }
            let madeBy = data.u16(offset + 4)
            let os = madeBy >> 8
            let attributes = data.u32(offset + 38)
            let mode = UInt16((attributes >> 16) & 0xF000)
            let kind: RawZIPEntry.Kind
            if os == 3 || os == 19 {
                switch mode {
                case 0x8000, 0: kind = path.hasSuffix("/") ? .directory : .file
                case 0x4000: kind = .directory
                case 0xA000: kind = .symlink
                default: kind = .unsupported
                }
            } else {
                kind = path.hasSuffix("/") ? .directory : .file
            }
            result.append(RawZIPEntry(
                path: path,
                compressedSize: compressed,
                expandedSize: expanded,
                compressionMethod: method,
                encrypted: (flags & 1) != 0,
                kind: kind
            ))
            offset = endName + extraLength + commentLength
        }
        return result
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }
}
