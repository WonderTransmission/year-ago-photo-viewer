import UniformTypeIdentifiers

/// What kind of file a path holds, judged by its extension.
public enum MediaKind: String, Codable, Sendable {
    /// A still image ImageIO can read: JPEG, HEIC, PNG, TIFF, and so on.
    case image
    /// A camera RAW file: CR2, CR3, NEF, ARW, DNG, and so on.
    case raw
    /// A video. Always ignored.
    case video
    /// A metadata sidecar such as `.xmp` or `.aae`. Always ignored.
    case sidecar
    /// Anything else.
    case other

    /// True for the kinds the viewer shows.
    public var isDisplayable: Bool {
        self == .image || self == .raw
    }

    /// Sidecar extensions. UTType does not classify these consistently.
    static let sidecarExtensions: Set<String> = ["xmp", "aae", "thm"]

    /// Classifies a file by its extension, case-insensitively.
    public static func classify(pathExtension: String) -> MediaKind {
        let ext = pathExtension.lowercased()
        guard !ext.isEmpty else { return .other }
        if sidecarExtensions.contains(ext) { return .sidecar }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .rawImage) { return .raw }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audiovisualContent) { return .video }
        return .other
    }
}
