import Foundation

public enum LicenseKeyStatus: String, Sendable, Codable, Equatable {
    case granted
    case revoked
    case disabled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LicenseKeyStatus(rawValue: raw) ?? .unknown
    }
}

/// Locally persisted record of a Polar license activation. Cached at
/// `~/Library/Application Support/Gargantua/license.json` after a successful
/// `activate`, refreshed by background `validate` calls. `lastValidated`
/// drives the offline grace window (see `LicensePolarConfig`).
public struct LicenseReceipt: Sendable, Equatable, Codable {
    public let key: String
    public let activationId: String
    public let email: String?
    public let name: String?
    public let status: LicenseKeyStatus
    public let activatedAt: Date
    public let lastValidated: Date

    public init(
        key: String,
        activationId: String,
        email: String?,
        name: String?,
        status: LicenseKeyStatus,
        activatedAt: Date,
        lastValidated: Date
    ) {
        self.key = key
        self.activationId = activationId
        self.email = email
        self.name = name
        self.status = status
        self.activatedAt = activatedAt
        self.lastValidated = lastValidated
    }

    /// Returns a copy with refreshed status / customer info and a new
    /// validation timestamp, preserving identity fields.
    public func revalidated(
        status: LicenseKeyStatus,
        email: String?,
        name: String?,
        at date: Date
    ) -> LicenseReceipt {
        LicenseReceipt(
            key: key,
            activationId: activationId,
            email: email ?? self.email,
            name: name ?? self.name,
            status: status,
            activatedAt: activatedAt,
            lastValidated: date
        )
    }

    public var displayName: String {
        name ?? email ?? "your license"
    }
}
