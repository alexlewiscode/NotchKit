//
//  ManifestValidator.swift
//  ValidationCore
//
//  Strict, JSON-only validation of a NotchKit extension manifest.
//
//  The validator never loads or executes extension code. It performs two
//  clearly separated passes:
//
//  1. STRUCTURAL: strict decoding against the canonical key/type/enum surface
//     of `NotchExtensions/manifests/manifest.schema.json`. `JSONSerialization`
//     is used for explicit key and type checks because `Codable` silently
//     ignores unknown keys. Any structural issue short-circuits the second pass.
//  2. HOST COMPATIBILITY: only when structure is sound, the decoded
//     `ExtensionMetadata` is validated with `ExtensionCompatibility.validate`.
//

import CoreFoundation
import Foundation
import NotchExtensionSDK

/// Validates extension manifests.
public enum ManifestValidator {

    /// Validates a manifest and returns every issue found.
    ///
    /// - Parameters:
    ///   - data: raw JSON manifest bytes.
    ///   - hostVersion: the running host application version.
    ///   - sdkVersion: the running extension SDK/API version.
    /// - Returns: issues in detection order. Structural issues short-circuit
    ///   host-compatibility checks, so the two phases are never mixed when the
    ///   manifest could not be decoded.
    public static func validate(
        data: Data,
        hostVersion: ExtensionVersion,
        sdkVersion: ExtensionAPIVersion
    ) -> [ValidationIssue] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let root = object as? [String: Any]
        else {
            return [
                issue(
                    ValidationCode.invalidJSON,
                    "Manifest is not a JSON object."
                )
            ]
        }

        var checker = StructuralChecker(root: root)
        let structural = checker.check()
        guard structural.isEmpty else { return structural }

        let metadata: ExtensionMetadata
        do {
            metadata = try JSONDecoder().decode(ExtensionMetadata.self, from: data)
        } catch {
            return [
                issue(
                    ValidationCode.decodeFailed,
                    "Manifest could not be decoded: \(error)"
                )
            ]
        }

        do {
            try ExtensionCompatibility.validate(
                metadata,
                hostVersion: hostVersion,
                sdkVersion: sdkVersion
            )
            return []
        } catch let error as ExtensionCompatibilityError {
            return [compatibilityIssue(error)]
        } catch {
            return [
                issue(
                    ValidationCode.compatibilityFailed,
                    "Compatibility validation failed: \(error)"
                )
            ]
        }
    }

    // MARK: - Issue helpers

    static func issue(
        _ code: String,
        _ message: String,
        path: String? = nil,
        phase: ValidationPhase = .structural,
        severity: ValidationSeverity = .error
    ) -> ValidationIssue {
        ValidationIssue(
            severity: severity,
            phase: phase,
            code: code,
            message: message,
            path: path
        )
    }

    private static func compatibilityIssue(_ error: ExtensionCompatibilityError) -> ValidationIssue {
        switch error {
        case let .unsupportedArtifactKind(_, kind):
            return issue(
                ValidationCode.unsupportedArtifactKind,
                "Artifact kind '\(kind.rawValue)' is not supported by this host.",
                phase: .hostCompatibility
            )
        case let .unsupportedHostVersion(_, required, running):
            return issue(
                ValidationCode.unsupportedHostVersion,
                "Host version \(running) is outside the required range \(required).",
                phase: .hostCompatibility
            )
        case let .unsupportedSDKVersion(_, required, running):
            return issue(
                ValidationCode.unsupportedSDKVersion,
                "SDK version \(running) is outside the required range \(required).",
                phase: .hostCompatibility
            )
        case let .undeclaredCapability(_, capability):
            return issue(
                ValidationCode.undeclaredCapability,
                "An entry point requires capability '\(capability.rawValue)' that is not declared.",
                phase: .hostCompatibility
            )
        case let .capabilityWithoutEntryPoint(_, capability):
            return issue(
                ValidationCode.capabilityWithoutEntryPoint,
                "Declared capability '\(capability.rawValue)' has no matching entry point.",
                phase: .hostCompatibility
            )
        case let .duplicateEntryPoint(_, id):
            return issue(
                ValidationCode.duplicateEntryPoint,
                "Duplicate entry point id '\(id)'.",
                phase: .hostCompatibility
            )
        }
    }
}

// MARK: - Structural pass

/// The canonical key sets, mirrored from `manifest.schema.json`.
private enum Schema {
    /// Keys permitted at the top level.
    ///
    /// `$schema` is not listed in the schema's `additionalProperties` set, but
    /// it is the standard JSON-Schema self-description annotation and is present
    /// in the canonical reference example. It is accepted here as a documented,
    /// non-negotiable exception; every other unknown key is rejected.
    static let topLevelKeys: Set<String> = [
        "$schema",
        "id", "displayName", "summary", "iconSystemName",
        "extensionVersion", "apiVersion",
        "supportedHostVersions", "supportedSDKVersions",
        "capabilities", "artifactKind", "entryPoints",
        "defaultEnabled", "source",
    ]

