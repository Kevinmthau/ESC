import Foundation

enum ESCError: Error, LocalizedError {
    case authentication(AuthError)
    case gmail(GmailError)
    case network(NetworkError)
    case data(DataError)
    case contacts(ContactsError)
    
    var errorDescription: String? {
        switch self {
        case .authentication(let error):
            return error.errorDescription
        case .gmail(let error):
            return error.errorDescription
        case .network(let error):
            return error.errorDescription
        case .data(let error):
            return error.errorDescription
        case .contacts(let error):
            return error.errorDescription
        }
    }
}

enum AuthError: Error, LocalizedError {
    case invalidURL
    case noCallbackURL
    case invalidCallback
    case authenticationFailed(String)
    case noAuthCode
    case noRefreshToken
    case tokenExpired
    case invalidCredentials
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid authentication URL"
        case .noCallbackURL:
            return "No callback URL received"
        case .invalidCallback:
            return "Invalid callback URL format"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error)"
        case .noAuthCode:
            return "No authorization code received"
        case .noRefreshToken:
            return "No refresh token available"
        case .tokenExpired:
            return "Access token has expired"
        case .invalidCredentials:
            return "Invalid authentication credentials"
        }
    }
}

enum GmailError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidMessageFormat
    case sendFailed(String)
    case fetchFailed(String)
    case quotaExceeded
    case messageNotFound
    case invalidRecipient
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Gmail authentication required"
        case .invalidURL:
            return "Invalid Gmail API URL"
        case .invalidMessageFormat:
            return "Invalid email message format"
        case .sendFailed(let reason):
            return "Failed to send email: \(reason)"
        case .fetchFailed(let reason):
            return "Failed to fetch emails: \(reason)"
        case .quotaExceeded:
            return "Gmail API quota exceeded"
        case .messageNotFound:
            return "Email message not found"
        case .invalidRecipient:
            return "Invalid recipient email address"
        }
    }
}

enum NetworkError: Error, LocalizedError {
    case noInternet
    case timeout
    case serverError(Int)
    case invalidResponse
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .noInternet:
            return "No internet connection available"
        case .timeout:
            return "Request timed out"
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .invalidResponse:
            return "Invalid server response"
        case .unknown(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

enum DataError: Error, LocalizedError {
    case saveFailed
    case loadFailed
    case corruptedData
    case modelNotFound
    case duplicateEntry
    
    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save data"
        case .loadFailed:
            return "Failed to load data"
        case .corruptedData:
            return "Data is corrupted or invalid"
        case .modelNotFound:
            return "Requested data not found"
        case .duplicateEntry:
            return "Duplicate entry detected"
        }
    }
}

enum ContactsError: Error, LocalizedError {
    case accessDenied
    case notAvailable
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Contact access denied"
        case .notAvailable:
            return "Contacts not available"
        case .fetchFailed:
            return "Failed to fetch contacts"
        }
    }
}