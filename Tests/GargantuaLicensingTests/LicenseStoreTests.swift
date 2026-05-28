import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("LicenseStore")
struct LicenseStoreTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gargantua-licensing-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
    }

    private func makeStore(at url: URL) -> LicenseStore {
        LicenseStore(
            fileURL: url,
            publicKey: LicenseSigningKeys.developmentPublicKey
        )
    }

    @Test("Validly signed receipt round-trips through save → load")
    func roundTripsValidReceipt() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        let receipt = try TestKeys.validReceipt()

        try store.save(receipt)
        let loaded = store.loadValidReceipt()

        #expect(loaded == receipt)
    }

    @Test("Loading from a non-existent file returns nil")
    func missingFileReturnsNil() {
        let store = makeStore(at: tempFileURL())
        #expect(store.loadValidReceipt() == nil)
    }

    @Test("Tampered receipt fails signature verification on load")
    func tamperedReceiptRejected() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        let receipt = try TestKeys.validReceipt(email: "real@example.com")
        try store.save(receipt)

        let tampered = LicenseReceipt(
            email: "attacker@example.com",
            name: receipt.name,
            activatedAt: receipt.activatedAt,
            signatureBase64: receipt.signatureBase64
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(tampered).write(to: url, options: [.atomic])

        #expect(store.loadValidReceipt() == nil)
    }

    @Test("Malformed file returns nil rather than throwing")
    func malformedFileReturnsNil() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json at all".utf8).write(to: url)

        #expect(store.loadValidReceipt() == nil)
    }

    @Test("Saving a receipt with an invalid signature throws")
    func savingInvalidSignatureThrows() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        let bogus = LicenseReceipt(
            email: "x@y.com",
            name: "Z",
            activatedAt: Date(timeIntervalSince1970: 0),
            signatureBase64: Data("fake-signature".utf8).base64EncodedString()
        )

        #expect(throws: LicenseStoreError.invalidSignature) {
            try store.save(bogus)
        }
    }

    @Test("Clear removes the saved receipt file")
    func clearRemovesFile() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        try store.save(try TestKeys.validReceipt())
        #expect(FileManager.default.fileExists(atPath: url.path))

        try store.clear()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.loadValidReceipt() == nil)
    }
}
