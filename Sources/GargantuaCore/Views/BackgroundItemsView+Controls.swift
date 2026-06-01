import SwiftUI

// MARK: - Control bar, filters, footer

extension BackgroundItemsView {
    func controlBar(scan: BackgroundItemScan, visibleCount: Int) -> some View {
        let triageResults = suspiciousTriageResults(scan)
        return HStack(spacing: GargantuaSpacing.space3) {
            ForEach(BackgroundItemFilter.allCases, id: \.self) { option in
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
        .help("Analyze the top suspicious background item candidates with the active AI engine")
    }

    func filterButton(_ option: BackgroundItemFilter, scan: BackgroundItemScan) -> some View {
        let count = option.apply(scan.items).count
        let isActive = filter == option
        return Button {
            filter = option
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
            Text("No items match the current filter.")
                .font(GargantuaFonts.body)
                .foregroundStyle(GargantuaColors.ink2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func footer(scan: BackgroundItemScan) -> some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
            Rectangle()
                .fill(GargantuaColors.border)
                .frame(height: 1)
            HStack(spacing: GargantuaSpacing.space2) {
                if scan.loginItemsNeedPrivileges {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11))
                        .foregroundStyle(GargantuaColors.ink3)
                    Text("Login-item enumeration is limited without elevated privileges.")
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.ink3)
                    Button("Open Login Items", action: openLoginItemsSettings)
                        .buttonStyle(.plain)
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.accent)
                }
                if scan.unparseableCount > 0 {
                    Text("\(scan.unparseableCount) unreadable plist\(scan.unparseableCount == 1 ? "" : "s") skipped.")
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.review)
                }
                Spacer()
                Text("Last scanned " + Self.timestampFormatter.localizedString(for: scan.scannedAt, relativeTo: Date()))
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
