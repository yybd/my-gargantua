import AppKit
import SwiftUI

// Header, metrics, controls, chips, expanded detail, and context menu for
// ProcessInventoryRow. Split out of the row so the type body stays under the
// length policy; `isHovered` is internal (not private) so this extension can
// reach it.
extension ProcessInventoryRow {
    /// Stop is offered for any user-controllable process. The executor still
    /// re-checks at run time — this gate is just the hover affordance.
    var canStop: Bool {
        guard item.safety != .protected_ else { return false }
        if item.pid <= 1 { return false }
        if let path = item.executablePath, path.hasPrefix("/System/") { return false }
        return true
    }

    /// Remove Source surfaces only when the launchd link is confident enough
    /// to safely route the user to the right Background Items row, and the
    /// safety tier permits the disable that would follow on the destination
    /// pane. Mirrors the executor's refusal so the user never sees a
    /// dead-end affordance.
    var canRemoveSource: Bool {
        guard item.safety != .protected_ else { return false }
        guard case .launchd = item.launchSource else { return false }
        return item.launchConfidence == .exact || item.launchConfidence == .path
    }

    // MARK: - Collapsed header

    var collapsedHeader: some View {
        HStack(alignment: .top, spacing: GargantuaSpacing.space3) {
            safetyIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: GargantuaSpacing.space2) {
                    Text(item.displayName)
                        .font(GargantuaFonts.label)
                        .foregroundStyle(GargantuaColors.ink)
                        .lineLimit(1)

                    Text("PID \(item.pid)")
                        .font(GargantuaFonts.caption.monospacedDigit())
                        .foregroundStyle(GargantuaColors.ink3)

                    Text(item.launchSource.displayLabel)
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.ink3)
                }

                Text(item.explanation)
                    .font(GargantuaFonts.body)
                    .foregroundStyle(GargantuaColors.ink2)
                    .lineLimit(2)

                if let path = item.executablePath {
                    Text(path)
                        .font(GargantuaFonts.monoPath)
                        .foregroundStyle(GargantuaColors.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if !item.reasons.isEmpty || item.launchConfidence != .unknown {
                    chipRow
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleExpand)

            metricsBadges

            trailingControls
        }
        .padding(.horizontal, GargantuaSpacing.space4)
        .padding(.vertical, GargantuaSpacing.space3)
        .padding(.leading, GargantuaSpacing.space1)
    }

