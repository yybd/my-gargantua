import SwiftUI

/// Reusable brand mark that renders the bundled `gargantua-logo.png` and
/// falls back to a hex-grid placeholder if the asset is missing.
public struct GargantuaBrandMark: View {
    public var body: some View {
        Group {
            if let image = Self.image {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(GargantuaColors.surface2)
                    .overlay {
                        Image(systemName: "circle.hexagongrid.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(GargantuaColors.accent)
                    }
            }
        }
    }

    private static let image: Image? = {
        guard let url = Bundle.gargantuaCoreResources.url(
            forResource: "gargantua-logo",
            withExtension: "png",
            subdirectory: "Brand"
        ) else {
            return nil
        }

        #if os(macOS)
            guard let nsImage = NSImage(contentsOf: url) else { return nil }
            return Image(nsImage: nsImage)
        #elseif os(iOS)
            guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
            return Image(uiImage: uiImage)
        #else
            return nil
        #endif
    }()
}
