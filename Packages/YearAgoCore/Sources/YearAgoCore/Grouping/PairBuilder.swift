import Foundation

/// Pairs RAW files with their camera JPEG or HEIC. See proposal 4.7.
///
/// Matching rule: same folder, same base name ignoring case, one RAW plus
/// one JPEG or HEIC. The JPEG/HEIC is shown; the RAW is hidden behind it.
public enum PairBuilder {
    /// One indexed file, as the pair builder sees it.
    public struct File: Equatable, Sendable {
        public var id: Int64
        public var locator: String
        public var isRaw: Bool

        public init(id: Int64, locator: String, isRaw: Bool) {
            self.id = id
            self.locator = locator
            self.isRaw = isRaw
        }
    }

    /// Extensions that can be a RAW file's display partner.
    static let partnerExtensions: Set<String> = ["jpg", "jpeg", "jpe", "heic", "heif"]

    /// Maps each paired RAW file's ID to its partner's ID. RAW files with
    /// no partner are left out.
    ///
    /// If a folder holds both `IMG_1.JPG` and `IMG_1.HEIC`, the partner is
    /// the one whose locator sorts first. Several RAWs (e.g. CR2 and DNG)
    /// may share one partner.
    public static func pairs(in files: [File]) -> [Int64: Int64] {
        var partners: [String: File] = [:]
        var raws: [(key: String, file: File)] = []
        for file in files {
            let key = stemKey(file.locator)
            if file.isRaw {
                raws.append((key, file))
            } else if partnerExtensions.contains(pathExtension(file.locator)) {
                if let existing = partners[key], existing.locator < file.locator { continue }
                partners[key] = file
            }
        }
        var result: [Int64: Int64] = [:]
        for raw in raws {
            if let partner = partners[raw.key] {
                result[raw.file.id] = partner.id
            }
        }
        return result
    }

    /// "Trip/IMG_1234.CR2" → "trip/img_1234": folder plus base name, lowercased.
    static func stemKey(_ locator: String) -> String {
        let lower = locator.lowercased()
        guard let dot = lower.lastIndex(of: "."),
              lower[dot...].firstIndex(of: "/") == nil
        else { return lower }
        return String(lower[..<dot])
    }

    static func pathExtension(_ locator: String) -> String {
        guard let dot = locator.lastIndex(of: ".") else { return "" }
        let ext = locator[locator.index(after: dot)...]
        return ext.contains("/") ? "" : ext.lowercased()
    }
}
