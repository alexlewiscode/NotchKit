//
//  LegacyIdentityArchiveReader.swift
//  NotchKit
//
//  Synchronously reads the pre-NotchKit app-owned archive from the
//  non-sandboxed XPC helper. Called before the app reads persisted settings so
//  migrated values are visible on first launch.
//

import Foundation

enum LegacyIdentityArchiveReader {
    /// Returns a JSON object `{defaultsPlist, shelfItems}` (base64 values), or
    /// `nil` when the helper is unavailable or cannot read the old container.
    static func read() -> [String: Any]? {
        let connection = NSXPCConnection(serviceName: "com.notchkit.app.XPCHelper")
        connection.remoteObjectInterface = NSXPCInterface(with: NotchKitXPCHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        guard let proxy = connection.remoteObjectProxy as? NotchKitXPCHelperProtocol else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var archive: Data?
        proxy.readLegacyIdentityArchive { data in
            archive = data
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success, let data = archive else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}