import SwiftUI

/// One-shot Codex agent run screen — the Codex sibling of
/// `ClaudeCodeAgentView`. Codex runs read-only via `codex exec` with no MCP
/// and no approval gates, so this is a straight pick-a-template → run →
/// read-the-report flow. Routed from "Agent Run" when the `maintenance` job is
/// assigned to Codex.
public struct CodexAgentView: View {
    @StateObject private var controller: CodexAgentRunController
    @State private var selectedTemplate: CodexAgentPromptTemplate = .investigateSpace
    @State private var userContext = ""

    @MainActor
    public init(controller: CodexAgentRunController? = nil) {
        self._controller = StateObject(wrappedValue: controller ?? CodexAgentRunController())
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: GargantuaSpacing.space5) {
                promptSection
                resultSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(GargantuaSpacing.space5)
        }
        .background(GargantuaColors.void_)
    }

    private var header: some View {
        PageHeaderView(
            title: "Agent Run",
            subtitle: "Hand the audit to Codex — one read-only `codex exec` pass, then a written report.",
            subtitleStyle: .voice
        ) {
            if controller.status.isRunning {
                HStack(spacing: GargantuaSpacing.space2) {
                    AccretionDiskView(activityRate: 8, size: 16, color: GargantuaColors.accretion)
                    Text("Running…")
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.ink3)
                }
            }
        }
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space3) {
            Text("PROMPT")
                .font(GargantuaFonts.sectionLabel)
                .tracking(0.8)
                .foregroundStyle(GargantuaColors.ink2)

            templatePicker

            Text(selectedTemplate.summary)
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink3)
                .fixedSize(horizontal: false, vertical: true)

            TextField(selectedTemplate.placeholder, text: $userContext, axis: .vertical)
                .textFieldStyle(.plain)
                .font(GargantuaFonts.body)
                .foregroundStyle(GargantuaColors.ink)
                .lineLimit(2...5)
                .padding(GargantuaSpacing.space3)
                .background(GargantuaColors.surface3)
                .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))

            HStack {
                Spacer()
                if controller.status.isRunning {
                    GargantuaButton("Cancel", icon: "stop.circle", tone: .neutral) {
                        controller.cancel()
                    }
                } else {
                    GargantuaButton("Start run", icon: "play.fill", tone: .primary) {
                        controller.start(template: selectedTemplate, userContext: userContext)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var templatePicker: some View {
        Menu {
            ForEach(CodexAgentPromptTemplate.allCases) { template in
                Button {
                    selectedTemplate = template
                } label: {
                    Label(template.title, systemImage: template.icon)
                }
            }
        } label: {
            HStack(spacing: GargantuaSpacing.space2) {
                Image(systemName: selectedTemplate.icon)
                    .font(.system(size: 12))
                Text(selectedTemplate.title)
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
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        switch controller.status {
        case .idle:
            emptyState
        case .running:
            runningState
        case .failed:
            if let message = controller.errorMessage {
                noticeCard(icon: "exclamationmark.triangle.fill", tone: GargantuaColors.protected_, message: message)
            }
        case .finished:
            reportCard
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            Text("REPORT")
                .font(GargantuaFonts.sectionLabel)
                .tracking(0.8)
                .foregroundStyle(GargantuaColors.ink2)
            Text("Pick a template and start a run. Codex inspects the filesystem read-only and returns its findings here — nothing is deleted.")
                .font(GargantuaFonts.body)
                .foregroundStyle(GargantuaColors.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var runningState: some View {
        HStack(spacing: GargantuaSpacing.space3) {
            AccretionDiskView(activityRate: 8, size: 24, color: GargantuaColors.accretion)
            Text("Codex is inspecting the filesystem…")
                .font(GargantuaFonts.body)
                .foregroundStyle(GargantuaColors.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            HStack {
                Text("REPORT")
                    .font(GargantuaFonts.sectionLabel)
                    .tracking(0.8)
                    .foregroundStyle(GargantuaColors.ink2)
                Spacer()
                GargantuaButton("Re-run", icon: "arrow.clockwise", tone: .neutral) {
                    controller.restart()
                }
            }
            ScrollView {
                Text(controller.output)
                    .font(GargantuaFonts.body)
                    .foregroundStyle(GargantuaColors.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GargantuaSpacing.space4)
            }
            .background(GargantuaColors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func noticeCard(icon: String, tone: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: GargantuaSpacing.space3) {
            Image(systemName: icon)
                .foregroundStyle(tone)
            Text(message)
                .font(GargantuaFonts.body)
                .foregroundStyle(GargantuaColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(GargantuaSpacing.space4)
        .background(tone.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.medium))
    }
}
