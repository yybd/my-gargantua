import SwiftUI

// MARK: - Control bar, sort/filter, footer

extension ProcessInventoryView {
    func controlBar(scan: ProcessInventoryScan, visibleCount: Int) -> some View {
        let triageResults = suspiciousTriageResults(scan)
        return HStack(spacing: GargantuaSpacing.space3) {
            sortToggle
            Divider()
                .frame(height: 14)
                .overlay(GargantuaColors.border)
            ForEach(ProcessSafetyFilter.allCases, id: \.self) { option in
                filterButton(option, scan: scan)
            }
            Spacer()
            if let onTriage, !triageResults.isEmpty {
                aiTriageButton {
                    onTriage(triageResults)
                }
            }
            Text("\(visibleCount) shown")
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink3)
        }
        .padding(.horizontal, GargantuaSpacing.space4)
        .padding(.vertical, GargantuaSpacing.space2)
    }

    func aiTriageButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: GargantuaSpacing.space1) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 11, weight: .medium))
                Text("Suspicious Triage")
                    .font(GargantuaFonts.caption)
            }
            .foregroundStyle(GargantuaColors.accent)
        }
        .buttonStyle(.plain)
        .help("Analyze the top suspicious process candidates with the active AI engine")
    }

    var sortToggle: some View {
        HStack(spacing: 4) {
            Text("Sort:")
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink3)
            ForEach(ProcessSortMetric.allCases, id: \.self) { metric in
                Button {
                    guard sortMetric != metric else { return }
                    sortMetric = metric
                    startSnapshot()
                } label: {
                    Text(metric.displayLabel)
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(sortMetric == metric ? GargantuaColors.ink : GargantuaColors.ink2)
                        .padding(.horizontal, GargantuaSpacing.space2)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: GargantuaRadius.small)
                                .fill(sortMetric == metric ? GargantuaColors.surface2 : .clear)
                        }
                }
                .buttonStyle(.plain)
                .disabled(session.isScanning)
            }
        }
    }

    func filterButton(_ option: ProcessSafetyFilter, scan: ProcessInventoryScan) -> some View {
        let count = option.apply(scan.items).count
        let isActive = safetyFilter == option
        return Button {
            safetyFilter = option
        } label: {
            HStack(spacing: 4) {
                Text(option.displayLabel)
                    .font(GargantuaFonts.caption)
                Text("\(count)")
                    .font(GargantuaFonts.caption.monospacedDigit())
                    .foregroundStyle(GargantuaColors.ink3)
            }
            .foregroundStyle(isActive ? GargantuaColors.ink : GargantuaColors.ink2)
            .padding(.horizontal, GargantuaSpacing.space2)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: GargantuaRadius.small)
                    .fill(isActive ? GargantuaColors.surface2 : .clear)
            }
        }
        .buttonStyle(.plain)
    }

    var emptyState: some View {
        VStack(spacing: GargantuaSpacing.space2) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(GargantuaColors.ink3)
            Text("No processes match the current filter.")
                .font(GargantuaFonts.body)
                .foregroundStyle(GargantuaColors.ink2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func footer(scan: ProcessInventoryScan) -> some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
            Rectangle()
                .fill(GargantuaColors.border)
                .frame(height: 1)
            HStack(spacing: GargantuaSpacing.space2) {
                Text("Stop and Remove Source actions are recorded to the audit log.")
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink3)
                Spacer()
                Text("Last sampled " + Self.timestampFormatter.localizedString(for: scan.scannedAt, relativeTo: Date()))
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink3)
            }
            .padding(.horizontal, GargantuaSpacing.space4)
            .padding(.vertical, GargantuaSpacing.space2)
        }
    }

    static let timestampFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
