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

let defaultHostVersion = ExtValidateOptionsParser.defaultHostVersion
let defaultSDKVersion = ExtValidateOptionsParser.defaultSDKVersion

let usage = """
Usage: ext-validate <path-to-manifest.json> [<path> ...] \
[--host-version \(defaultHostVersion)] [--sdk-version \(defaultSDKVersion)]

Validates one or more NotchKit extension manifests against the canonical
schema and the running host/SDK compatibility rules.

Options:
  --host-version <x.y.z>   Host application version (default \(defaultHostVersion)).
  --sdk-version <x.y.z>    Extension SDK/API version (default \(defaultSDKVersion)).
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

let options: ExtValidateOptions
do {
    options = try ExtValidateOptionsParser.parse(Array(CommandLine.arguments.dropFirst()))
} catch ExtValidateOptionsError.helpRequested {
    print(usage)
    exit(0)
} catch {
    failUsage("\(error)")
}

var hadError = false
var hadIOError = false

for path in options.manifestPaths {
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
        hostVersion: options.hostVersion,
        sdkVersion: options.sdkVersion
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
