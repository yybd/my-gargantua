import SwiftUI

/// Settings surface for the two TCC permissions Gargantua relies on.
///
/// Onboarding only runs once, so users who installed before this flow existed —
/// or who skipped/denied a permission — need a durable place to grant or repair
/// it. Full Disk Access is link-only (macOS has no programmatic grant); Finder
/// Automation can be requested in place, which is also the *only* way the app
/// gets added to System Settings ▸ Privacy & Security ▸ Automation (that pane
/// has no "+").
struct PermissionsSettingsSection: View {
    @State private var hasFullDiskAccess = PermissionChecker.hasFullDiskAccess
    @State private var automation = PermissionChecker.finderAutomationPermission(prompt: false)
    @State private var isRequesting = false
    @State private var requestTask: Task<Void, Never>?

    @Environment(\.openURL) private var openURL

    /// Reflects grants made directly in System Settings without a manual refresh.
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsSectionContainer(
            "Permissions",
            subtitle: "Grant these any time. Cleanup still works without them, just with fewer guarantees."
        ) {
            fullDiskAccessRow

            SettingsHairlineDivider()

            automationRow
        }
        .onReceive(timer) { _ in
            hasFullDiskAccess = PermissionChecker.hasFullDiskAccess
            if !isRequesting {
                automation = PermissionChecker.finderAutomationPermission(prompt: false)
            }
        }
        .onDisappear { requestTask?.cancel() }
    }

    // MARK: - Full Disk Access

    private var fullDiskAccessRow: some View {
        HStack(spacing: GargantuaSpacing.space3) {
            SettingsRowIcon(systemName: "externaldrive.fill.badge.checkmark", size: 20)

            SettingsRowText(
                title: "Full Disk Access",
                detail: hasFullDiskAccess
                    ? "Granted — scans reach protected system folders."
                    : "Not granted — scans are limited to your home folder.",
                detailColor: hasFullDiskAccess ? GargantuaColors.safe : GargantuaColors.review
            )

            Spacer(minLength: GargantuaSpacing.space3)

            if hasFullDiskAccess {
                grantedBadge
            } else {
                GargantuaButton("Open Settings", icon: "arrow.up.forward.app") {
                    openURL(fullDiskAccessURL)
                }
            }
        }
    }

    // MARK: - Finder Automation

    private var automationRow: some View {
        HStack(spacing: GargantuaSpacing.space3) {
            SettingsRowIcon(systemName: "arrow.3.trianglepath", size: 20)

            SettingsRowText(
                title: "Finder Automation",
                detail: automationDetail,
                detailColor: automationDetailColor
            )

            Spacer(minLength: GargantuaSpacing.space3)

            automationControl
        }
    }

    @ViewBuilder
    private var automationControl: some View {
        switch automation {
        case .granted:
            grantedBadge
        case .denied:
            GargantuaButton("Open Settings", icon: "arrow.up.forward.app") {
                openURL(automationURL)
            }
        case .notDetermined:
            if isRequesting {
                AccretionDiskView(activityRate: 18, size: 16, color: GargantuaColors.accent)
            } else {
                GargantuaButton("Allow…", icon: "checkmark.shield", tone: .primary) {
                    requestAutomation()
                }
            }
        }
    }

    private var automationDetail: String {
        switch automation {
        case .granted:
            return "Allowed — Finder moves items to Trash so cleanup stays reversible."
        case .denied:
            return "Denied — turn Gargantua → Finder back on in Settings; macOS won't re-prompt."
        case .notDetermined:
            return "Not requested — allow it so deletions route through Finder's Trash."
        }
    }

    private var automationDetailColor: Color {
        switch automation {
        case .granted: return GargantuaColors.safe
        case .denied: return GargantuaColors.protected_
        case .notDetermined: return GargantuaColors.review
        }
    }

    private var grantedBadge: some View {
        HStack(spacing: GargantuaSpacing.space1) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
            Text("Granted")
                .font(GargantuaFonts.label)
        }
        .foregroundStyle(GargantuaColors.safe)
    }

    private func requestAutomation() {
        guard !isRequesting, automation == .notDetermined else { return }
        isRequesting = true
        requestTask = Task.detached {
            // Blocks while the consent dialog is on screen — must stay off main.
            let result = PermissionChecker.finderAutomationPermission(prompt: true)
            await MainActor.run {
                automation = result
                isRequesting = false
            }
        }
    }

    private var fullDiskAccessURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    }

    private var automationURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    }
}
