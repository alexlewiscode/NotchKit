//
//  ExtValidateOptions.swift
//  ValidationCore
//
//  Testable command-line parsing for `ext-validate`.
//
//  Extracted from the executable so default/override version behaviour can be
//  unit-tested. The SDK default follows the shared current SDK value rather than
//  a second hard-coded literal.
//

import Foundation
import NotchExtensionSDK

/// Parsed `ext-validate` options.
public struct ExtValidateOptions: Equatable {
    public var manifestPaths: [String]
    public var hostVersion: ExtensionVersion
    public var sdkVersion: ExtensionAPIVersion

    public init(
        manifestPaths: [String],
        hostVersion: ExtensionVersion,
        sdkVersion: ExtensionAPIVersion
    ) {
        self.manifestPaths = manifestPaths
        self.hostVersion = hostVersion
        self.sdkVersion = sdkVersion
    }
}

/// Parse failures. `helpRequested` is not an error condition for the caller.
public enum ExtValidateOptionsError: Error, Equatable, CustomStringConvertible {
    case helpRequested
    case missingValue(option: String)
    case invalidVersion(option: String)
    case unknownOption(String)
    case noManifests

    public var description: String {
        switch self {
        case .helpRequested:
            return "help requested"
        case .missingValue(let option):
            return "\(option) requires a major.minor.patch value"
        case .invalidVersion(let option):
            return "\(option) requires a major.minor.patch value"
        case .unknownOption(let option):
            return "unknown option '\(option)'"
        case .noManifests:
            return "no manifest paths provided"
        }
    }
}

/// The `ext-validate` argument parser.
public enum ExtValidateOptionsParser {
    /// Default host application version.
    public static let defaultHostVersion = ExtensionVersion(major: 1, minor: 0, patch: 0)

    /// Default SDK/API version: the shared current SDK value, so this CLI can
    /// never drift from the SDK constant.
    public static var defaultSDKVersion: ExtensionAPIVersion { .current }

    /// Parses arguments (excluding the executable name).
    public static func parse(_ arguments: [String]) throws -> ExtValidateOptions {
        var manifestPaths: [String] = []
        var hostVersion = defaultHostVersion
        var sdkVersion = defaultSDKVersion

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--host-version":
                index += 1
                guard index < arguments.count else {
                    throw ExtValidateOptionsError.missingValue(option: "--host-version")
                }
                guard let parsed = ExtensionVersion(arguments[index]) else {
                    throw ExtValidateOptionsError.invalidVersion(option: "--host-version")
                }
                hostVersion = parsed
            case "--sdk-version":
                index += 1
                guard index < arguments.count else {
                    throw ExtValidateOptionsError.missingValue(option: "--sdk-version")
                }
                guard let parsed = ExtensionVersion(arguments[index]) else {
                    throw ExtValidateOptionsError.invalidVersion(option: "--sdk-version")
                }
                sdkVersion = ExtensionAPIVersion(
                    major: parsed.major, minor: parsed.minor, patch: parsed.patch
                )
            case "-h", "--help":
                throw ExtValidateOptionsError.helpRequested
            default:
                if argument.hasPrefix("-") {
                    throw ExtValidateOptionsError.unknownOption(argument)
                }
                manifestPaths.append(argument)
            }
            index += 1
        }

        guard !manifestPaths.isEmpty else {
            throw ExtValidateOptionsError.noManifests
        }

        return ExtValidateOptions(
            manifestPaths: manifestPaths,
            hostVersion: hostVersion,
            sdkVersion: sdkVersion
        )
    }
}
