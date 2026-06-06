import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GargantuaCore

extension CzkawkaAdapterTests {

    /// Returns a fixed verdict regardless of path — lets the adapter tests
    /// exercise each branch without depending on real image bytes.
    struct StubVerifier: BrokenFileVerifier {
        let verdict: BrokenFileVerdict
        func verify(path: String) -> BrokenFileVerdict { verdict }
    }

    /// Write a real, decodable JPEG to `url` so ImageIO content-sniffs it as
    /// `public.jpeg` regardless of the path's extension.
    static func writeJPEG(to url: URL) throws {
        let width = 2, height = 2
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0x80, count: bytesPerRow * height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func brokenFinding(path: String) -> String {
        "Found 1 broken files.\n\(path)"
    }

    // MARK: - Adapter wiring (stubbed verdicts)

    @Test("valid image whose extension matches is dropped (czkawka false positive)")
    func brokenValidMatchingExtensionDropped() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CzkawkaBroken-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("logo.png")
        try Data(repeating: 1, count: 256).write(to: file)

        let adapter = CzkawkaAdapter(
            binary: URL(fileURLWithPath: "/bin/czkawka"),
            categories: [.brokenFiles],
            scanRoots: [dir],
            runner: StubRunner(outputs: [
                "broken": ProcessOutput(
                    stdout: brokenFinding(path: file.path), stderr: "", exitCode: 0
                ),
            ]),
            brokenFileVerifier: StubVerifier(verdict: .validMatchingExtension)
        )

        let results = try await adapter.scan(progress: nil)
        #expect(results.isEmpty)
    }

    @Test("valid image with wrong extension is relabeled, protected, not corrupt")
    func brokenValidWrongExtensionRelabeled() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CzkawkaBroken-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("logo.png")
        try Data(repeating: 1, count: 256).write(to: file)

        let adapter = CzkawkaAdapter(
            binary: URL(fileURLWithPath: "/bin/czkawka"),
            categories: [.brokenFiles],
            scanRoots: [dir],
            runner: StubRunner(outputs: [
                "broken": ProcessOutput(
                    stdout: brokenFinding(path: file.path), stderr: "", exitCode: 0
                ),
            ]),
            brokenFileVerifier: StubVerifier(
                verdict: .validWrongExtension(actualFormatName: "JPEG image", actualExtension: "jpeg")
            )
        )

        let results = try await adapter.scan(progress: nil)
        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.safety == .protected_)
        #expect(result.tags == ["extension_mismatch"])
        #expect(result.explanation.contains("not corrupt"))
        #expect(result.explanation.contains(".jpeg"))
        #expect(result.category == "broken_files")
    }

    @Test("undecodable file keeps czkawka's corrupt verdict")
    func brokenUnverifiedKeptAsCorrupt() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CzkawkaBroken-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("truncated.png")
        try Data(repeating: 1, count: 256).write(to: file)

        let adapter = CzkawkaAdapter(
            binary: URL(fileURLWithPath: "/bin/czkawka"),
            categories: [.brokenFiles],
            scanRoots: [dir],
            runner: StubRunner(outputs: [
                "broken": ProcessOutput(
                    stdout: brokenFinding(path: file.path), stderr: "", exitCode: 0
                ),
            ]),
            brokenFileVerifier: StubVerifier(verdict: .unverified)
        )

        let results = try await adapter.scan(progress: nil)
        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.safety == .review)
        #expect(result.explanation == "File appears corrupt. Verify before removing.")
    }

    // MARK: - ImageIOBrokenFileVerifier (real bytes)

    @Test("ImageIO verifier flags a JPEG saved as .png as a wrong-extension match")
    func imageIOWrongExtension() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageIOVerify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("misnamed.png")
        try Self.writeJPEG(to: file)

        let verdict = ImageIOBrokenFileVerifier().verify(path: file.path)
        guard case let .validWrongExtension(_, actualExtension) = verdict else {
            Issue.record("expected .validWrongExtension, got \(verdict)")
            return
        }
        #expect(actualExtension == "jpeg")
    }

    @Test("ImageIO verifier accepts a JPEG saved as .jpg as a matching extension")
    func imageIOMatchingExtension() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageIOVerify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("named.jpg")
        try Self.writeJPEG(to: file)

        #expect(ImageIOBrokenFileVerifier().verify(path: file.path) == .validMatchingExtension)
    }

    @Test("ImageIO verifier leaves genuinely undecodable data unverified")
    func imageIOUndecodable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageIOVerify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("garbage.png")
        try Data(repeating: 0xAB, count: 512).write(to: file)

        #expect(ImageIOBrokenFileVerifier().verify(path: file.path) == .unverified)
    }
}