    static let requiredTopLevelKeys: [String] = [
        "id", "displayName", "iconSystemName",
        "extensionVersion", "apiVersion",
        "supportedHostVersions", "supportedSDKVersions",
        "capabilities", "artifactKind", "entryPoints",
        "defaultEnabled", "source",
    ]

    static let entryPointKeys: Set<String> = ["id", "kind", "sceneName", "metadata"]

    static let capabilities: Set<String> = [
        "open-destination", "closed-notch-contribution", "settings-destination",
    ]

    static let artifactKinds: Set<String> = ["compiled-in", "app-extension", "xpc-service"]

    static let sources: Set<String> = ["firstParty"]
}

private struct StructuralChecker {
    let root: [String: Any]
    private var issues: [ValidationIssue] = []

    init(root: [String: Any]) {
        self.root = root
    }

    mutating func check() -> [ValidationIssue] {
        checkUnknownTopLevelKeys()
        checkMissingRequiredFields()
        checkIdentity()
        checkNonEmptyString("displayName")
        checkString("summary")
        checkNonEmptyString("iconSystemName")
        checkVersion("extensionVersion")
        checkVersion("apiVersion")
        checkVersionRange("supportedHostVersions")
        checkVersionRange("supportedSDKVersions")
        checkCapabilities()
        checkArtifactKind()
        checkEntryPoints()
        checkBoolean("defaultEnabled")
        checkSource()
        return issues
    }

    // MARK: Key presence

    private mutating func checkUnknownTopLevelKeys() {
        for key in root.keys where !Schema.topLevelKeys.contains(key) {
            add(
                ValidationCode.unknownKey,
                "Unknown top-level key '\(key)'.",
                path: "$.\(key)"
            )
        }
    }

    private mutating func checkMissingRequiredFields() {
        for key in Schema.requiredTopLevelKeys where root[key] == nil {
            add(
                ValidationCode.missingRequiredField,
                "Missing required field '\(key)'.",
                path: "$.\(key)"
            )
        }
    }

    // MARK: Scalar fields

    private mutating func checkIdentity() {
        guard let value = root["id"] else { return }
        guard let string = value as? String else {
            addInvalidType("id", expected: "a string", path: "$.id")
            return
        }
        do {
            _ = try ExtensionIdentity(string)
        } catch {
            add(
                ValidationCode.invalidIdentity,
                "'\(string)' is not a valid reverse-DNS identity (at least three components).",
                path: "$.id"
            )
        }
    }

    private mutating func checkNonEmptyString(_ key: String) {
        guard let value = root[key] else { return }
        guard let string = value as? String else {
            addInvalidType(key, expected: "a string", path: "$.\(key)")
            return
        }
        if string.isEmpty {
            add(
                ValidationCode.emptyString,
                "Field '\(key)' must not be empty.",
                path: "$.\(key)"
            )
        }
    }

    private mutating func checkString(_ key: String) {
        guard let value = root[key] else { return }
        if !(value is String) {
            addInvalidType(key, expected: "a string", path: "$.\(key)")
        }
    }

    private mutating func checkVersion(_ key: String) {
        guard let value = root[key] else { return }
        guard let string = value as? String else {
            addInvalidType(key, expected: "a semantic version string", path: "$.\(key)")
            return
        }
        if ExtensionVersion(string) == nil {
            add(
                ValidationCode.invalidVersion,
                "'\(string)' is not a valid major.minor.patch version.",
                path: "$.\(key)"
            )
        }
    }

    private mutating func checkVersionRange(_ key: String) {
        guard let value = root[key] else { return }
        guard let string = value as? String else {
            addInvalidType(key, expected: "a version range string", path: "$.\(key)")
            return
        }
        if ExtensionVersionRange.parse(string) == nil {
            add(
                ValidationCode.invalidVersionRange,
                "'\(string)' is not a valid version range (expected \">=x.y.z\" or \">=x.y.z <a.b.c\").",
                path: "$.\(key)"
            )
        }
    }

    private mutating func checkBoolean(_ key: String) {
        guard let value = root[key] else { return }
        guard isJSONBoolean(value) else {
            addInvalidType(key, expected: "a boolean", path: "$.\(key)")
            return
        }
    }

    private mutating func checkSource() {
        guard let value = root["source"] else { return }
        guard let string = value as? String else {
            addInvalidType("source", expected: "a string", path: "$.source")
            return
        }
        if !Schema.sources.contains(string) {
            add(
                ValidationCode.invalidType,
                "'\(string)' is not a valid source (expected 'firstParty').",
                path: "$.source"
            )
        }
    }

    // MARK: Enums

    private mutating func checkArtifactKind() {
        guard let value = root["artifactKind"] else { return }
        guard let string = value as? String else {
            addInvalidType("artifactKind", expected: "a string", path: "$.artifactKind")
            return
        }
        if !Schema.artifactKinds.contains(string) {
            add(
                ValidationCode.invalidArtifactKind,
                "'\(string)' is not a valid artifact kind.",
                path: "$.artifactKind"
            )
        }
    }

