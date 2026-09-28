import CryptoKit
import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK

private struct ValidationCheck: Encodable {
    let name: String
    let status: String
    let code: String
    let message: String
}

private struct HubValidationReport: Encodable {
    let artifactSha256: String
    let validatorVersion: String
    let teamIdentifier: String?
    let signerType: String?
    let notarized: Bool
    let stapled: Bool
    let manifestSHA256: String?
    let catalogMetadata: [String: AnyEncodable]?
    let checks: [ValidationCheck]
    let completedAt: String
}

private struct AnyEncodable: Encodable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        if let value = value as? AnyEncodable {
            try value.encode(to: encoder)
        } else if let dictionary = value as? [String: Any] {
            var container = encoder.container(keyedBy: DynamicKey.self)
            for (key, value) in dictionary {
                try container.encode(AnyEncodable(value), forKey: DynamicKey(stringValue: key))
            }
        } else if let array = value as? [Any] {
            var container = encoder.unkeyedContainer()
            for value in array { try container.encode(AnyEncodable(value)) }
        } else {
            var container = encoder.singleValueContainer()
            switch value {
            case let value as String: try container.encode(value)
            case let value as Bool: try container.encode(value)
            case let value as Int: try container.encode(value)
            case is NSNull: try container.encodeNil()
            default: throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported report value"))
            }
        }
    }
}

private struct DynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private struct Arguments {
    let archive: URL
    let submissionID: String
    let expectedSHA256: String
    let expectedSize: Int64

    init(_ values: [String]) throws {
        guard values.count == 9,
              values[0] == "validate-archive",
              values[2] == "--submission",
              values[4] == "--sha256",
              values[6] == "--size",
              values[8] == "--json",
              let size = Int64(values[7]),
              size > 0,
              values[5].count == 64,
              values[5].allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else { throw ValidatorError.usage }
        archive = URL(fileURLWithPath: values[1]).standardizedFileURL
        submissionID = values[3]
        expectedSHA256 = values[5]
        expectedSize = size
    }
}

private enum ValidatorError: Error, CustomStringConvertible {
    case usage
    case artifactDigestMismatch
    case invalidMarketplaceManifest(String)
    case invalidCodeSignature(String)
    case inconsistentSignerTeams
    case mixedSignerTypes
    case incompleteCatalogMetadata
    case missingExecutable(String)
    case unsupportedArchitecture(String)

    var description: String {
        switch self {
        case .usage:
            "Usage: notchkit-hub-validator validate-archive <archive> --submission <uuid> --sha256 <lowercase-hex> --size <bytes> --json"
        case .artifactDigestMismatch: "Measured archive hash or size does not match the worker input."
        case let .invalidMarketplaceManifest(message): message
        case let .invalidCodeSignature(message): message
        case .inconsistentSignerTeams: "Provider and nested app extension must use the same Apple signing Team ID."
        case .mixedSignerTypes: "Provider and nested app extension must use the same signer class."
        case .incompleteCatalogMetadata: "The manifest is missing catalog-required display metadata."
        case let .missingExecutable(name): "Bundle executable is missing: \(name)"
        case let .unsupportedArchitecture(name): "Bundle executable is missing a declared architecture: \(name)"
        }
    }

    var checkCode: String {
        switch self {
        case .usage: "validator.usage"
        case .artifactDigestMismatch: "artifact.digest_mismatch"
        case .invalidMarketplaceManifest: "manifest.invalid"
        case .invalidCodeSignature: "signature.invalid"
        case .inconsistentSignerTeams: "signature.team_mismatch"
        case .mixedSignerTypes: "signature.signer_type_mismatch"
        case .incompleteCatalogMetadata: "manifest.catalog_metadata_missing"
        case .missingExecutable: "architecture.executable_missing"
        case .unsupportedArchitecture: "architecture.unsupported"
        }
    }

    var checkName: String {
        switch self {
        case .usage: "validatorInvocation"
        case .artifactDigestMismatch: "artifactDigest"
        case .invalidMarketplaceManifest: "marketplaceManifest"
        case .invalidCodeSignature, .inconsistentSignerTeams, .mixedSignerTypes: "appleCodeSignature"
        case .incompleteCatalogMetadata: "catalogMetadata"
        case .missingExecutable, .unsupportedArchitecture: "architecture"
        }
    }
}

private struct Measurement {
    let sha256: String
    let size: Int64
}

