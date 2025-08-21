import Foundation

// Temporary type aliases for migration
typealias GmailError = AppError
typealias NetworkError = AppError
typealias AuthError = AppError

// Extension to maintain compatibility with old error creation patterns
extension AppError {
    static var notAuthenticated: AppError { .noAuthToken }
    // invalidURL already exists in AppError, no need to alias
    static var invalidMessageFormat: AppError { .invalidEmailFormat }
    static var invalidRecipient: AppError { .recipientRequired }
    static var invalidResponse: AppError { .custom("Invalid response") }
    
    // AuthError mappings
    static var invalidCallback: AppError { .custom("Invalid callback URL") }
    static var noCallbackURL: AppError { .custom("No callback URL received") }
    static var noAuthCode: AppError { .custom("No authorization code received") }
    static var noRefreshToken: AppError { .custom("No refresh token available") }
    
    
    static func fetchFailed(_ reason: String) -> AppError {
        .fetchFailed(NSError(domain: "Gmail", code: 0, userInfo: [NSLocalizedDescriptionKey: reason]))
    }
    
    static func sendFailed(_ reason: String) -> AppError {
        .messageSendFailed(reason)
    }
    
    static func decodingFailed(_ reason: String) -> AppError {
        .custom("Decoding failed: \(reason)")
    }
    
    static func unknown(_ error: Error) -> AppError {
        .networkError(error)
    }
}