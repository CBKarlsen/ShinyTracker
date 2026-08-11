import Foundation

/// Supabase project coordinates, read from the app bundle — never compiled in.
///
/// `Info.plist` gets `SUPABASE_URL` / `SUPABASE_ANON_KEY` from build settings, which come from
/// `ios/App/Config/Secrets.xcconfig` (gitignored; copy `Secrets.example.xcconfig`).
public struct AuthConfig: Sendable {
    /// e.g. `https://<project>.supabase.co` — the project root, not the auth endpoint.
    public let projectURL: URL
    /// The publishable ("anon") key. Public by design; still not committed.
    public let anonKey: String

    public init(projectURL: URL, anonKey: String) {
        self.projectURL = projectURL
        self.anonKey = anonKey
    }

    /// The custom scheme the OAuth providers redirect back to. Must also be registered in the app
    /// target's `CFBundleURLTypes` and in the Supabase project's allowed redirect URLs.
    public static let redirectURL = URL(string: "shinytracker://auth-callback")!

    var authURL: URL { projectURL.appendingPathComponent("auth/v1") }

    public static func fromBundle(_ bundle: Bundle = .main) -> AuthConfig {
        guard
            let rawURL = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: rawURL), url.scheme != nil, url.host != nil,
            let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty
        else {
            // ponytail: fail loudly at launch rather than thread optionals through every caller —
            // this is a build-configuration mistake, not a runtime condition to recover from.
            fatalError(
                """
                SUPABASE_URL / SUPABASE_ANON_KEY missing from Info.plist.
                Copy ios/App/Config/Secrets.example.xcconfig to Secrets.xcconfig, fill it in, \
                and re-run `xcodegen generate` in ios/.
                """
            )
        }
        return AuthConfig(projectURL: url, anonKey: key)
    }
}
