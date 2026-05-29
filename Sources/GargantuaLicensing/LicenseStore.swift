import Foundation

public enum LicenseStoreError: Error, Sendable, Equatable {
    case fileIOFailed(String)
}

/// Persists the Polar license activation locally and brokers activate /
/// revalidate / deactivate against `PolarLicenseValidating`. Reads are sync
/// (cache on disk) so the license gate never blocks on the network; the
/// `validate` round-trip happens in the background to extend the offline
/// grace window and catch revocations.
public final class LicenseStore: @unchecked Sendable {
    private let fileURL: URL
    private let client: any PolarLicenseValidating
    private let graceInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let deviceLabel: @Sendable () -> String
    private let lock = NSLock()

    public convenience init() {
        self.init(
            fileURL: LicenseStore.defaultFileURL,
            client: PolarLicenseClient()
        )
    }

    public init(
        fileURL: URL,
        client: any PolarLicenseValidating,
        graceInterval: TimeInterval = LicensePolarConfig.validationGraceInterval,
        now: @escaping @Sendable () -> Date = { Date() },
        deviceLabel: @escaping @Sendable () -> String = { LicenseStore.defaultDeviceLabel() }
    ) {
        self.fileURL = fileURL
        self.client = client
        self.graceInterval = graceInterval
        self.now = now
        self.deviceLabel = deviceLabel
    }

    public static var defaultFileURL: URL {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Gargantua", isDirectory: true)
        return supportDir.appendingPathComponent("license.json", isDirectory: false)
    }

    public static func defaultDeviceLabel() -> String {
        Host.current().localizedName ?? "Mac"
    }

    // MARK: - Cache reads (sync)

    public func loadCachedReceipt() -> LicenseReceipt? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LicenseReceipt.self, from: data)
    }

    /// A cached receipt is currently valid if it's `granted` and the last
    /// server validation is within the grace window.
    public func isCurrentlyValid(_ receipt: LicenseReceipt, at reference: Date? = nil) -> Bool {
        guard receipt.status == .granted else { return false }
        let ref = reference ?? now()
        return ref.timeIntervalSince(receipt.lastValidated) < graceInterval
    }

    // MARK: - Network operations

    @discardableResult
    public func activate(key rawKey: String) async throws -> LicenseReceipt {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let activation = try await client.activate(
            key: key,
            label: deviceLabel(),
            meta: Self.defaultMeta()
        )
        let stamp = now()
        let receipt = LicenseReceipt(
            key: key,
            activationId: activation.activationId,
            email: activation.email,
            name: activation.name,
            status: activation.status,
            activatedAt: stamp,
            lastValidated: stamp
        )
        try save(receipt)
        return receipt
    }

    /// Re-checks the cached license against the server. On `granted`, refreshes
    /// the validation timestamp (extending offline grace). On revoked/disabled
    /// or 404 (key gone, stale activation), clears the cache. Network errors
    /// propagate without touching the cache so offline grace still applies.
    @discardableResult
    public func revalidate() async throws -> LicenseReceipt? {
        guard let cached = loadCachedReceipt() else { return nil }
        do {
            let result = try await client.validate(key: cached.key, activationId: cached.activationId)
            if result.status == .granted {
                let updated = cached.revalidated(
                    status: .granted,
                    email: result.email,
                    name: result.name,
                    at: now()
                )
                try save(updated)
                return updated
            }
            try clear()
            return nil
        } catch PolarLicenseError.notFound {
            try clear()
            return nil
        }
    }

    public func deactivate() async throws {
        if let cached = loadCachedReceipt() {
            // Best-effort: free the server slot. Even if the network call
            // fails, drop the local cache so the Mac stops claiming a license.
            try? await client.deactivate(key: cached.key, activationId: cached.activationId)
        }
        try clear()
    }

    // MARK: - Persistence

    public func save(_ receipt: LicenseReceipt) throws {
        lock.lock()
        defer { lock.unlock() }
        let parent = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(receipt)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw LicenseStoreError.fileIOFailed(error.localizedDescription)
        }
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw LicenseStoreError.fileIOFailed(error.localizedDescription)
        }
    }

    private static func defaultMeta() -> [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return [
            "app_version": version,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
    }
}
