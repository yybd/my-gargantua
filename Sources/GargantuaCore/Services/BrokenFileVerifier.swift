import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.gargantua.core", category: "BrokenFileVerifier")

/// The outcome of second-guessing a czkawka `broken` (corrupt-file) verdict.
///
/// czkawka's image check decodes strictly by file extension: a JPEG saved as
/// `.png` fails the PNG decoder and is reported as corrupt even though it
/// renders fine everywhere that content-sniffs (Finder, browsers, ImageIO).
/// The verifier re-checks the bytes so the adapter can drop or relabel these
/// false positives instead of telling the user a healthy file is broken.
public enum BrokenFileVerdict: Sendable, Equatable {
    /// The file decodes as a valid image and its real container matches the
    /// declared extension. czkawka was simply wrong — drop the finding.
    case validMatchingExtension

    /// The file decodes as a valid image but its real container differs from
    /// the declared extension. Not corrupt, just misnamed — surface a rename
    /// affordance rather than a deletion candidate.
    case validWrongExtension(actualFormatName: String, actualExtension: String)

    /// Couldn't be verified (not an image we can read, or genuinely
    /// undecodable). Trust czkawka's verdict and keep the finding as-is.
    case unverified
}

/// Re-validates a path czkawka flagged as a broken/corrupt file.
public protocol BrokenFileVerifier: Sendable {
    func verify(path: String) -> BrokenFileVerdict
}

/// ImageIO-backed verifier. Content-sniffs the file (ignoring its extension),
/// confirms the image data is complete/decodable, and compares the real
/// container type against the declared extension.
///
/// Only images are verifiable here — czkawka's `broken` check also covers PDF,
/// audio, archive, and video, which ImageIO can't read. Those return
/// `.unverified` so the original corrupt verdict stands.
public struct ImageIOBrokenFileVerifier: BrokenFileVerifier {
    public init() {}

    public func verify(path: String) -> BrokenFileVerdict {
        let url = URL(fileURLWithPath: path)
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let typeID = CGImageSourceGetType(source),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else {
            return .unverified
        }

        let realType = UTType(typeID as String)
        let declaredExt = url.pathExtension.lowercased()

        if !declaredExt.isEmpty,
           let declaredType = UTType(filenameExtension: declaredExt),
           let realType,
           declaredType == realType
               || declaredType.conforms(to: realType)
               || realType.conforms(to: declaredType) {
            return .validMatchingExtension
        }

        let actualExt = realType?.preferredFilenameExtension ?? (typeID as String)
        let name = realType?.localizedDescription ?? "image"
        logger.debug(
            "Broken-file false positive: \(url.lastPathComponent, privacy: .public) is a valid \(name, privacy: .public)"
        )
        return .validWrongExtension(actualFormatName: name, actualExtension: actualExt)
    }
}
