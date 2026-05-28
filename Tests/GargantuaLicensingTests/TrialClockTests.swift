import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("TrialClock")
struct TrialClockTests {
    @Test("Fresh storage seeds firstLaunchDate on first read")
    func freshStorageSeedsDate() {
        let storage = InMemoryTrialClockStorage()
        let frozen = Date(timeIntervalSince1970: 1_750_000_000)
        let clock = TrialClock(storage: storage, now: { frozen })

        let firstLaunch = clock.firstLaunchDate()

        #expect(firstLaunch == frozen)
        #expect(storage.readFirstLaunchDate() == frozen)
    }

    @Test("daysRemaining returns full window on day zero")
    func dayZeroReturnsFullWindow() {
        let frozen = Date(timeIntervalSince1970: 1_750_000_000)
        let storage = InMemoryTrialClockStorage(initialDate: frozen)
        let clock = TrialClock(storage: storage, now: { frozen })

        #expect(clock.daysRemaining() == 14)
    }

    @Test("daysRemaining shrinks as time advances")
    func daysRemainingShrinks() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let storage = InMemoryTrialClockStorage(initialDate: start)
        let day7 = start.addingTimeInterval(7 * 24 * 60 * 60)
        let clock = TrialClock(storage: storage, now: { day7 })

        #expect(clock.daysRemaining() == 7)
    }

    @Test("daysRemaining is zero exactly at the boundary")
    func boundaryReturnsZero() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let storage = InMemoryTrialClockStorage(initialDate: start)
        let boundary = start.addingTimeInterval(14 * 24 * 60 * 60)
        let clock = TrialClock(storage: storage, now: { boundary })

        #expect(clock.daysRemaining() == 0)
        #expect(clock.isExpired())
    }

    @Test("daysRemaining stays at zero past expiry")
    func postExpiryStaysZero() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let storage = InMemoryTrialClockStorage(initialDate: start)
        let day30 = start.addingTimeInterval(30 * 24 * 60 * 60)
        let clock = TrialClock(storage: storage, now: { day30 })

        #expect(clock.daysRemaining() == 0)
        #expect(clock.isExpired())
    }
}
