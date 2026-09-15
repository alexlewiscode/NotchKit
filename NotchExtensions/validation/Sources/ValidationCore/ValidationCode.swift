//
//  ValidationCode.swift
//  ValidationCore
//
//  Stable issue codes. These are part of the CLI contract and must not change
//  meaning between releases; new codes may be added.
//

import Foundation

/// Stable identifiers for every issue the validator can emit.
public enum ValidationCode {
    // MARK: Structural

    /// The input was not a JSON object at all.
    public static let invalidJSON = "structural.invalid_json"
    /// The strict `ExtensionMetadata` decode failed after structural checks.
    public static let decodeFailed = "structural.decode_failed"
    /// An unexpected top-level key was present.
    public static let unknownKey = "structural.unknown_key"
    /// An unexpected key was present inside an entry point.
    public static let unknownEntryPointKey = "structural.unknown_entry_point_key"
    /// A required field was missing.
    public static let missingRequiredField = "structural.missing_required_field"
    /// A field had the wrong JSON type.
    public static let invalidType = "structural.invalid_type"
    /// A required string field was empty.
    public static let emptyString = "structural.empty_string"
    /// The identity was not a valid reverse-DNS identifier.
    public static let invalidIdentity = "structural.invalid_identity"
    /// A semantic version string was malformed.
    public static let invalidVersion = "structural.invalid_version"
    /// A version range string was malformed.
    public static let invalidVersionRange = "structural.invalid_version_range"
    /// A declared capability was not one of the canonical values.
    public static let invalidCapability = "structural.invalid_capability"
    /// The same capability was declared more than once.
    public static let duplicateCapability = "structural.duplicate_capability"
    /// The artifact kind was not one of the canonical values.
    public static let invalidArtifactKind = "structural.invalid_artifact_kind"
    /// An entry point kind was not one of the canonical values.
    public static let invalidEntryPointKind = "structural.invalid_entry_point_kind"
    /// Two entry points shared an id.
    public static let duplicateEntryPointID = "structural.duplicate_entry_point_id"
    /// `sceneName` was present on a `compiled-in` extension.
    public static let sceneNameNotAllowed = "structural.scene_name_not_allowed"
    /// Entry point `metadata` was not a string-to-string object.
    public static let invalidEntryPointMetadata = "structural.invalid_entry_point_metadata"

    // MARK: Host compatibility

    /// The host does not support this artifact kind.
    public static let unsupportedArtifactKind = "compat.unsupported_artifact_kind"
    /// The running host version is outside the declared range.
    public static let unsupportedHostVersion = "compat.unsupported_host_version"
    /// The running SDK version is outside the declared range.
    public static let unsupportedSDKVersion = "compat.unsupported_sdk_version"
    /// An entry point requires a capability that was not declared.
    public static let undeclaredCapability = "compat.undeclared_capability"
    /// A declared capability has no matching entry point.
    public static let capabilityWithoutEntryPoint = "compat.capability_without_entry_point"
    /// Two entry points shared an id (reported by the SDK).
    public static let duplicateEntryPoint = "compat.duplicate_entry_point"
    /// Compatibility validation failed for an unexpected reason.
    public static let compatibilityFailed = "compat.failed"
}
