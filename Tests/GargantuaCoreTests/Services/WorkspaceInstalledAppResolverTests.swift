import Foundation
import Testing
@testable import GargantuaCore

@Suite("WorkspaceInstalledAppResolver")
struct WorkspaceInstalledAppResolverTests {
    private struct StubRunner: ProcessRunner {
        var stdout: String = ""
        var exitCode: Int32 = 0
        func run(executable _: URL, arguments _: [String]) throws -> ProcessOutput {
            ProcessOutput(stdout: stdout, stderr: "", exitCode: exitCode)
        }
    }

    private final class AppRootFixture {
        let root: URL
        private let fm = FileManager.default

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("AppRootFixture-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit { try? fm.removeItem(at: root) }

        func makeApp(_ name: String, bundleID: String?, embeddedHelper: String? = nil) throws {
            let contents = root
                .appendingPathComponent("\(name).app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            if let bundleID {
                let data = try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": bundleID],
                    format: .xml,
                    options: 0
                )
                try data.write(to: contents.appendingPathComponent("Info.plist"))
            }
            if let embeddedHelper {
                let ls = contents.appendingPathComponent("Library/LaunchServices", isDirectory: true)
                try fm.createDirectory(at: ls, withIntermediateDirectories: true)
                fm.createFile(atPath: ls.appendingPathComponent(embeddedHelper).path, contents: Data())
            }
        }
    }

    private func resolver(
        roots: [URL],
        mdfindStdout: String = "",
        workspace: @escaping @Sendable (String) -> Bool = { _ in false }
    ) -> WorkspaceInstalledAppResolver {
        WorkspaceInstalledAppResolver(
            appRoots: roots,
            processRunner: StubRunner(stdout: mdfindStdout),
            workspaceLookup: workspace
        )
    }

    @Test("filesystem Info.plist match counts as installed")
    func filesystemInfoPlistMatch() throws {
        let fixture = try AppRootFixture()
        try fixture.makeApp("Fantastical", bundleID: "com.flexibits.fantastical2.mac")

        let resolver = resolver(roots: [fixture.root])
        #expect(resolver.isInstalled(bundleID: "com.flexibits.fantastical2.mac"))
        #expect(!resolver.isInstalled(bundleID: "com.gone.app"))
    }

    @Test("embedded LaunchServices helper counts as installed")
    func embeddedHelperMatch() throws {
        let fixture = try AppRootFixture()
        try fixture.makeApp("Acrobat", bundleID: "com.adobe.Acrobat", embeddedHelper: "com.adobe.ARMDC.Communicator")

        let resolver = resolver(roots: [fixture.root])
        #expect(resolver.isInstalled(bundleID: "com.adobe.ARMDC.Communicator"))
    }

    @Test("helper-suffixed id resolves through its parent app")
    func helperSuffixParentMatch() throws {
        let fixture = try AppRootFixture()
        try fixture.makeApp("Keep", bundleID: "org.keepassxc.KeePassXC")

        let resolver = resolver(roots: [fixture.root])
        #expect(resolver.isInstalled(bundleID: "org.keepassxc.KeePassXC.helper"))
    }

    @Test("mdfind hit counts as installed even with no app on disk")
    func mdfindMatch() {
        let resolver = resolver(roots: [], mdfindStdout: "/Applications/Whatever.app\n")
        #expect(resolver.isInstalled(bundleID: "com.some.app"))
    }

    @Test("LaunchServices hit short-circuits to installed")
    func workspaceShortCircuit() {
        let resolver = resolver(roots: [], workspace: { _ in true })
        #expect(resolver.isInstalled(bundleID: "com.some.app"))
    }

    @Test("all layers miss means not installed")
    func allMiss() throws {
        let fixture = try AppRootFixture()
        try fixture.makeApp("Other", bundleID: "com.other.app")

        let resolver = resolver(roots: [fixture.root])
        #expect(!resolver.isInstalled(bundleID: "com.truly.gone"))
    }

    @Test("malformed bundle ids are rejected, never declared installed")
    func malformedRejected() {
        #expect(!WorkspaceInstalledAppResolver.isSafeBundleID("com.x y"))
        #expect(!WorkspaceInstalledAppResolver.isSafeBundleID("noseparator"))
        #expect(WorkspaceInstalledAppResolver.isSafeBundleID("com.flexibits.fantastical2.mac"))
    }
}
