import CryptoKit
import Foundation

/// SHA-256 of a file's contents, read in 1 MB chunks.
public enum ContentHasher {
    static let chunkSize = 1 << 20

    /// Returns nil if the file cannot be read.
    public static func sha256(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return Data(hasher.finalize())
    }
}
