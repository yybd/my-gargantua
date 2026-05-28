import CryptoKit
import Foundation

public enum LicenseSigningKeys {
    /// Development public key used to verify receipts during Phase 2.
    /// Phase 4 replaces this with the FastSpring production public key
    /// once the storefront account is provisioned. The matching private key
    /// stays inside FastSpring (production) or the test bundle (Phase 2 dev).
    public static let developmentPublicKeyDER: Data = Data(base64Encoded:
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEQaqNmHorPzc2ZU9sdkiVrdsJyGsyydr0vQOyKgBnuPp+tZmyivmjV89OAb8I3qFv0tGdvmnXX9Vrrysdnssivw=="
    )!

    public static var developmentPublicKey: P256.Signing.PublicKey {
        // swiftlint:disable:next force_try
        try! P256.Signing.PublicKey(derRepresentation: developmentPublicKeyDER)
    }
}
