import Foundation

/// Comprehensive error types for the ESC application
enum AppError: LocalizedError {
    // MARK: - Authentication Errors
    case authenticationFailed(String)
    case tokenExpired
    case noAuthToken
    case invalidCredentials
    
    // MARK: - Network Errors
    case networkError(Error)
    case noInternetConnection
    case serverError(statusCode: Int)
    case requestTimeout
    case invalidURL
    
    // MARK: - Gmail API Errors
    case gmailAPIError(String)
    case messageSendFailed(String)
    case messageNotFound
    case quotaExceeded
    case invalidEmailFormat
    
    // MARK: - Data Errors
    case dataCorrupted
    case saveFailed(Error)
    case fetchFailed(Error)
    case deleteFailed(Error)
    case duplicateEntry
    
    // MARK: - Validation Errors
    case invalidEmail(String)
    case emptyMessage
    case recipientRequired
    case attachmentTooLarge(maxSize: Int)
    case unsupportedFileType(String)
    
    // MARK: - UI Errors
    case viewModelNotInitialized
    case invalidState(String)
    
    // MARK: - Generic Errors
    case unknown
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        // Authentication
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .noAuthToken:
            return "No authentication token found. Please sign in."
        case .invalidCredentials:
            return "Invalid credentials. Please check your email and password."
            
        // Network
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noInternetConnection:
            return "No internet connection. Please check your network settings."
        case .serverError(let statusCode):
            return "Server error (code: \(statusCode)). Please try again later."
        case .requestTimeout:
            return "Request timed out. Please try again."
        case .invalidURL:
            return "Invalid URL format."
            
        // Gmail API
        case .gmailAPIError(let message):
            return "Gmail API error: \(message)"
        case .messageSendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .messageNotFound:
            return "Message not found."
        case .quotaExceeded:
            return "Gmail API quota exceeded. Please try again later."
        case .invalidEmailFormat:
            return "Invalid email format."
            
        // Data
        case .dataCorrupted:
            return "Data is corrupted and cannot be read."
        case .saveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete data: \(error.localizedDescription)"
        case .duplicateEntry:
            return "This entry already exists."
            
        // Validation
        case .invalidEmail(let email):
            return "Invalid email address: \(email)"
        case .emptyMessage:
            return "Message cannot be empty."
        case .recipientRequired:
            return "Please add at least one recipient."
        case .attachmentTooLarge(let maxSize):
            return "Attachment is too large. Maximum size is \(maxSize) MB."
        case .unsupportedFileType(let type):
            return "Unsupported file type: \(type)"
            
        // UI
        case .viewModelNotInitialized:
            return "View model is not properly initialized."
        case .invalidState(let description):
            return "Invalid state: \(description)"
            
        // Generic
        case .unknown:
            return "An unknown error occurred."
        case .custom(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authenticationFailed, .tokenExpired, .noAuthToken, .invalidCredentials:
            return "Try signing in again with your Google account."
        case .noInternetConnection:
            return "Check your Wi-Fi or cellular data connection."
        case .serverError, .requestTimeout:
            return "Wait a moment and try again."
        case .quotaExceeded:
            return "You've reached the Gmail API limit. Wait a few minutes before trying again."
        case .attachmentTooLarge:
            return "Try compressing the file or sending it via Google Drive."
        case .emptyMessage:
            return "Type a message or add an attachment before sending."
        case .recipientRequired:
            return "Add at least one recipient in the To field."
        default:
            return nil
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkError, .noInternetConnection, .serverError, .requestTimeout, .quotaExceeded:
            return true
        default:
            return false
        }
    }
    
    var requiresReauthentication: Bool {
        switch self {
        case .authenticationFailed, .tokenExpired, .noAuthToken, .invalidCredentials:
            return true
        default:
            return false
        }
    }
}

// MARK: - Result Extension
extension Result where Failure == AppError {
    /// Converts a throwing closure into a Result type
    static func from(_ closure: () throws -> Success) -> Result<Success, AppError> {
        do {
            return .success(try closure())
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }
    }
    
    /// Executes success handler if result is success
    @discardableResult
    func onSuccess(_ handler: (Success) -> Void) -> Result<Success, AppError> {
        if case .success(let value) = self {
            handler(value)
        }
        return self
    }
    
    /// Executes failure handler if result is failure
    @discardableResult
    func onFailure(_ handler: (AppError) -> Void) -> Result<Success, AppError> {
        if case .failure(let error) = self {
            handler(error)
        }
        return self
    }
}

// MARK: - Error Handler Protocol
protocol ErrorHandler {
    func handle(_ error: AppError)
    func handleWithRetry(_ error: AppError, retry: @escaping () -> Void)
}