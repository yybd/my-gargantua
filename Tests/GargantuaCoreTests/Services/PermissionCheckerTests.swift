import CoreServices
import Foundation
import Testing
@testable import GargantuaCore

@Suite("PermissionChecker")
struct PermissionCheckerTests {

    @Test("hasFullDiskAccess returns a Bool without crashing")
    func hasFullDiskAccessReturnsBool() {
        let result: Bool = PermissionChecker.hasFullDiskAccess
        #expect(result == true || result == false)
    }

    @Test("hasFullDiskAccess is consistent across consecutive reads")
    func hasFullDiskAccessIsConsistent() {
        let first = PermissionChecker.hasFullDiskAccess
        let second = PermissionChecker.hasFullDiskAccess
        #expect(first == second)
    }

    @Test("denied readability probe reports Full Disk Access as unavailable")
    func deniedProbeReportsNoFullDiskAccess() {
        let result = PermissionChecker.hasFullDiskAccess(
            probing: "/private/denied/TCC.db",
            isReadable: { path in
                #expect(path == "/private/denied/TCC.db")
                return false
            }
        )

        #expect(result == false)
    }

    @Test("granted readability probe reports Full Disk Access as available")
    func grantedProbeReportsFullDiskAccess() {
        let result = PermissionChecker.hasFullDiskAccess(
            probing: "/private/granted/TCC.db",
            isReadable: { path in
                #expect(path == "/private/granted/TCC.db")
                return true
            }
        )

        #expect(result == true)
    }

    @Test("noErr maps to granted")
    func noErrMapsToGranted() {
        let result = PermissionChecker.finderAutomationPermission(prompt: true) { _ in noErr }
        #expect(result == .granted)
    }

    @Test("errAEEventNotPermitted maps to denied")
    func notPermittedMapsToDenied() {
        let result = PermissionChecker.finderAutomationPermission(prompt: false) { _ in
            OSStatus(errAEEventNotPermitted)
        }
        #expect(result == .denied)
    }

    @Test("would-require-consent maps to notDetermined")
    func wouldRequireConsentMapsToNotDetermined() {
        let result = PermissionChecker.finderAutomationPermission(prompt: false) { _ in
            OSStatus(errAEEventWouldRequireUserConsent)
        }
        #expect(result == .notDetermined)
    }

    @Test("transient failures (e.g. Finder not running) map to notDetermined")
    func transientFailureMapsToNotDetermined() {
        let result = PermissionChecker.finderAutomationPermission(prompt: true) { _ in
            OSStatus(procNotFound)
        }
        #expect(result == .notDetermined)
    }

    @Test("prompt flag is forwarded to the underlying determination")
    func promptFlagForwarded() {
        var captured: Bool?
        _ = PermissionChecker.finderAutomationPermission(prompt: true) { ask in
            captured = ask
            return noErr
        }
        #expect(captured == true)
    }
}
