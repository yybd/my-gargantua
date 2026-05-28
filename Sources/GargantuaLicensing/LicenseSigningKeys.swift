import CryptoKit
import Foundation

public enum LicenseSigningKeys {
    /// Development public key. Used by tests and Phase 2/3 verification
    /// (matching private key lives in `Tests/GargantuaLicensingTests/TestKeys.swift`).
    /// Always remains in source — tests rely on it.
    public static let developmentPublicKeyDER: Data = Data(base64Encoded:
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEQaqNmHorPzc2ZU9sdkiVrdsJyGsyydr0vQOyKgBnuPp+tZmyivmjV89OAb8I3qFv0tGdvmnXX9Vrrysdnssivw=="
    )!

    // ──────────────────────────────────────────────────────────────────
    //  PHASE 4 SWAP — FastSpring production public key
    //
    //  When FastSpring generates the CocoaFob keypair in their dashboard
    //  (see docs/fastspring/README.md → "Configure product"), paste the
    //  base64-DER public key into the string below, replacing the fallback.
    //
    //  Until then `productionPublicKeyDER` falls back to the dev key, so
    //  the source-build path keeps working end-to-end with test keys.
    //
    //  After paste, replace the entire body of `productionPublicKeyDER`
    //  with:
    //      Data(base64Encoded: "<PASTE_FASTSPRING_PUBLIC_KEY_HERE>")!
    //
    //  Do NOT delete `developmentPublicKeyDER` — tests sign with the
    //  matching dev private key and verify against the dev public key.
    // ──────────────────────────────────────────────────────────────────
    public static let productionPublicKeyDER: Data = developmentPublicKeyDER

    public static var developmentPublicKey: P256.Signing.PublicKey {
        // swiftlint:disable:next force_try
        try! P256.Signing.PublicKey(derRepresentation: developmentPublicKeyDER)
    }

    /// Public key used by the default `LicenseStore()` initializer. Resolves to
    /// the FastSpring production key once Phase 4 ships; falls back to the dev
    /// key until then so the activation flow stays exercisable end-to-end.
    public static var productionPublicKey: P256.Signing.PublicKey {
        // swiftlint:disable:next force_try
        try! P256.Signing.PublicKey(derRepresentation: productionPublicKeyDER)
    }
}
