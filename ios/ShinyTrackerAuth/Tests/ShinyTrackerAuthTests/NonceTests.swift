import Foundation
import Testing

@testable import ShinyTrackerAuth

@Suite("Sign in with Apple nonce")
struct NonceTests {
    /// The whole flow hinges on Apple getting the hash and Supabase getting the raw value, so pin
    /// the hash against a known vector rather than against our own implementation.
    @Test("sha256Hex matches the standard vector for \"abc\"")
    func knownVector() {
        #expect(
            Nonce.sha256Hex("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(
            Nonce.sha256Hex("")
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test("sha256Hex is 64 lowercase hex characters")
    func hexShape() {
        let hex = Nonce.sha256Hex(Nonce.random())
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("random nonces are unique and URL-safe")
    func randomness() {
        let nonces = (0..<200).map { _ in Nonce.random() }
        #expect(Set(nonces).count == nonces.count)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(nonces.allSatisfy { !$0.isEmpty && $0.allSatisfy(allowed.contains) })
    }
}
