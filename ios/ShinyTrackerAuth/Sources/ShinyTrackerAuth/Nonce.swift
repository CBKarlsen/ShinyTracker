import CryptoKit
import Foundation
import Security

/// Sign in with Apple nonce handling.
///
/// Apple receives the **SHA256 hex** of the nonce (it lands in the identity token's `nonce`
/// claim); Supabase receives the **raw** nonce and re-hashes it to verify the token was minted
/// for this request. Sending the same value to both, or hashing twice, fails verification
/// silently — the token simply gets rejected with no useful error.
enum Nonce {
    /// A fresh random nonce, base64url, unpadded.
    static func random(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with \(status)")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Lowercase hex SHA256 of `value` — the form Apple expects on the request.
    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