private func measure(_ url: URL) throws -> Measurement {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hasher = SHA256()
    var size: Int64 = 0
    while true {
        let chunk = try file.read(upToCount: 64 * 1024) ?? Data()
        if chunk.isEmpty { break }
        size += Int64(chunk.count)
        hasher.update(data: chunk)
    }
    return Measurement(
        sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
        size: size
    )
}

private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    } catch {
        return (127, error.localizedDescription)
    }
}

private func validateArchitecture(_ url: URL, declared: Set<String>) throws {
    let infoURL = url.appendingPathComponent("Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
          let executable = info["CFBundleExecutable"] as? String
    else { throw ValidatorError.missingExecutable(url.lastPathComponent) }
    let binaryURL = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
    guard FileManager.default.fileExists(atPath: binaryURL.path) else {
        throw ValidatorError.missingExecutable(binaryURL.path)
    }
    let result = run("/usr/bin/lipo", ["-archs", binaryURL.path])
    let actual = Set(result.output.split(whereSeparator: \.isWhitespace).map(String.init))
    guard result.status == 0, !declared.isEmpty, declared.isSubset(of: actual) else {
        throw ValidatorError.unsupportedArchitecture(url.lastPathComponent)
    }
}

private func encodableMetadata(_ package: ExtensionPackageManifest, manifestSHA256: String) -> [String: AnyEncodable] {
    let metadata = package.metadata
    let artifact = package.artifact.appExtension!
    let entryPoints: [[String: AnyEncodable]] = package.entryPoints.map { point in
        [
            "id": AnyEncodable(point.entryPoint.id),
            "kind": AnyEncodable(point.entryPoint.kind.rawValue),
            "sceneName": AnyEncodable(point.sceneName ?? NSNull()),
            "metadata": AnyEncodable(point.entryPoint.metadata),
        ]
    }
    let permissions: [[String: AnyEncodable]] = package.permissions.map { permission in
        [
            "kind": AnyEncodable(permission.kind.rawValue),
            "required": AnyEncodable(permission.required),
            "owner": AnyEncodable(permission.owner.rawValue),
            "usageDescriptionKey": AnyEncodable(permission.usageDescriptionKey),
        ]
    }
    return [
        "displayName": AnyEncodable(metadata.displayName),
        "summary": AnyEncodable(metadata.summary ?? ""),
        "iconSystemName": AnyEncodable(metadata.iconSystemName),
        "iconURL": AnyEncodable(NSNull()),
        "manifestSHA256": AnyEncodable(manifestSHA256),
        "providerBundleIdentifier": AnyEncodable(artifact.providerBundleIdentifier),
        "extensionBundleIdentifier": AnyEncodable(artifact.extensionBundleIdentifier),
        "extensionPointIdentifier": AnyEncodable(artifact.extensionPointIdentifier),
        "compatibility": AnyEncodable([
            "minimumMacOSVersion": artifact.minimumMacOSVersion.description,
            "supportedHostVersions": ["minimum": metadata.supportedHostVersions.minimum.description,
                                      "maximum": metadata.supportedHostVersions.maximum?.description as Any? ?? NSNull()],
            "supportedSDKVersions": ["minimum": metadata.supportedSDKVersions.minimum.description,
                                     "maximum": metadata.supportedSDKVersions.maximum?.description as Any? ?? NSNull()],
            "apiVersion": metadata.apiVersion.description,
            "protocolVersions": ["minimum": artifact.protocolVersions.minimum,
                                 "maximum": artifact.protocolVersions.maximum],
            "supportedArchitectures": artifact.architectures.map(\.rawValue).sorted(),
        ] as [String: Any]),
        "capabilities": AnyEncodable(metadata.capabilities.map(\.rawValue).sorted()),
        "entryPoints": AnyEncodable(entryPoints.map { AnyEncodable($0) }),
        "permissions": AnyEncodable(permissions.map { AnyEncodable($0) }),
        "hostActions": AnyEncodable(package.hostActions.map(\.rawValue).sorted()),
    ]
}

private func validate(_ arguments: Arguments) throws -> HubValidationReport {
    let measured = try measure(arguments.archive)
    guard measured.sha256 == arguments.expectedSHA256, measured.size == arguments.expectedSize else {
        throw ValidatorError.artifactDigestMismatch
    }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("notchkit-hub-validator-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    do {
        try ZIPPackageArchiveValidator().validateAndExtract(archiveURL: arguments.archive, to: staging)
        let package = try DefaultExtractedPackageValidator().validate(packageRootURL: staging, context: .marketplace)
        guard let artifact = package.packageManifest.artifact.appExtension else {
            throw ValidatorError.invalidMarketplaceManifest("The package is not an app extension.")
        }
        guard let summary = package.packageManifest.metadata.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { throw ValidatorError.incompleteCatalogMetadata }

        let signatureValidator = SecurityCodeSignatureValidator()
        let provider = try signatureValidator.validateCode(at: package.providerURL)
        let nested = try package.extensionURLs.map { try signatureValidator.validateCode(at: $0) }
        guard !provider.teamIdentifier.isEmpty,
              nested.allSatisfy({ $0.teamIdentifier == provider.teamIdentifier })
        else { throw ValidatorError.inconsistentSignerTeams }
        let allSigners = [provider] + nested
        let signerTypes = Set(allSigners.map(\.isDeveloperID))
        guard signerTypes.count == 1 else { throw ValidatorError.mixedSignerTypes }
        let declared = Set(artifact.architectures.map(\.rawValue))
        try validateArchitecture(package.providerURL, declared: declared)
        for extensionURL in package.extensionURLs { try validateArchitecture(extensionURL, declared: declared) }

        let manifestSHA = SHA256.hash(data: package.manifestData).map { String(format: "%02x", $0) }.joined()
        let stapler = run("/usr/bin/xcrun", ["stapler", "validate", package.providerURL.path])
        let stapled = stapler.status == 0
        let checks = [
            ValidationCheck(name: "archiveAndManifest", status: "passed", code: "package.valid", message: "Archive, layout, marketplace manifest, and embedded manifest are valid."),
            ValidationCheck(name: "appleCodeSignature", status: "passed", code: "apple_code_signature_valid", message: "Provider and nested extension have valid Apple-anchored signatures with matching Team IDs."),
            ValidationCheck(name: "architecture", status: "passed", code: "architecture.supported", message: "Provider and nested extension include all manifest-declared architectures."),
            ValidationCheck(name: "notarization", status: stapled ? "passed" : "not-required", code: stapled ? "notarization.ticket_present" : "notarization.optional", message: stapled ? "A valid stapled ticket is present." : "Notarization is optional; this release will rely on manual review."),
            ValidationCheck(name: "stapling", status: stapled ? "passed" : "not-required", code: stapled ? "stapling.valid" : "stapling.optional", message: stapled ? "The stapled ticket validates." : "Stapling is optional for manually reviewed releases."),
        ]
        return HubValidationReport(
            artifactSha256: measured.sha256,
            validatorVersion: "0.2.0",
            teamIdentifier: provider.teamIdentifier,
            signerType: provider.isDeveloperID ? "developerID" : "appleDevelopment",
            notarized: stapled,
            stapled: stapled,
            manifestSHA256: manifestSHA,
            catalogMetadata: encodableMetadata(package.packageManifest, manifestSHA256: manifestSHA),
            checks: checks,
            completedAt: ISO8601DateFormatter().string(from: Date())
        )
    } catch let error as ValidatorError {
        throw error
    } catch let error as CodeSignatureValidationError {
        throw ValidatorError.invalidCodeSignature(String(describing: error))
    } catch {
        throw ValidatorError.invalidMarketplaceManifest(String(describing: error))
    }
}

do {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    let report = try validate(arguments)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data([0x0a]))
} catch let error as ValidatorError where error.checkCode != "validator.usage" {
    let arguments = try? Arguments(Array(CommandLine.arguments.dropFirst()))
    let sha = arguments.flatMap { try? measure($0.archive).sha256 } ?? String(repeating: "0", count: 64)
    let report = HubValidationReport(
        artifactSha256: sha,
        validatorVersion: "0.2.0",
        teamIdentifier: nil,
        signerType: nil,
        notarized: false,
        stapled: false,
        manifestSHA256: nil,
        catalogMetadata: nil,
        checks: [ValidationCheck(name: error.checkName, status: "failed", code: error.checkCode, message: error.description)],
        completedAt: ISO8601DateFormatter().string(from: Date())
    )
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data([0x0a]))
    } catch {
        FileHandle.standardError.write(Data("Failed to encode validation report: \(error)\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
