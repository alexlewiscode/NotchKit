import Foundation

public struct ExtensionToolRunner {
    private let service: ExtensionToolService
    private let output: (String) -> Void
    private let errorOutput: (String) -> Void

    public init(
        service: ExtensionToolService = ExtensionToolService(),
        output: @escaping (String) -> Void,
        errorOutput: @escaping (String) -> Void
    ) {
        self.service = service
        self.output = output
        self.errorOutput = errorOutput
    }

    public func run(arguments: [String], currentDirectoryURL: URL) -> Int32 {
        do {
            let command = try ExtensionToolCommandParser.parse(arguments, currentDirectoryURL: currentDirectoryURL)
            switch command {
            case let .validate(archiveURL):
                try service.validate(archiveURL: archiveURL)
                output("Valid")
            case let .inspect(archiveURL, json):
                let inspection = try service.inspect(archiveURL: archiveURL)
                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    output(String(decoding: try encoder.encode(inspection), as: UTF8.self))
                } else {
                    output(inspection.humanReadable())
                }
            case let .package(providerURL, outputURL):
                _ = try service.package(providerURL: providerURL, outputURL: outputURL)
                output(outputURL.path)
            }
            return 0
        } catch is ExtensionToolUsageError {
            errorOutput(ExtensionToolCommandParser.usage)
            return 2
        } catch let error as ExtensionToolError {
            errorOutput(error.localizedDescription)
            switch error {
            case .validation: return 1
            case .io: return 2
            }
        } catch {
            errorOutput(error.localizedDescription)
            return 2
        }
    }
}
