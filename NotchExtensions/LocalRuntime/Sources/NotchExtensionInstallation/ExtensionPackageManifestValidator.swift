import CoreFoundation
import Foundation
import NotchExtensionSDK

public enum StrictExtensionPackageManifestError: Error, Equatable {
    case invalidJSON
    case invalidStructure(String)
    case decodeFailed
}

/// Strict schema-v2 validation layered over the SDK's permissive Codable model.
public struct StrictExtensionPackageManifestValidator: Sendable {
    public init() {}

    public func decodeAndValidate(data: Data) throws -> ExtensionPackageManifest {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StrictExtensionPackageManifestError.invalidJSON
        }
        try object(root, at: "$", allowed: ["schemaVersion", "metadata", "artifact", "permissions", "hostActions", "entryPoints"], required: ["schemaVersion", "metadata", "artifact", "permissions", "hostActions", "entryPoints"])
        try integer(root["schemaVersion"], at: "$.schemaVersion")
        try metadata(root["metadata"], at: "$.metadata")
        try artifact(root["artifact"], at: "$.artifact")
        try permissions(root["permissions"], at: "$.permissions")
        try stringArray(root["hostActions"], at: "$.hostActions")
        guard let entries = root["entryPoints"] as? [Any] else { throw structure("$.entryPoints") }
        for (index, entry) in entries.enumerated() {
            guard let value = entry as? [String: Any] else { throw structure("$.entryPoints[\(index)]") }
            let path = "$.entryPoints[\(index)]"
            try object(value, at: path, allowed: ["entryPoint", "presentationMode", "sceneName"], required: ["entryPoint", "presentationMode"])
            try entryPoint(value["entryPoint"], at: "\(path).entryPoint")
            try string(value["presentationMode"], at: "\(path).presentationMode")
            if let scene = value["sceneName"] { try string(scene, at: "\(path).sceneName") }
        }

        let manifest: ExtensionPackageManifest
        do { manifest = try JSONDecoder().decode(ExtensionPackageManifest.self, from: data) }
        catch { throw StrictExtensionPackageManifestError.decodeFailed }
        try NotchExtensionSDK.ExtensionPackageManifestValidator.validate(manifest)
        return manifest
    }

    private func metadata(_ value: Any?, at path: String) throws {
        guard let value = value as? [String: Any] else { throw structure(path) }
        let required: Set<String> = ["id", "displayName", "iconSystemName", "extensionVersion", "apiVersion", "supportedHostVersions", "supportedSDKVersions", "capabilities", "artifactKind", "entryPoints", "defaultEnabled", "source"]
        try object(value, at: path, allowed: required.union(["summary"]), required: required)
        for key in ["id", "displayName", "iconSystemName", "extensionVersion", "apiVersion", "supportedHostVersions", "supportedSDKVersions", "artifactKind", "source"] {
            try string(value[key], at: "\(path).\(key)")
        }
        if let summary = value["summary"] { try string(summary, at: "\(path).summary") }
        try stringArray(value["capabilities"], at: "\(path).capabilities")
        try boolean(value["defaultEnabled"], at: "\(path).defaultEnabled")
        guard let entries = value["entryPoints"] as? [Any] else { throw structure("\(path).entryPoints") }
        for (index, entry) in entries.enumerated() {
            try entryPoint(entry, at: "\(path).entryPoints[\(index)]")
        }
    }

    private func artifact(_ value: Any?, at path: String) throws {
        guard let value = value as? [String: Any] else { throw structure(path) }
        try object(value, at: path, allowed: ["kind", "appExtension"], required: ["kind", "appExtension"])
        try string(value["kind"], at: "\(path).kind")
        guard let app = value["appExtension"] as? [String: Any] else { throw structure("\(path).appExtension") }
        let appPath = "\(path).appExtension"
        try object(app, at: appPath, allowed: ["providerBundleIdentifier", "extensionBundleIdentifier", "extensionPointIdentifier", "minimumMacOSVersion", "protocolVersions", "architectures"], required: ["providerBundleIdentifier", "extensionBundleIdentifier", "extensionPointIdentifier", "minimumMacOSVersion", "protocolVersions", "architectures"])
        for key in ["providerBundleIdentifier", "extensionBundleIdentifier", "extensionPointIdentifier", "minimumMacOSVersion"] {
            try string(app[key], at: "\(appPath).\(key)")
        }
        try stringArray(app["architectures"], at: "\(appPath).architectures")
        guard let versions = app["protocolVersions"] as? [String: Any] else { throw structure("\(appPath).protocolVersions") }
        try object(versions, at: "\(appPath).protocolVersions", allowed: ["minimum", "maximum"], required: ["minimum", "maximum"])
        try integer(versions["minimum"], at: "\(appPath).protocolVersions.minimum")
        try integer(versions["maximum"], at: "\(appPath).protocolVersions.maximum")
    }

    private func entryPoint(_ value: Any?, at path: String) throws {
        guard let value = value as? [String: Any] else { throw structure(path) }
        try object(value, at: path, allowed: ["id", "kind", "sceneName", "metadata"], required: ["id", "kind"])
        try string(value["id"], at: "\(path).id")
        try string(value["kind"], at: "\(path).kind")
        if let scene = value["sceneName"] { try string(scene, at: "\(path).sceneName") }
        if let metadata = value["metadata"] {
            guard let metadata = metadata as? [String: Any], metadata.values.allSatisfy({ $0 is String }) else {
                throw structure("\(path).metadata")
            }
        }
    }

    private func permissions(_ value: Any?, at path: String) throws {
        guard let values = value as? [Any] else { throw structure(path) }
        for (index, item) in values.enumerated() {
            guard let permission = item as? [String: Any] else { throw structure("\(path)[\(index)]") }
            let itemPath = "\(path)[\(index)]"
            try object(permission, at: itemPath, allowed: ["kind", "required", "owner", "usageDescriptionKey"], required: ["kind", "required", "owner", "usageDescriptionKey"])
            try string(permission["kind"], at: "\(itemPath).kind")
            try boolean(permission["required"], at: "\(itemPath).required")
            try string(permission["owner"], at: "\(itemPath).owner")
            try string(permission["usageDescriptionKey"], at: "\(itemPath).usageDescriptionKey")
        }
    }

    private func object(_ value: [String: Any], at path: String, allowed: Set<String>, required: Set<String>) throws {
        guard Set(value.keys).isSubset(of: allowed), required.isSubset(of: Set(value.keys)) else { throw structure(path) }
    }

    private func stringArray(_ value: Any?, at path: String) throws {
        guard let values = value as? [Any], values.allSatisfy({ $0 is String }) else { throw structure(path) }
    }

    private func string(_ value: Any?, at path: String) throws {
        guard value is String else { throw structure(path) }
    }

    private func integer(_ value: Any?, at path: String) throws {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded() == number.doubleValue
        else { throw structure(path) }
    }

    private func boolean(_ value: Any?, at path: String) throws {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw structure(path) }
    }

    private func structure(_ path: String) -> StrictExtensionPackageManifestError {
        .invalidStructure(path)
    }
}
