import CryptoKit
import Foundation

public enum LicenseStoreError: Error, Sendable, Equatable {
    case invalidSignature
    case malformedReceipt
    case fileIOFailed(String)
}

public final class LicenseStore: @unchecked Sendable {
    private let fileURL: URL
    private let publicKey: P256.Signing.PublicKey
    private let fileManager: FileManager
    private let lock = NSLock()

    public convenience init() {
        self.init(
            fileURL: LicenseStore.defaultFileURL,
            publicKey: LicenseSigningKeys.productionPublicKey
        )
    }

    public init(
        fileURL: URL,
        publicKey: P256.Signing.PublicKey,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.publicKey = publicKey
        self.fileManager = fileManager
    }

    public static var defaultFileURL: URL {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Gargantua", isDirectory: true)
        return supportDir.appendingPathComponent("license.dat", isDirectory: false)
    }

    public func loadValidReceipt() -> LicenseReceipt? {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let receipt = try? JSONDecoder().decode(LicenseReceipt.self, from: data) else { return nil }
        guard verify(receipt) else { return nil }
        return receipt
    }

    @discardableResult
    public func save(_ receipt: LicenseReceipt) throws -> LicenseReceipt {
        guard verify(receipt) else { throw LicenseStoreError.invalidSignature }
        lock.lock()
        defer { lock.unlock() }
        let parent = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(receipt)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw LicenseStoreError.fileIOFailed(error.localizedDescription)
        }
        return receipt
    }

    /// Activate from the customer-facing key string emailed by FastSpring.
    /// Phase 3 expects callers to invoke `await LicenseStateModel.shared.refresh()`
    /// after this returns so observers re-render.
    @discardableResult
    public func activate(keyString: String) throws -> LicenseReceipt {
        let receipt = try LicenseKeyCodec.decode(keyString)
        return try save(receipt)
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw LicenseStoreError.fileIOFailed(error.localizedDescription)
        }
    }

    public func verify(_ receipt: LicenseReceipt) -> Bool {
        guard let signature = Data(base64Encoded: receipt.signatureBase64) else { return false }
        let ecdsaSignature: P256.Signing.ECDSASignature
        do {
            ecdsaSignature = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        } catch {
            return false
        }
        return publicKey.isValidSignature(ecdsaSignature, for: receipt.canonicalMessage())
    }
}
