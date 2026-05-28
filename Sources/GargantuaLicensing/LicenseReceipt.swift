import Foundation

public struct LicenseReceipt: Sendable, Equatable, Codable {
    public let email: String
    public let name: String
    public let activatedAt: Date
    public let signatureBase64: String

    public init(email: String, name: String, activatedAt: Date, signatureBase64: String) {
        self.email = email
        self.name = name
        self.activatedAt = activatedAt
        self.signatureBase64 = signatureBase64
    }

    public func canonicalMessage() -> Data {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let activatedAtString = isoFormatter.string(from: activatedAt)
        let canonical = "gargantua-v1|\(email)|\(name)|\(activatedAtString)"
        return Data(canonical.utf8)
    }
}
