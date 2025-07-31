import Foundation
import AuthenticationServices
import SafariServices
import UIKit

class GoogleAuthManager: NSObject, ObservableObject {
    static let shared = GoogleAuthManager()
    
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var refreshToken: String?
    
    private let clientId = "999923476073-b4m4r3o96gv30rqmo71qo210oa46au74.apps.googleusercontent.com"
    private let clientSecret = "" // Not needed for iOS
    private let redirectUri = "com.googleusercontent.apps.999923476073-b4m4r3o96gv30rqmo71qo210oa46au74:/oauth"
    private let scope = "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.send"
    
    private var authSession: ASWebAuthenticationSession?
    
    // UserDefaults keys for persistent storage
    private let accessTokenKey = "GoogleAuth.AccessToken"
    private let refreshTokenKey = "GoogleAuth.RefreshToken"
    private let isAuthenticatedKey = "GoogleAuth.IsAuthenticated"
    
    private override init() {
        super.init()
        loadStoredTokens()
    }
    
    @MainActor
    func authenticate() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.startAuthFlow { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func startAuthFlow(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let authURL = buildAuthURL() else {
            completion(.failure(AuthError.invalidURL))
            return
        }
        
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "com.googleusercontent.apps.999923476073-b4m4r3o96gv30rqmo71qo210oa46au74"
        ) { [weak self] callbackURL, error in
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let callbackURL = callbackURL else {
                completion(.failure(AuthError.noCallbackURL))
                return
            }
            
            self?.handleAuthCallback(url: callbackURL, completion: completion)
        }
        
        authSession?.presentationContextProvider = self
        authSession?.start()
    }
    
    private func buildAuthURL() -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }
    
    private func handleAuthCallback(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            completion(.failure(AuthError.invalidCallback))
            return
        }
        
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            completion(.failure(AuthError.authenticationFailed(error)))
            return
        }
        
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            completion(.failure(AuthError.noAuthCode))
            return
        }
        
        Task {
            do {
                try await self.exchangeCodeForTokens(code: code)
                await MainActor.run {
                    print("🔑 GoogleAuthManager: Authentication successful! Setting isAuthenticated = true")
                    self.isAuthenticated = true
                    print("🔑 GoogleAuthManager: isAuthenticated is now: \(self.isAuthenticated)")
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func exchangeCodeForTokens(code: String) async throws {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            self.isAuthenticated = true
            print("🔑 GoogleAuthManager: Tokens received - access token: \(tokenResponse.accessToken.prefix(20))...")
            print("🔑 GoogleAuthManager: Setting isAuthenticated to true")
            self.saveTokens()
        }
    }
    
    func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw AuthError.noRefreshToken
        }
        
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "grant_type": "refresh_token"
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = tokenResponse.accessToken
            if let newRefreshToken = tokenResponse.refreshToken {
                self.refreshToken = newRefreshToken
            }
            self.isAuthenticated = true
            self.saveTokens()
        }
    }
    
    func signOut() {
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        clearStoredTokens()
    }
    
    // MARK: - Persistent Storage
    
    private func loadStoredTokens() {
        let userDefaults = UserDefaults.standard
        
        self.accessToken = userDefaults.string(forKey: accessTokenKey)
        self.refreshToken = userDefaults.string(forKey: refreshTokenKey)
        self.isAuthenticated = userDefaults.bool(forKey: isAuthenticatedKey)
        
        print("🔑 GoogleAuthManager: Loaded stored auth state - isAuthenticated: \(isAuthenticated)")
        if let token = accessToken {
            print("🔑 GoogleAuthManager: Found stored access token: \(token.prefix(20))...")
        }
        
        // If we have tokens, try to validate and refresh them
        if accessToken != nil && refreshToken != nil {
            print("🔑 GoogleAuthManager: Found stored tokens, attempting to refresh...")
            Task {
                do {
                    try await refreshAccessToken()
                    print("🔑 GoogleAuthManager: Successfully refreshed stored tokens")
                } catch {
                    print("🔑 GoogleAuthManager: Failed to refresh stored tokens: \(error)")
                    await MainActor.run {
                        self.signOut()
                    }
                }
            }
        } else if accessToken != nil {
            // We have an access token but no refresh token - consider it valid for now
            print("🔑 GoogleAuthManager: Found access token without refresh token, marking as authenticated")
            self.isAuthenticated = true
        }
    }
    
    private func saveTokens() {
        let userDefaults = UserDefaults.standard
        
        userDefaults.set(accessToken, forKey: accessTokenKey)
        userDefaults.set(refreshToken, forKey: refreshTokenKey)
        userDefaults.set(isAuthenticated, forKey: isAuthenticatedKey)
        
        print("🔑 GoogleAuthManager: Saved authentication state to UserDefaults")
    }
    
    private func clearStoredTokens() {
        let userDefaults = UserDefaults.standard
        
        userDefaults.removeObject(forKey: accessTokenKey)
        userDefaults.removeObject(forKey: refreshTokenKey)
        userDefaults.removeObject(forKey: isAuthenticatedKey)
        
        print("🔑 GoogleAuthManager: Cleared stored authentication state")
    }
}

extension GoogleAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

enum AuthError: Error, LocalizedError {
    case invalidURL
    case noCallbackURL
    case invalidCallback
    case authenticationFailed(String)
    case noAuthCode
    case noRefreshToken
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noCallbackURL:
            return "No callback URL received"
        case .invalidCallback:
            return "Invalid callback URL"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error)"
        case .noAuthCode:
            return "No authorization code received"
        case .noRefreshToken:
            return "No refresh token available"
        }
    }
}