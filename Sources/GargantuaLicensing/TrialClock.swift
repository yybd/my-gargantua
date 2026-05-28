import Foundation

public protocol TrialClockStorage: Sendable {
    func readFirstLaunchDate() -> Date?
    func writeFirstLaunchDate(_ date: Date)
}

public final class UserDefaultsTrialClockStorage: TrialClockStorage, @unchecked Sendable {
    public static let firstLaunchKey = "com.gargantua.licensing.trial.firstLaunch"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func readFirstLaunchDate() -> Date? {
        defaults.object(forKey: Self.firstLaunchKey) as? Date
    }

    public func writeFirstLaunchDate(_ date: Date) {
        defaults.set(date, forKey: Self.firstLaunchKey)
    }
}

public final class InMemoryTrialClockStorage: TrialClockStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDate: Date?

    public init(initialDate: Date? = nil) {
        self.storedDate = initialDate
    }

    public func readFirstLaunchDate() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return storedDate
    }

    public func writeFirstLaunchDate(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        storedDate = date
    }
}

public final class TrialClock: @unchecked Sendable {
    public static let trialDuration: TimeInterval = 14 * 24 * 60 * 60

    private let storage: any TrialClockStorage
    private let now: @Sendable () -> Date

    public init(
        storage: any TrialClockStorage = UserDefaultsTrialClockStorage(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.now = now
    }

    @discardableResult
    public func firstLaunchDate() -> Date {
        if let existing = storage.readFirstLaunchDate() { return existing }
        let current = now()
        storage.writeFirstLaunchDate(current)
        return current
    }

    public func daysRemaining() -> Int {
        // Seed the launch date first so any clock motion during seeding counts
        // as elapsed time, not as a negative interval that would inflate the
        // ceiling math.
        let launch = firstLaunchDate()
        let elapsed = now().timeIntervalSince(launch)
        let remaining = Self.trialDuration - elapsed
        if remaining <= 0 { return 0 }
        return Int(ceil(remaining / (24 * 60 * 60)))
    }

    public func isExpired() -> Bool {
        daysRemaining() == 0
    }
}
