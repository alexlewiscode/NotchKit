import ExtensionFoundation

func availabilityCheck(_ identity: AppExtensionIdentity) -> AppExtensionProcess.Configuration {
    AppExtensionProcess.Configuration(appExtensionIdentity: identity, onInterruption: {})
}