import Darwin
import Foundation
import NotchExtensionToolSupport

let runner = ExtensionToolRunner(
    output: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
    errorOutput: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
)
let status = runner.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    currentDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
)
exit(status)
