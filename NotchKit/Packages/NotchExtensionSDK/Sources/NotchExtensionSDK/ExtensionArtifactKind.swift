//
//  ExtensionArtifactKind.swift
//  NotchExtensionSDK
//
//  Classifies how an extension is delivered and executed.
//

import Foundation

/// How an extension artifact is delivered and executed.
///
/// Phase 1 ships only `.compiledIn`: extensions that are statically linked into
/// the host and run in-process with full trust. The out-of-process cases are
/// reserved so the manifest format does not have to change later, and are
/// rejected at registration until an out-of-process adapter is proven.
public enum ExtensionArtifactKind: String, Codable, CaseIterable, Sendable {
    /// Statically linked Swift code compiled into the host application.
    case compiledIn = "compiled-in"
    /// An Apple app extension bundle hosted via ExtensionFoundation/ExtensionKit.
    /// Reserved; not supported by the host yet.
    case appExtension = "app-extension"
    /// A standalone XPC service that the host launches and connects to.
    /// Reserved; not supported by the host yet.
    case xpcService = "xpc-service"
}
