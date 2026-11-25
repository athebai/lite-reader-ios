import Foundation

/// Builds stable, filesystem-safe names that stay unique for Chinese titles.
///
/// The readable part is ASCII-only (for debugging), while a FNV-1a hash of the
/// original string guarantees two different books never share a cache folder.
enum FileKey {

    static func make(_ name: String, maxPrefix: Int = 32) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        var prefix = ""
        for scalar in name.unicodeScalars {
            if prefix.count >= maxPrefix { break }
            if allowed.contains(scalar) {
                prefix.unicodeScalars.append(scalar)
            } else {
                prefix.append("_")
            }
        }
        if prefix.isEmpty { prefix = "item" }

        var hash: UInt64 = 14695981039346656037
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return "\(prefix)-\(String(hash, radix: 16))"
    }
}