    var safetyIcon: some View {
        Image(systemName: safetySFSymbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(safetyColor)
            .frame(width: 16, height: 16, alignment: .center)
    }

    var metricsBadges: some View {
        VStack(alignment: .trailing, spacing: 4) {
            metricBadge(label: "CPU", value: ProcessInventoryFormat.cpu(item.cpuFraction))
            metricBadge(label: "MEM", value: ProcessInventoryFormat.bytes(item.residentBytes))
        }
    }

    func metricBadge(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink4)
            Text(value)
                .font(GargantuaFonts.monoData)
                .foregroundStyle(GargantuaColors.ink2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: GargantuaRadius.small)
                .fill(GargantuaColors.surface2)
        }
    }

    var trailingControls: some View {
        HStack(spacing: GargantuaSpacing.space2) {
            if isBusy {
                AccretionDiskView(activityRate: 12, size: 14, color: GargantuaColors.accretion)
            }

            if isHovered, let onExplain {
                Button(action: onExplain) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(GargantuaColors.accent)
                }
                .buttonStyle(.plain)
                .help("Generate an AI explanation")
            }

            if isHovered, let onAction {
                actionButtonGroup(onAction: onAction)
            }

            if let onRevealBinary, item.executablePath != nil {
                Button(action: onRevealBinary) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(GargantuaColors.ink2)
                }
                .buttonStyle(.plain)
                .help("Reveal binary in Finder")
            }

            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GargantuaColors.ink3)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse details" : "Show details")
        }
        .frame(width: 132, alignment: .trailing)
    }

    func actionButtonGroup(onAction: @escaping (ProcessAction) -> Void) -> some View {
        HStack(spacing: 4) {
            if canStop {
                Button {
                    onAction(.stop)
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(GargantuaColors.review)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help("Stop this process")
            }

            if canRemoveSource {
                Button {
                    onAction(.removeSource)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundStyle(GargantuaColors.accent)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help("Open this process's source in Background Items")
            }
        }
    }

    // MARK: - Chips

    var chipRow: some View {
        HStack(spacing: GargantuaSpacing.space1) {
            if item.launchConfidence != .unknown {
                confidenceChip
            }
            ForEach(Array(item.reasons).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { reason in
                Text(reason.displayLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(chipForeground(for: reason))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: GargantuaRadius.small)
                            .fill(chipBackground(for: reason))
                    }
            }
        }
    }

    var confidenceChip: some View {
        Text("Match: \(item.launchConfidence.displayLabel)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(confidenceForeground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: GargantuaRadius.small)
                    .fill(confidenceBackground)
            }
    }

    // MARK: - Expanded detail

    var expandedDetail: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            Rectangle()
                .fill(GargantuaColors.borderSoft)
                .frame(height: 1)
                .padding(.horizontal, GargantuaSpacing.space3)

            VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
                detailRow(label: "PID", value: "\(item.pid)", mono: true)
                detailRow(label: "Parent PID", value: "\(item.parentPID)", mono: true)
                detailRow(label: "User", value: item.owningUser)
                detailRow(label: "Command", value: item.command, mono: true)
                if let exe = item.executablePath {
                    detailRow(label: "Executable", value: exe, mono: true)
                }
                if case let .launchd(_, label, plistPath) = item.launchSource {
                    detailRow(label: "Launchd Label", value: label, mono: true)
                    detailRow(label: "Plist", value: plistPath, mono: true)
                    if let onRevealPlist {
                        HStack {
                            Spacer().frame(width: 92)
                            Button("Reveal plist in Finder", action: onRevealPlist)
                                .buttonStyle(.plain)
                                .font(GargantuaFonts.caption)
                                .foregroundStyle(GargantuaColors.accent)
                            Spacer()
                        }
                    }
                }
                detailRow(label: "Source", value: item.launchSource.displayLabel)
                detailRow(label: "Match", value: item.launchConfidence.displayLabel)
                if let identity = item.identity {
                    if let team = identity.teamIdentifier {
                        detailRow(label: "Team ID", value: team, mono: true)
                    }
                    if let signing = identity.signingIdentity {
                        detailRow(label: "Signed by", value: signing)
                    }
                    if let bundleID = identity.bundleIdentifier {
                        detailRow(label: "Bundle ID", value: bundleID, mono: true)
                    }
                    if let version = identity.bundleShortVersion {
                        detailRow(label: "Version", value: version)
                    }
                    detailRow(label: "Vendor", value: vendorLabel(identity.vendor))
                    if let valid = identity.signatureValid {
                        detailRow(label: "Signature", value: valid ? "Valid" : "Invalid")
                    }
                }
            }
            .padding(.horizontal, GargantuaSpacing.space4)
            .padding(.vertical, GargantuaSpacing.space2)
            .padding(.leading, GargantuaSpacing.space1)
        }
    }

    func detailRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: GargantuaSpacing.space3) {
            Text(label)
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink3)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(mono ? GargantuaFonts.monoData : GargantuaFonts.body)
                .foregroundStyle(GargantuaColors.ink)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    var contextMenu: some View {
        if let onAction, canStop {
            Button("Stop process") { onAction(.stop) }
        }
        if let onAction, canRemoveSource {
            Button("Open source in Background Items") { onAction(.removeSource) }
        }
        if (canStop || canRemoveSource) && (onAction != nil) {
            Divider()
        }
        if let onRevealBinary, item.executablePath != nil {
            Button("Reveal binary in Finder") { onRevealBinary() }
        }
        if let onRevealPlist, item.launchSource.plistPath != nil {
            Button("Reveal launching plist in Finder") { onRevealPlist() }
        }
        if let onExplain {
            Button("Explain with AI") { onExplain() }
        }
        Button("Copy command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.command, forType: .string)
        }
    }

    var accessibilityDescription: String {
        let safetyWord = {
            switch item.safety {
            case .safe: "Safe"
            case .review: "Review"
            case .protected_: "Protected"
            }
        }()
        return "\(item.displayName), PID \(item.pid), \(safetyWord). \(item.explanation)"
    }
}
