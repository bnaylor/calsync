import Foundation
import Network

public actor GoogleAuthService {
    private let keychain: KeychainService
    private let port: UInt16 = 8080
    private let redirectUri = "http://localhost:8080"

    struct TokenResponse: Codable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let scope: String
        let token_type: String
    }

    public enum AuthError: Error {
        case notAuthenticated
        case refreshFailed(String)
        case missingCredentials
    }

    public init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    public func authenticate(clientId: String, clientSecret: String) async throws {
        try keychain.save(key: "clientId", value: clientId)
        try keychain.save(key: "clientSecret", value: clientSecret)

        let authUrl = "https://accounts.google.com/o/oauth2/v2/auth?" + [
            "client_id=\(clientId)",
            "redirect_uri=\(redirectUri)",
            "response_type=code",
            "scope=https://www.googleapis.com/auth/calendar",
            "access_type=offline",
            "prompt=consent"
        ].joined(separator: "&")

        print("Please open this URL in your browser to authenticate:")
        print(authUrl)

        let code = try await waitForRedirect()
        let tokenResponse = try await exchangeCodeForToken(code, clientId: clientId, clientSecret: clientSecret)

        try keychain.save(key: "accessToken", value: tokenResponse.access_token)
        if let refreshToken = tokenResponse.refresh_token {
            try keychain.save(key: "refreshToken", value: refreshToken)
        }
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        try keychain.save(key: "expiresAt", value: String(expiresAt.timeIntervalSince1970))

        print("Successfully authenticated! Tokens stored in Keychain.")
    }

    public func getValidAccessToken() async throws -> String {
        guard let accessToken = try keychain.retrieve(key: "accessToken") else {
            throw AuthError.notAuthenticated
        }
        if let expiresAtStr = try keychain.retrieve(key: "expiresAt"),
           let expiresAt = Double(expiresAtStr) {
            if Date().timeIntervalSince1970 < expiresAt - 60 {
                return accessToken
            }
        }
        return try await refreshAccessToken()
    }

    public func refreshAccessToken() async throws -> String {
        guard let refreshToken = try keychain.retrieve(key: "refreshToken"),
              let clientId = try keychain.retrieve(key: "clientId"),
              let clientSecret = try keychain.retrieve(key: "clientSecret") else {
            throw AuthError.missingCredentials
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "refresh_token=\(refreshToken)",
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.refreshFailed(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        try keychain.save(key: "accessToken", value: tokenResponse.access_token)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        try keychain.save(key: "expiresAt", value: String(expiresAt.timeIntervalSince1970))
        return tokenResponse.access_token
    }

    private func waitForRedirect() async throws -> String {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)

        return try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                    if let data = data, let request = String(data: data, encoding: .utf8) {
                        let lines = request.components(separatedBy: "\r\n")
                        if let firstLine = lines.first, firstLine.contains("GET") {
                            let components = firstLine.components(separatedBy: " ")
                            if components.count > 1 {
                                let url = components[1]
                                if let code = self.extractQueryParam(from: url, name: "code") {
                                    let response = "HTTP/1.1 200 OK\r\nContent-Length: 43\r\n\r\nAuthentication successful! You can close this."
                                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                                        connection.cancel()
                                        listener.cancel()
                                        continuation.resume(returning: code)
                                    }))
                                    return
                                }
                            }
                        }
                    }
                    if let error = error {
                        continuation.resume(throwing: error)
                    }
                }
            }
            listener.start(queue: .main)
        }
    }

    private func extractQueryParam(from url: String, name: String) -> String? {
        guard let urlComponents = URLComponents(string: "http://localhost\(url)") else { return nil }
        return urlComponents.queryItems?.first(where: { $0.name == name })?.value
    }

    private func exchangeCodeForToken(_ code: String, clientId: String, clientSecret: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code=\(code)",
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "redirect_uri=\(redirectUri)",
            "grant_type=authorization_code"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.refreshFailed(String(data: data, encoding: .utf8) ?? "Token exchange failed")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
