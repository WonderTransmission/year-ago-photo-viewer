/// Where a photo's date comes from. Each photo source picks one.
public enum DateSourceKind: String, CaseIterable, Codable, Sendable {
    /// A date embedded in the file name, such as a macOS screenshot name.
    case fileName
    /// The file's last-modified timestamp.
    case modified
    /// The file's creation timestamp.
    case created
    /// The capture date stored in the image's EXIF metadata.
    case exif

    /// A short label for menus.
    public var displayName: String {
        switch self {
        case .fileName: "File name"
        case .modified: "Modified date"
        case .created: "Created date"
        case .exif: "EXIF date"
        }
    }
}
