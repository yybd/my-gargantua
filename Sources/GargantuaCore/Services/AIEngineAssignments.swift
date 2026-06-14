import Foundation

/// Persistence for "which engine does each job". Most use cases store an
/// `AIEngineID` under their own key, but two bridge to pre-existing prefs so
/// the rest of the app keeps working unchanged:
///
/// - `.organize` reads/writes `OrganizerBackendPreference` (what the File
///   Organizer already consults), mapping `.template` ⇄ `.local`.
/// - `.inlineExplain`, when set to a local engine, also mirrors
///   `AIEnginePreference` so `LocalAIService` (and the other local-AI features —
///   narrate, scan filter, cluster suggest) run the chosen Template/MLX engine.
public enum AIEngineAssignments {
    private static func key(for useCase: AIUseCase) -> String {
        "ai.assignment.\(useCase.rawValue)"
    }

    public static func engine(for useCase: AIUseCase, in defaults: UserDefaults = .standard) -> AIEngineID {
        switch useCase {
        case .organize:
            return engineID(from: OrganizerBackendPreference.stored(in: defaults))
        default:
            guard let raw = defaults.string(forKey: key(for: useCase)),
                  let id = AIEngineID(rawValue: raw),
                  useCase.canUse(id)
            else {
                return useCase.defaultEngine
            }
            return id
        }
    }

    public static func set(_ engine: AIEngineID, for useCase: AIUseCase, in defaults: UserDefaults = .standard) {
        guard useCase.canUse(engine) else { return }

        switch useCase {
        case .organize:
            backendPreference(from: engine).store(in: defaults)
        default:
            defaults.set(engine.rawValue, forKey: key(for: useCase))
        }

        // Picking a local engine for inline "Why?" also drives the shared
        // local engine, so LocalAIService runs the right one.
        if useCase == .inlineExplain, engine.isLocal {
            (engine == .mlx ? AIEnginePreference.mlx : .template).store(in: defaults)
        }
    }

    // MARK: - Organizer bridge

    static func engineID(from preference: OrganizerBackendPreference) -> AIEngineID {
        switch preference {
        case .local: .template
        case .mlx: .mlx
        case .cloud: .cloud
        case .claudeCode: .claudeCode
        case .codex: .codex
        }
    }

    static func backendPreference(from engine: AIEngineID) -> OrganizerBackendPreference {
        switch engine {
        case .template: .local
        case .mlx: .mlx
        case .cloud: .cloud
        case .claudeCode: .claudeCode
        case .codex: .codex
        }
    }
}
