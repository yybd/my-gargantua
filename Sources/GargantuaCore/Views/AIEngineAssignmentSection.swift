import SwiftUI

/// "What uses which engine" — the assignment half of the AI tab. One row per
/// job; each row picks from every engine, greying the ones that can't do that
/// job (with the reason inline) and showing the selected engine's tradeoff +
/// cost hint. Writes through `AIEngineAssignments`, which bridges to the
/// organizer + local-engine prefs so the rest of the app stays in sync.
struct AIEngineAssignmentSection: View {
    @State private var selections: [AIUseCase: AIEngineID] = [:]

    /// Jobs that actually route through an assigned engine today. `.maintenance`
    /// is intentionally excluded until the Codex agent runtime exists and Agent
    /// Run / scheduled audits honor the assignment — showing it now would be a
    /// control that does nothing.
    private let displayedUseCases: [AIUseCase] = [.inlineExplain, .deeperExplain, .organize]

    var body: some View {
        SettingsSectionContainer(
            "What uses which engine",
            subtitle: "Pick the engine for each job. Set the engines up above; assign them here."
        ) {
            ForEach(Array(displayedUseCases.enumerated()), id: \.element) { index, useCase in
                if index > 0 {
                    Divider().overlay(GargantuaColors.border)
                }
                assignmentRow(for: useCase)
            }
        }
        .task { reload() }
    }

    private func reload() {
        for useCase in displayedUseCases {
            selections[useCase] = AIEngineAssignments.engine(for: useCase)
        }
    }

    private func binding(for useCase: AIUseCase) -> AIEngineID {
        selections[useCase] ?? useCase.defaultEngine
    }

    @ViewBuilder
    private func assignmentRow(for useCase: AIUseCase) -> some View {
        let current = binding(for: useCase)

        HStack(alignment: .top, spacing: GargantuaSpacing.space3) {
            VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
                Text(useCase.title)
                    .font(GargantuaFonts.label)
                    .foregroundStyle(GargantuaColors.ink)
                Text(useCase.subtitle)
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(EngineCostHint.text(for: current))
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink4)
            }

            Spacer(minLength: GargantuaSpacing.space3)

            enginePicker(for: useCase, current: current)
        }
        .padding(.vertical, GargantuaSpacing.space1)
    }

    private func enginePicker(for useCase: AIUseCase, current: AIEngineID) -> some View {
        Menu {
            ForEach(AIEngineID.allCases) { engine in
                engineOption(useCase: useCase, engine: engine, current: current)
            }
        } label: {
            HStack(spacing: GargantuaSpacing.space1) {
                Image(systemName: current.systemImage)
                    .font(.system(size: 11))
                Text(current.label)
                    .font(GargantuaFonts.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(GargantuaColors.ink4)
            }
            .foregroundStyle(GargantuaColors.ink)
            .padding(.horizontal, GargantuaSpacing.space3)
            .padding(.vertical, GargantuaSpacing.space2)
            .background(GargantuaColors.surface3)
            .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose the engine for “\(useCase.title)”")
    }

    @ViewBuilder
    private func engineOption(useCase: AIUseCase, engine: AIEngineID, current: AIEngineID) -> some View {
        let reason = useCase.disabledReason(for: engine)
        Button {
            AIEngineAssignments.set(engine, for: useCase)
            selections[useCase] = engine
        } label: {
            if let reason {
                // Greyed-out: the disabled modifier dims it; the reason rides
                // along as a second line so the user sees WHY it can't be used.
                Text("\(engine.label) — \(reason)")
            } else if engine == current {
                Label(engine.label, systemImage: "checkmark")
            } else {
                Text(engine.label)
            }
        }
        .disabled(reason != nil)
    }
}

/// One-line tradeoff + cost hint per engine. Cloud shows an estimated token
/// count per call (input + up to the output budget) rather than a dollar/cent
/// figure; subscription CLIs note they bill to your own account.
enum EngineCostHint {
    static func text(for engine: AIEngineID) -> String {
        switch engine {
        case .template:
            return "Instant · free · on-device"
        case .mlx:
            return "On-device · free · needs the downloaded model"
        case .cloud:
            return "Metered · ≈ \(cloudTokenEstimate) tokens per call"
        case .claudeCode:
            return "Uses your Claude subscription · no per-call charge"
        case .codex:
            // Honest caveat: codex exec has no tool-disable flag, so it runs
            // locally with read access — for an explanation it can read files.
            return "Uses your Codex account · runs locally, can read files"
        }
    }

    /// Rough per-explanation token estimate: system + a representative item
    /// prompt on input, up to the configured output budget. Honest ballpark,
    /// not a billed figure.
    private static var cloudTokenEstimate: String {
        let config = CloudAIConfiguration()
        let inputSample = CloudAIPromptBuilder.systemPrompt + String(repeating: "x", count: 600)
        let input = CloudAICostEstimator.estimateTokens(for: inputSample)
        let low = input
        let high = input + config.maxTokens
        return "\(roundedHundreds(low))–\(roundedHundreds(high))"
    }

    private static func roundedHundreds(_ value: Int) -> String {
        if value >= 1000 {
            let thousands = Double(value) / 1000.0
            return String(format: "%.1fk", thousands)
        }
        let rounded = Int((Double(value) / 100.0).rounded()) * 100
        return "\(max(100, rounded))"
    }
}
