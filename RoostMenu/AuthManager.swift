import Foundation
import AppKit

enum AuthError: LocalizedError {
    case notConfigured
    case reauthRequired
    case badCode
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Open Settings and enter your Project ID, Client ID and Client Secret."
        case .reauthRequired:
            return "Google signed you out (refresh token rejected). If your OAuth app is still in Testing mode this happens every 7 days. Sign in again, and publish the app to production to stop it."
        case .badCode: return "Couldn't find an authorization code in what you pasted."
        case .server(let m): return m
        }
    }
}

/// OAuth 2.0 against Google using the redirect flow Device Access documents
/// (redirect to https://www.google.com, user pastes the resulting address).
/// Refresh token + client secret live in the Keychain; the access token is memory-only.
@MainActor
final class AuthManager: ObservableObject {
    static let redirectURI = "https://www.google.com"
    static let scope = "https://www.googleapis.com/auth/sdm.service"
    private let tokenURL = URL(string: "https://www.googleapis.com/oauth2/v4/token")!

    @Published var projectID: String
    @Published var clientID: String
    @Published var clientSecret: String
    @Published private(set) var isSignedIn: Bool

    private var accessTokenValue: String?
    private var accessTokenExpiry: Date = .distantPast
    private var refreshTask: Task<String, Error>?

    init() {
        let d = UserDefaults.standard
        projectID = d.string(forKey: "projectID") ?? ""
        clientID = d.string(forKey: "clientID") ?? ""
        clientSecret = Keychain.get("clientSecret") ?? ""
        isSignedIn = Keychain.get("refreshToken") != nil
    }

    var isConfigured: Bool {
        !projectID.trimmed.isEmpty && !clientID.trimmed.isEmpty && !clientSecret.trimmed.isEmpty
    }

    func saveCredentials() {
        projectID = projectID.trimmed
        clientID = clientID.trimmed
        clientSecret = clientSecret.trimmed
        UserDefaults.standard.set(projectID, forKey: "projectID")
        UserDefaults.standard.set(clientID, forKey: "clientID")
        Keychain.set(clientSecret, for: "clientSecret")
    }

    var authorizationURL: URL? {
        guard isConfigured else { return nil }
        var c = URLComponents(string: "https://nestservices.google.com/partnerconnections/\(projectID.trimmed)/auth")!
        c.queryItems = [
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
        ]
        return c.url
    }

    func openSignIn() {
        saveCredentials()
        if let url = authorizationURL { NSWorkspace.shared.open(url) }
    }

    /// Accepts either the full redirected address (…?code=…&scope=…) or the bare code.
    func finishSignIn(pasted: String) async throws {
        saveCredentials()
        let text = pasted.trimmed
        var code = text
        if let comps = URLComponents(string: text),
           let c = comps.queryItems?.first(where: { $0.name == "code" })?.value {
            code = c
        }
        guard !code.isEmpty, !code.contains(" ") else { throw AuthError.badCode }
        let resp = try await post([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": Self.redirectURI,
        ])
        guard let refresh = resp.refresh_token else {
            throw AuthError.server("Google didn't return a refresh token. Sign in again from the button above.")
        }
        Keychain.set(refresh, for: "refreshToken")
        accessTokenValue = resp.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(resp.expires_in ?? 3000))
        isSignedIn = true
    }

    func signOut() {
        Keychain.delete("refreshToken")
        accessTokenValue = nil
        accessTokenExpiry = .distantPast
        isSignedIn = false
    }

    func invalidateAccessToken() { accessTokenExpiry = .distantPast }

    func accessToken() async throws -> String {
        if let t = accessTokenValue, accessTokenExpiry > Date().addingTimeInterval(60) { return t }
        if let task = refreshTask { return try await task.value }
        let task = Task { try await self.refresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func refresh() async throws -> String {
        guard isConfigured else { throw AuthError.notConfigured }
        guard let refresh = Keychain.get("refreshToken") else {
            isSignedIn = false
            throw AuthError.reauthRequired
        }
        do {
            let resp = try await post([
                "client_id": clientID,
                "client_secret": clientSecret,
                "refresh_token": refresh,
                "grant_type": "refresh_token",
            ])
            accessTokenValue = resp.access_token
            accessTokenExpiry = Date().addingTimeInterval(TimeInterval(resp.expires_in ?? 3000))
            return resp.access_token
        } catch TokenError.invalidGrant {
            signOut()
            throw AuthError.reauthRequired
        }
    }

    // MARK: HTTP

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
    }
    private struct TokenErrorBody: Decodable { let error: String?; let error_description: String? }
    private enum TokenError: Error { case invalidGrant }

    private func post(_ params: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return try JSONDecoder().decode(TokenResponse.self, from: data) }
        let body = try? JSONDecoder().decode(TokenErrorBody.self, from: data)
        if body?.error == "invalid_grant", params["grant_type"] == "refresh_token" { throw TokenError.invalidGrant }
        throw AuthError.server("Google sign-in failed: \(body?.error_description ?? body?.error ?? "HTTP \(status)")")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? self
    }
}
