import Foundation
import NotchExtensionSDK

public enum ExtensionToolCommand: Equatable, Sendable {
    case validate(archiveURL: URL)
    case inspect(archiveURL: URL, json: Bool)
    case package(providerURL: URL, outputURL: URL, context: ExtensionPackageValidationContext)
}

public enum ExtensionToolUsageError: Error, Equatable {
    case invalidArguments
}

public enum ExtensionToolCommandParser {
    public static let usage = """
    Usage:
      notchkit-extension validate <archive>
      notchkit-extension inspect <archive> [--json]
      notchkit-extension package <provider.app> --output <file.notchkitextension> [--marketplace]
    """

    public static func parse(_ arguments: [String], currentDirectoryURL: URL) throws -> ExtensionToolCommand {
        func url(_ path: String) -> URL {
            URL(fileURLWithPath: path, relativeTo: currentDirectoryURL).standardizedFileURL
        }

        if arguments.count == 2, arguments[0] == "validate" {
            return .validate(archiveURL: url(arguments[1]))
        }
        if arguments.count == 2, arguments[0] == "inspect" {
            return .inspect(archiveURL: url(arguments[1]), json: false)
        }
        if arguments.count == 3, arguments[0] == "inspect", arguments[2] == "--json" {
            return .inspect(archiveURL: url(arguments[1]), json: true)
        }
        if arguments.count == 4, arguments[0] == "package", arguments[2] == "--output" {
            return .package(providerURL: url(arguments[1]), outputURL: url(arguments[3]), context: .localDeveloper)
        }
        if arguments.count == 5, arguments[0] == "package", arguments[2] == "--output",
           arguments[4] == "--marketplace" {
            return .package(providerURL: url(arguments[1]), outputURL: url(arguments[3]), context: .marketplace)
        }
        throw ExtensionToolUsageError.invalidArguments
    }
}
