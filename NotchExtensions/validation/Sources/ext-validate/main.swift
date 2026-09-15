//
//  main.swift
//  ext-validate
//
//  Command-line entry point for manifest validation. JSON only: no extension
//  code is ever loaded or executed.
//

import Foundation
import NotchExtensionSDK
import ValidationCore

let usage = """
Usage: ext-validate <path-to-manifest.json> [<path> ...] \
[--host-version 1.0.0] [--sdk-version 1.0.0]

Validates one or more NotchKit extension manifests against the canonical
schema and the running host/SDK compatibility rules.

Options:
  --host-version <x.y.z>   Host application version (default 1.0.0).
  --sdk-version <x.y.z>    Extension SDK/API version (default 1.0.0).
  -h, --help               Show this help.

Exit codes:
  0  no errors (warnings may have been printed)
  1  at least one validation error
  2  usage or I/O error
"""

func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func failUsage(_ message: String) -> Never {
    writeStderr("ext-validate: \(message)")
    writeStderr(usage)
    exit(2)
}

var manifestPaths: [String] = []
var hostVersion = ExtensionVersion(major: 1, minor: 0, patch: 0)
var sdkVersion = ExtensionAPIVersion(major: 1, minor: 0, patch: 0)

let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--host-version":
        index += 1
        guard index < arguments.count, let parsed = ExtensionVersion(arguments[index]) else {
            failUsage("--host-version requires a major.minor.patch value")
        }
        hostVersion = parsed
    case "--sdk-version":
        index += 1
        guard index < arguments.count, let parsed = ExtensionVersion(arguments[index]) else {
            failUsage("--sdk-version requires a major.minor.patch value")
        }
        sdkVersion = ExtensionAPIVersion(major: parsed.major, minor: parsed.minor, patch: parsed.patch)
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        if argument.hasPrefix("-") {
            failUsage("unknown option '\(argument)'")
        }
        manifestPaths.append(argument)
    }
    index += 1
}

guard !manifestPaths.isEmpty else {
    failUsage("no manifest paths provided")
}

var hadError = false
var hadIOError = false

for path in manifestPaths {
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        writeStderr("ext-validate: cannot read '\(path)': \(error.localizedDescription)")
        hadIOError = true
        continue
    }

    let issues = ManifestValidator.validate(
        data: data,
        hostVersion: hostVersion,
        sdkVersion: sdkVersion
    )

    for issue in issues {
        if issue.severity == .error {
            hadError = true
        }
        let prefix = issue.severity == .error ? "ERR" : "WARN"
        var line = "\(prefix) \(issue.phase.rawValue) \(issue.code): \(issue.message)"
        if let jsonPath = issue.path {
            line += " [\(jsonPath)]"
        }
        line += " (file: \(path))"
        print(line)
    }
}

if hadIOError {
    exit(2)
}
exit(hadError ? 1 : 0)