    private mutating func checkCapabilities() {
        guard let value = root["capabilities"] else { return }
        guard let array = value as? [Any] else {
            addInvalidType("capabilities", expected: "an array of strings", path: "$.capabilities")
            return
        }
        var seen = Set<String>()
        for (index, element) in array.enumerated() {
            let path = "$.capabilities[\(index)]"
            guard let string = element as? String else {
                addInvalidType("capabilities[\(index)]", expected: "a string", path: path)
                continue
            }
            if !Schema.capabilities.contains(string) {
                add(
                    ValidationCode.invalidCapability,
                    "'\(string)' is not a valid capability.",
                    path: path
                )
            } else if !seen.insert(string).inserted {
                add(
                    ValidationCode.duplicateCapability,
                    "Capability '\(string)' is declared more than once.",
                    path: path
                )
            }
        }
    }

    // MARK: Entry points

    private mutating func checkEntryPoints() {
        guard let value = root["entryPoints"] else { return }
        guard let array = value as? [Any] else {
            addInvalidType("entryPoints", expected: "an array of objects", path: "$.entryPoints")
            return
        }

        let artifactKind = root["artifactKind"] as? String
        var seenIDs = Set<String>()

        for (index, element) in array.enumerated() {
            let base = "$.entryPoints[\(index)]"
            guard let entry = element as? [String: Any] else {
                addInvalidType("entryPoints[\(index)]", expected: "an object", path: base)
                continue
            }

            for key in entry.keys where !Schema.entryPointKeys.contains(key) {
                add(
                    ValidationCode.unknownEntryPointKey,
                    "Unknown entry point key '\(key)'.",
                    path: "\(base).\(key)"
                )
            }

            checkEntryPointID(entry, base: base, seenIDs: &seenIDs)
            checkEntryPointKind(entry, base: base)
            checkEntryPointSceneName(entry, base: base, artifactKind: artifactKind)
            checkEntryPointMetadata(entry, base: base)
        }
    }

    private mutating func checkEntryPointID(
        _ entry: [String: Any],
        base: String,
        seenIDs: inout Set<String>
    ) {
        guard let value = entry["id"] else {
            add(
                ValidationCode.missingRequiredField,
                "Missing required field 'id'.",
                path: "\(base).id"
            )
            return
        }
        guard let string = value as? String else {
            addInvalidType("entryPoints.id", expected: "a string", path: "\(base).id")
            return
        }
        if string.isEmpty {
            add(
                ValidationCode.emptyString,
                "Entry point 'id' must not be empty.",
                path: "\(base).id"
            )
            return
        }
        if !seenIDs.insert(string).inserted {
            add(
                ValidationCode.duplicateEntryPointID,
                "Duplicate entry point id '\(string)'.",
                path: "\(base).id"
            )
        }
    }

    private mutating func checkEntryPointKind(_ entry: [String: Any], base: String) {
        guard let value = entry["kind"] else {
            add(
                ValidationCode.missingRequiredField,
                "Missing required field 'kind'.",
                path: "\(base).kind"
            )
            return
        }
        guard let string = value as? String else {
            addInvalidType("entryPoints.kind", expected: "a string", path: "\(base).kind")
            return
        }
        if !Schema.capabilities.contains(string) {
            add(
                ValidationCode.invalidEntryPointKind,
                "'\(string)' is not a valid entry point kind.",
                path: "\(base).kind"
            )
        }
    }

    private mutating func checkEntryPointSceneName(
        _ entry: [String: Any],
        base: String,
        artifactKind: String?
    ) {
        guard let value = entry["sceneName"] else { return }
        guard value is String else {
            addInvalidType("entryPoints.sceneName", expected: "a string", path: "\(base).sceneName")
            return
        }
        if artifactKind == "compiled-in" {
            add(
                ValidationCode.sceneNameNotAllowed,
                "'sceneName' must be absent for compiled-in extensions.",
                path: "\(base).sceneName"
            )
        }
    }

    private mutating func checkEntryPointMetadata(_ entry: [String: Any], base: String) {
        guard let value = entry["metadata"] else { return }
        guard let dictionary = value as? [String: Any] else {
            add(
                ValidationCode.invalidEntryPointMetadata,
                "Entry point 'metadata' must be a string-to-string object.",
                path: "\(base).metadata"
            )
            return
        }
        for (key, element) in dictionary where !(element is String) {
            add(
                ValidationCode.invalidEntryPointMetadata,
                "Entry point metadata value for '\(key)' must be a string.",
                path: "\(base).metadata.\(key)"
            )
        }
    }

    // MARK: Helpers

    private mutating func add(
        _ code: String,
        _ message: String,
        path: String?
    ) {
        issues.append(
            ManifestValidator.issue(code, message, path: path)
        )
    }

    private mutating func addInvalidType(_ field: String, expected: String, path: String) {
        add(
            ValidationCode.invalidType,
            "Field '\(field)' must be \(expected).",
            path: path
        )
    }

    private func isJSONBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
