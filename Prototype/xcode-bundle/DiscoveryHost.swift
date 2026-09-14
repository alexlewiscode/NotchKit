import Foundation
import ExtensionFoundation

@main
struct DiscoveryHost {
    static func main() async {
        let pointID = ProcessInfo.processInfo.environment["NOTCHKIT_POINT_ID"]
            ?? "com.notchkit.prototype.point"

        // Never hang headless: bound the wait.
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            print("DISCOVERY_TIMEOUT point=\(pointID)")
            exit(3)
        }

        do {
            let identities = try AppExtensionIdentity.matching(appExtensionPointIDs: pointID)
            for await batch in identities {
                print("DISCOVERY_BATCH count=\(batch.count)")
                for id in batch {
                    print("IDENTITY bundle=\(id.bundleIdentifier) name=\(id.localizedName) point=\(id.extensionPointIdentifier)")
                }
                exit(batch.isEmpty ? 4 : 0)
            }
            print("DISCOVERY_STREAM_ENDED point=\(pointID)")
            exit(4)
        } catch {
            print("DISCOVERY_FAIL point=\(pointID) error=\(error)")
            exit(1)
        }
    }
}