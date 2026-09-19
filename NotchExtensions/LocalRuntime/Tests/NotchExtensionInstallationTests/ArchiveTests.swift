import Foundation
import NotchExtensionInstallation
import ZIPFoundation
import XCTest

final class ArchiveTests: XCTestCase {
    func testValidArchiveExtracts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("good.notchkitextension")
        try makeArchive(at: archive, entries: [("manifest.json", Data("{}".utf8))])
        let output = root.appendingPathComponent("output")
        let result = try ZIPPackageArchiveValidator().validateAndExtract(archiveURL: archive, to: output)
        XCTAssertEqual(result.entryCount, 1)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("manifest.json")), Data("{}".utf8))
    }

    func testRejectsWrongExtension() throws {
        let root = try temporaryDirectory()
        let archive = root.appendingPathComponent("bad.zip")
        try makeArchive(at: archive, entries: [("a", Data())])
        XCTAssertThrowsError(try ZIPPackageArchiveValidator().validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("o"))) {
            XCTAssertEqual($0 as? PackageArchiveError, .invalidFileExtension)
        }
    }

    func testRejectsTraversalAndAbsolutePaths() throws {
        for path in ["../escape", "../", "/absolute", "a/../../escape", "a//", "C:/escape", "a\\escape"] {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = root.appendingPathComponent("bad.notchkitextension")
            try makeArchive(at: archive, entries: [(path, Data("x".utf8))])
            XCTAssertThrowsError(try ZIPPackageArchiveValidator().validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("o")), path)
        }
    }

    func testRejectsSymlink() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appendingPathComponent("bad.notchkitextension")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let target = Data("target".utf8)
        try archive.addEntry(with: "link", type: .symlink, uncompressedSize: Int64(target.count)) { position, size in
            target.subdata(in: Int(position)..<min(Int(position) + size, target.count))
        }
        XCTAssertThrowsError(try ZIPPackageArchiveValidator().validateAndExtract(archiveURL: archiveURL, to: root.appendingPathComponent("o"))) {
            XCTAssertEqual($0 as? PackageArchiveError, .symlink("link"))
        }
    }

    func testRejectsEntryCountPathLengthAndDepthLimits() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("bad.notchkitextension")
        try makeArchive(at: archive, entries: [("a/b/c", Data()), ("second", Data())])
        XCTAssertThrowsError(try ZIPPackageArchiveValidator(limits: .init(maximumEntryCount: 1)).validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("one")))
        XCTAssertThrowsError(try ZIPPackageArchiveValidator(limits: .init(maximumPathLength: 2)).validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("two")))
        XCTAssertThrowsError(try ZIPPackageArchiveValidator(limits: .init(maximumPathDepth: 2)).validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("three")))
    }

    func testRejectsCompressedExpandedAndRatioLimits() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("bad.notchkitextension")
        try makeArchive(at: archive, entries: [("large", Data(repeating: 0, count: 10_000))], compression: .deflate)
        XCTAssertThrowsError(try ZIPPackageArchiveValidator(limits: .init(maximumCompressedBytes: 1)).validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("one")))
        XCTAssertThrowsError(try ZIPPackageArchiveValidator(limits: .init(maximumExpandedBytes: 10)).validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("two")))
        XCTAssertThrowsError(try ZIPPackageArchiveValidator(limits: .init(maximumExpansionRatio: 2)).validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("three")))
    }

    func testRejectsEncryptedFlagWhenDetectable() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("bad.notchkitextension")
        try makeArchive(at: archive, entries: [("a", Data("x".utf8))])
        var data = try Data(contentsOf: archive)
        for signature in [Data([0x50, 0x4b, 0x03, 0x04]), Data([0x50, 0x4b, 0x01, 0x02])] {
            let range = data.range(of: signature)!
            let flagOffset = range.lowerBound + (signature[2] == 3 ? 6 : 8)
            data[flagOffset] |= 1
        }
        try data.write(to: archive)
        XCTAssertThrowsError(try ZIPPackageArchiveValidator().validateAndExtract(archiveURL: archive, to: root.appendingPathComponent("o"))) {
            XCTAssertEqual($0 as? PackageArchiveError, .encryptedArchive)
        }
    }
}
