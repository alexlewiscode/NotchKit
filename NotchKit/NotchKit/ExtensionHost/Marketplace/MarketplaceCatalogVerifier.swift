import CryptoKit
import Foundation

enum MarketplaceCatalogVerifier {
    static func verify(
        _ data: Data,
        configuration: MarketplaceCatalogConfiguration,
        now: Date = Date(),
        allowExpired: Bool = false
    ) throws -> MarketplaceCatalogSnapshot {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(MarketplaceCatalogEnvelope.self, from: data)
            guard envelope.keyID == configuration.keyID else {
                throw MarketplaceCatalogError.untrustedKey
            }
            guard let payload = Data(base64Encoded: envelope.payload),
                  let signature = Data(base64Encoded: envelope.signature)
            else { throw MarketplaceCatalogError.invalidEnvelope }

            let publicKey: Curve25519.Signing.PublicKey
            do {
                publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: configuration.publicKey)
            } catch {
                throw MarketplaceCatalogError.untrustedKey
            }
            let domain = Data("NotchKit-Hub-Catalog-v1\0".utf8)
            guard publicKey.isValidSignature(signature, for: domain + payload) else {
                throw MarketplaceCatalogError.invalidSignature
            }

            let snapshot = try decoder.decode(MarketplaceCatalogSnapshot.self, from: payload)
            guard snapshot.apiVersion == "1" else {
                throw MarketplaceCatalogError.unsupportedAPI(snapshot.apiVersion)
            }
            guard allowExpired || snapshot.expiresAt > now else { throw MarketplaceCatalogError.expired }
            try validate(snapshot)
            return snapshot
        } catch let error as MarketplaceCatalogError {
            throw error
        } catch {
            throw MarketplaceCatalogError.invalidEnvelope
        }
    }

    private static func validate(_ snapshot: MarketplaceCatalogSnapshot) throws {
        guard snapshot.generatedAt < snapshot.expiresAt,
              Set(snapshot.entries.map(\.id)).count == snapshot.entries.count
        else { throw MarketplaceCatalogError.invalidCatalog }

        for entry in snapshot.entries {
            let releases = entry.versions.isEmpty ? [entry.latest] : entry.versions
            guard releases.contains(entry.latest),
                  Set(releases.map(\.releaseID)).count == releases.count,
                  Set(releases.map(\.version)).count == releases.count
            else { throw MarketplaceCatalogError.invalidCatalog }
            for release in releases {
                guard release.size > 0,
                      isSHA256(release.sha256),
                      isSHA256(release.manifestSHA256),
                      !release.teamIdentifier.isEmpty,
                      !release.downloadPath.isEmpty,
                      release.compatibility.protocolVersions.minimum > 0,
                      release.compatibility.protocolVersions.maximum
                        >= release.compatibility.protocolVersions.minimum
                else { throw MarketplaceCatalogError.invalidCatalog }
            }
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

enum MarketplaceSignedPayloadVerifier {
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        domain: String,
        configuration: MarketplaceCatalogConfiguration
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(MarketplaceCatalogEnvelope.self, from: data)
        guard envelope.keyID == configuration.keyID else { throw MarketplaceCatalogError.untrustedKey }
        guard let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: configuration.publicKey)
        else { throw MarketplaceCatalogError.invalidEnvelope }
        let message = Data("\(domain)\0".utf8) + payload
        guard key.isValidSignature(signature, for: message) else {
            throw MarketplaceCatalogError.invalidSignature
        }
        return try decoder.decode(type, from: payload)
    }
}
