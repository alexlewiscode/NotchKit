import CryptoKit
import Foundation

public struct ValidatedNativeExtensionPackage: Equatable, Sendable {
    public let rootURL: URL
    public let manifest: NativeExtensionManifest
    public let providerApplicationURL: URL
    public let extensionBundleURL: URL
}

public enum NativeExtensionPackageError: Error, Equatable, LocalizedError {
    case packageIsNotDirectory
    case missingManifest
    case missingSignatureMetadata
    case malformedManifest(String)
    case malformedSignatureMetadata(String)
    case manifestHashMismatch
    case signatureIdentityMismatch
    case unsupportedSignatureVerification(String)
    case missingProviderApplication(String)
    case invalidProviderBundleIdentifier(expected: String, actual: String?)
    case missingExtensionBundle(String)
    case invalidExtensionBundleIdentifier(expected: String, actual: String?)
    case invalidCodeSignature(String)

    public var errorDescription: String? {
        switch self {
        case .packageIsNotDirectory:
            "The extension package must be an extracted directory"
        case .missingManifest:
            "The extension package has no manifest.json"
        case .missingSignatureMetadata:
            "The extension package has no signature.json"
        case let .malformedManifest(message):
            "The extension manifest could not be decoded: \(message)"
        case let .malformedSignatureMetadata(message):
            "The extension signature metadata could not be decoded: \(message)"
        case .manifestHashMismatch:
            "The extension manifest does not match signature.json"
        case .signatureIdentityMismatch:
            "The bundle identifiers in signature.json do not match the manifest"
        case let .unsupportedSignatureVerification(value):
            "Unsupported package signature verification mode: \(value)"
        case let .missingProviderApplication(name):
            "The package does not contain payload/\(name).app"
        case let .invalidProviderBundleIdentifier(expected, actual):
            "Provider bundle identifier mismatch; expected \(expected), found \(actual ?? "none")"
        case let .missingExtensionBundle(name):
            "The provider does not contain Contents/Extensions/\(name).appex"
        case let .invalidExtensionBundleIdentifier(expected, actual):
            "Extension bundle identifier mismatch; expected \(expected), found \(actual ?? "none")"
        case let .invalidCodeSignature(message):
            "Provider code signature is invalid: \(message)"
        }
    }
}

public enum NativeExtensionPackageValidator {
    public static func validatePackage(
        at rootURL: URL,
        verifyCodeSignature: Bool = true
    ) throws -> ValidatedNativeExtensionPackage {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw NativeExtensionPackageError.packageIsNotDirectory
        }

        let manifestURL = rootURL.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw NativeExtensionPackageError.missingManifest
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest: NativeExtensionManifest
        do {
            manifest = try JSONDecoder().decode(
                NativeExtensionManifest.self,
                from: manifestData
            )
        } catch {
            throw NativeExtensionPackageError.malformedManifest(error.localizedDescription)
        }
        try NativeExtensionManifestValidator.validate(manifest)

        let signatureURL = rootURL.appending(path: "signature.json")
        guard FileManager.default.fileExists(atPath: signatureURL.path) else {
            throw NativeExtensionPackageError.missingSignatureMetadata
        }
        let signature: SignatureMetadata
        do {
            signature = try JSONDecoder().decode(
                SignatureMetadata.self,
                from: Data(contentsOf: signatureURL)
            )
        } catch {
            throw NativeExtensionPackageError.malformedSignatureMetadata(error.localizedDescription)
        }
        guard signature.manifestSHA256 == sha256(manifestData) else {
            throw NativeExtensionPackageError.manifestHashMismatch
        }
        guard signature.providerBundleIdentifier == manifest.providerBundleIdentifier,
              signature.extensionBundleIdentifier == manifest.extensionBundleIdentifier
        else {
            throw NativeExtensionPackageError.signatureIdentityMismatch
        }
        guard signature.verification == "apple-code-signature" else {
            throw NativeExtensionPackageError.unsupportedSignatureVerification(signature.verification)
        }

        let providerName = finalBundleComponent(manifest.providerBundleIdentifier)
        let providerURL = rootURL.appending(path: "payload/\(providerName).app")
        guard FileManager.default.fileExists(atPath: providerURL.path) else {
            throw NativeExtensionPackageError.missingProviderApplication(providerName)
        }
        let providerBundleID = bundleIdentifier(at: providerURL)
        guard providerBundleID == manifest.providerBundleIdentifier else {
            throw NativeExtensionPackageError.invalidProviderBundleIdentifier(
                expected: manifest.providerBundleIdentifier,
                actual: providerBundleID
            )
        }

        let extensionName = finalBundleComponent(manifest.extensionBundleIdentifier)
        let extensionURL = providerURL.appending(path: "Contents/Extensions/\(extensionName).appex")
        guard FileManager.default.fileExists(atPath: extensionURL.path) else {
            throw NativeExtensionPackageError.missingExtensionBundle(extensionName)
        }
        let extensionBundleID = bundleIdentifier(at: extensionURL)
        guard extensionBundleID == manifest.extensionBundleIdentifier else {
            throw NativeExtensionPackageError.invalidExtensionBundleIdentifier(
                expected: manifest.extensionBundleIdentifier,
                actual: extensionBundleID
            )
        }

        if verifyCodeSignature {
            try validateCodeSignature(at: providerURL)
        }

        return ValidatedNativeExtensionPackage(
            rootURL: rootURL,
            manifest: manifest,
            providerApplicationURL: providerURL,
            extensionBundleURL: extensionURL
        )
    }

    public static func finalBundleComponent(_ identifier: String) -> String {
        identifier.split(separator: ".").last.map(String.init) ?? identifier
    }

    private static func bundleIdentifier(at bundleURL: URL) -> String? {
        guard let data = try? Data(contentsOf: bundleURL.appending(path: "Contents/Info.plist")),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary["CFBundleIdentifier"] as? String
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateCodeSignature(at providerURL: URL) throws {
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", "--deep", providerURL.path]
        process.standardError = standardError
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw NativeExtensionPackageError.invalidCodeSignature(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NativeExtensionPackageError.invalidCodeSignature(message)
        }
    }
}

private struct SignatureMetadata: Decodable {
    let manifestSHA256: String
    let providerBundleIdentifier: String
    let extensionBundleIdentifier: String
    let verification: String
}
