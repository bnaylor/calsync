import Foundation
import Network
import AuthenticationServices

public actor GoogleAuthService {
    private let clientId: String
    private let clientSecret: String
    private let port: UInt16 = 8080
    private let redirectUri = "http://localhost:8080"
    
    struct TokenResponse: Codable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let scope: String
        let token_type: String
    }
    
    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
    
    public func authenticate() async throws -> String {
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
        return try await exchangeCodeForToken(code)
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
    
    private func exchangeCodeForToken(_ code: String) async throws -> String {
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
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GoogleAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(String(data: data, encoding: .utf8) ?? "")"])
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        // In a real app, we'd save the refresh token securely in Keychain
        return tokenResponse.access_token
    }
}
