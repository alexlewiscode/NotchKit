import Foundation
import NativeExtensionShared

@main
enum NotchExtensionPackageTool {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) throws {
        guard arguments.count == 2, arguments[0] == "validate" else {
            throw ToolError.usage
        }

        let packageURL = URL(filePath: arguments[1], directoryHint: .isDirectory)
        let package = try NativeExtensionPackageValidator.validatePackage(at: packageURL)
        print("VALID id=\(package.manifest.id) version=\(package.manifest.extensionVersion)")
    }
}

private enum ToolError: Error, LocalizedError {
    case usage

    var errorDescription: String? {
        "Usage: notch-extension-package validate <extracted-package-directory>"
    }
}
