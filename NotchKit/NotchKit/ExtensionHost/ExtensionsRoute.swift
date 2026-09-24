import NotchExtensionSDK

enum ExtensionsRoute: Hashable {
    case builtIn(ExtensionSettingsRoute)
    case installed(ExtensionIdentity)
}

enum ExtensionsSearch {
    static func matches(query: String, fields: [String?]) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return fields.compactMap { $0 }.contains {
            $0.localizedCaseInsensitiveContains(normalized)
        }
    }
}
