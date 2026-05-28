import CryptoKit
import Foundation
@testable import GargantuaLicensing

enum TestKeys {
    static let developmentPrivateKeyRawBase64 = "79PmIv23EfHo4hsyDWomSGAQd2s2QeYK89y7jFZoWZA="

    static var privateKey: P256.Signing.PrivateKey {
        // swiftlint:disable force_unwrapping force_try
        let raw = Data(base64Encoded: developmentPrivateKeyRawBase64)!
        return try! P256.Signing.PrivateKey(rawRepresentation: raw)
        // swiftlint:enable force_unwrapping force_try
    }

    static func sign(_ receipt: LicenseReceipt) throws -> LicenseReceipt {
        let signature = try privateKey.signature(for: receipt.canonicalMessage())
        return LicenseReceipt(
            email: receipt.email,
            name: receipt.name,
            activatedAt: receipt.activatedAt,
            signatureBase64: signature.rawRepresentation.base64EncodedString()
        )
    }

    static func validReceipt(
        email: String = "user@example.com",
        name: String = "Test User",
        activatedAt: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) throws -> LicenseReceipt {
        let unsigned = LicenseReceipt(
            email: email,
            name: name,
            activatedAt: activatedAt,
            signatureBase64: ""
        )
        return try sign(unsigned)
    }
}
