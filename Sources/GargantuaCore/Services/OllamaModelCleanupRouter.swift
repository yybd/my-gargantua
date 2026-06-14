import Foundation

/// Deletes a named Ollama model. Implementations talk to Ollama itself — never
/// the filesystem — because blobs are shared and only Ollama can garbage-collect
/// the unreferenced ones safely.
public protocol OllamaModelDeleting: Sendable {
    func delete(reference: String) async throws
}

public enum OllamaModelDeleteError: Error, LocalizedError, Equatable {
    case notTagged
    case unreachable(detail: String)
    case rejected(detail: String)

    public var errorDescription: String? {
        switch self {
        case .notTagged:
            return "Internal: scan item is not tagged as an Ollama model."
        case .unreachable(let detail):
            return "Ollama is not reachable. Start the Ollama app and try again. (\(detail))"
        case .rejected(let detail):
            return "Ollama refused to delete the model: \(detail)"
        }
    }
}

/// Default deleter: `DELETE /api/delete` against the running daemon, falling
/// back to the `ollama rm` CLI when the HTTP endpoint can't be reached.
public struct OllamaModelDeleter: OllamaModelDeleting {
    private let session: URLSession
    private let environment: [String: String]

    public init(
        session: URLSession = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.session = session
        self.environment = environment
    }

    public func delete(reference: String) async throws {
        do {
            try await deleteViaAPI(reference: reference)
        } catch let error as OllamaModelDeleteError {
            // A daemon that answered and rejected the request is authoritative —
            // don't paper over it with the CLI (which talks to the same daemon).
            if case .rejected = error { throw error }
            try deleteViaCLI(reference: reference, apiDetail: error.localizedDescription)
        }
    }

    private func host() -> String {
        let raw = environment["OLLAMA_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var value = raw, !value.isEmpty else { return "http://127.0.0.1:11434" }
        if !value.contains("://") { value = "http://\(value)" }
        return value
    }

    private func deleteViaAPI(reference: String) async throws {
        guard let url = URL(string: "\(host())/api/delete") else {
            throw OllamaModelDeleteError.unreachable(detail: "bad host")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": reference])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OllamaModelDeleteError.unreachable(detail: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OllamaModelDeleteError.unreachable(detail: "no HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw OllamaModelDeleteError.rejected(detail: body.isEmpty ? "HTTP \(http.statusCode)" : body)
        }
    }

    private func deleteViaCLI(reference: String, apiDetail: String) throws {
        guard let binary = Self.resolveOllamaBinary() else {
            throw OllamaModelDeleteError.unreachable(detail: apiDetail)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rm", reference]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw OllamaModelDeleteError.unreachable(detail: error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(process.terminationStatus)"
            throw OllamaModelDeleteError.rejected(detail: detail.isEmpty ? "exit \(process.terminationStatus)" : detail)
        }
    }

    private static func resolveOllamaBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Bridge between `CleanupEngine` and an `OllamaModelDeleting`. Recovers the
/// model reference from the scan-result id and translates the deletion outcome
/// back into the engine's per-item result shape.
public struct OllamaModelCleanupRouter: Sendable {
    /// Disabled router that fails closed — used by tests that don't exercise the
    /// Ollama path so they don't have to stand up a fake daemon.
    public static let disabled = OllamaModelCleanupRouter(deleter: DisabledDeleter())

    private let deleter: any OllamaModelDeleting

    public init(deleter: any OllamaModelDeleting = OllamaModelDeleter()) {
        self.deleter = deleter
    }

    public static func production() -> OllamaModelCleanupRouter {
        OllamaModelCleanupRouter()
    }

    public func run(item: ScanResult) async -> CleanupItemResult {
        guard let reference = item.ollamaModelReference else {
            return CleanupItemResult(
                item: item,
                succeeded: false,
                error: OllamaModelDeleteError.notTagged.localizedDescription
            )
        }
        do {
            try await deleter.delete(reference: reference)
            return CleanupItemResult(item: item, succeeded: true)
        } catch {
            return CleanupItemResult(
                item: item,
                succeeded: false,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}

private struct DisabledDeleter: OllamaModelDeleting {
    func delete(reference: String) async throws {
        throw OllamaModelDeleteError.unreachable(detail: "Ollama cleanup is disabled in this context.")
    }
}
