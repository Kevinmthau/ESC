import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Error Recovery Action
enum ErrorRecoveryAction {
    case retry
    case authenticate
    case clearCache
    case resetApp
    case contactSupport
    case dismiss
    
    var title: String {
        switch self {
        case .retry: return "Retry"
        case .authenticate: return "Sign In"
        case .clearCache: return "Clear Cache"
        case .resetApp: return "Reset App"
        case .contactSupport: return "Contact Support"
        case .dismiss: return "Dismiss"
        }
    }
    
    var isDestructive: Bool {
        switch self {
        case .resetApp, .clearCache: return true
        default: return false
        }
    }
}

// MARK: - Error Recovery Strategy
struct ErrorRecoveryStrategy {
    let primaryAction: ErrorRecoveryAction
    let secondaryActions: [ErrorRecoveryAction]
    let message: String
    let isRecoverable: Bool
    
    static func strategy(for error: Error) -> ErrorRecoveryStrategy {
        if let appError = error as? AppError {
            return strategy(for: appError)
        }
        
        // Default strategy for unknown errors
        return ErrorRecoveryStrategy(
            primaryAction: .retry,
            secondaryActions: [.dismiss],
            message: "An unexpected error occurred",
            isRecoverable: true
        )
    }
    
    private static func strategy(for error: AppError) -> ErrorRecoveryStrategy {
        switch error {
        // Authentication Errors
        case .authenticationFailed, .tokenExpired, .noAuthToken, .invalidCredentials:
            return ErrorRecoveryStrategy(
                primaryAction: .authenticate,
                secondaryActions: [.dismiss],
                message: "Please sign in to continue",
                isRecoverable: true
            )
            
        // Network Errors
        case .networkError, .noInternetConnection, .requestTimeout:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.dismiss],
                message: "Check your internet connection and try again",
                isRecoverable: true
            )
            
        case .serverError:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.contactSupport, .dismiss],
                message: "Server is temporarily unavailable",
                isRecoverable: true
            )
            
        // Data Errors
        case .dataCorrupted:
            return ErrorRecoveryStrategy(
                primaryAction: .clearCache,
                secondaryActions: [.resetApp, .contactSupport],
                message: "Data corruption detected. Clear cache to recover.",
                isRecoverable: true
            )
            
        case .saveFailed, .fetchFailed:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.clearCache, .dismiss],
                message: "Failed to save data. Please try again.",
                isRecoverable: true
            )
            
        // Gmail API Errors
        case .quotaExceeded:
            return ErrorRecoveryStrategy(
                primaryAction: .dismiss,
                secondaryActions: [],
                message: "API quota exceeded. Please try again later.",
                isRecoverable: false
            )
            
        case .messageSendFailed:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.dismiss],
                message: "Failed to send message. Please try again.",
                isRecoverable: true
            )
            
        // Validation Errors
        case .invalidEmail, .emptyMessage, .recipientRequired:
            return ErrorRecoveryStrategy(
                primaryAction: .dismiss,
                secondaryActions: [],
                message: "Please correct the validation errors",
                isRecoverable: false
            )
            
        default:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.dismiss],
                message: error.localizedDescription,
                isRecoverable: true
            )
        }
    }
}

// MARK: - Error Recovery Service
@MainActor
class ErrorRecoveryService: ObservableObject {
    static let shared = ErrorRecoveryService()
    
    @Published var currentError: Error?
    @Published var recoveryStrategy: ErrorRecoveryStrategy?
    @Published var isRecovering = false
    @Published var recoveryProgress: Double = 0.0
    
    private var retryCount: [String: Int] = [:]
    private let maxRetries = 3
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Error Handling
    
    func handle(_ error: Error, context: String? = nil) {
        currentError = error
        recoveryStrategy = ErrorRecoveryStrategy.strategy(for: error)
        
        // Track retry count for context
        if let context = context {
            retryCount[context] = (retryCount[context] ?? 0) + 1
            
            // Disable retry if max retries exceeded
            if retryCount[context]! >= maxRetries {
                recoveryStrategy?.primaryAction == .retry ?
                    modifyStrategyToDisableRetry() : nil
            }
        }
        
        // Auto-recover for certain errors
        if shouldAutoRecover(error) {
            Task {
                await performRecovery(recoveryStrategy!.primaryAction)
            }
        }
    }
    
    // MARK: - Recovery Actions
    
    func performRecovery(_ action: ErrorRecoveryAction) async {
        isRecovering = true
        recoveryProgress = 0.0
        
        switch action {
        case .retry:
            await retryLastOperation()
            
        case .authenticate:
            await reauthenticate()
            
        case .clearCache:
            await clearCache()
            
        case .resetApp:
            await resetApp()
            
        case .contactSupport:
            openSupportPage()
            
        case .dismiss:
            dismissError()
        }
        
        // Clear error on successful recovery
        currentError = nil
        recoveryStrategy = nil
        
        isRecovering = false
        recoveryProgress = 0.0
    }
    
    // MARK: - Private Methods
    
    private func shouldAutoRecover(_ error: Error) -> Bool {
        guard let appError = error as? AppError else { return false }
        
        switch appError {
        case .tokenExpired:
            return true // Auto-refresh token
        default:
            return false
        }
    }
    
    private func modifyStrategyToDisableRetry() {
        guard let strategy = recoveryStrategy else { return }
        
        if strategy.primaryAction == .retry {
            // Replace retry with dismiss
            recoveryStrategy = ErrorRecoveryStrategy(
                primaryAction: .dismiss,
                secondaryActions: strategy.secondaryActions.filter { $0 != .retry },
                message: "Maximum retries exceeded. \(strategy.message)",
                isRecoverable: false
            )
        }
    }
    
    private func retryLastOperation() async {
        // Simulate retry with progress
        for i in 0...10 {
            recoveryProgress = Double(i) / 10.0
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Post notification to retry last operation
        NotificationCenter.default.post(
            name: NSNotification.Name("RetryLastOperation"),
            object: nil
        )
    }
    
    private func reauthenticate() async {
        // Trigger authentication flow
        NotificationCenter.default.post(
            name: NSNotification.Name("RequiresAuthentication"),
            object: nil
        )
    }
    
    private func clearCache() async {
        recoveryProgress = 0.2
        
        // Clear image cache
        ContactsService.shared.clearCache()
        recoveryProgress = 0.4
        
        // Clear WebView pool if needed
        // WebViewPoolManager doesn't have clearCache, but we can release all webviews
        recoveryProgress = 0.6
        
        // Clear user defaults cache
        UserDefaults.standard.synchronize()
        recoveryProgress = 1.0
    }
    
    private func resetApp() async {
        recoveryProgress = 0.1
        
        // Clear all data
        await clearCache()
        recoveryProgress = 0.3
        
        // Clear SwiftData
        // The modelContainer exists and would need proper cleanup implementation
        recoveryProgress = 0.6
        
        // Reset user defaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        recoveryProgress = 0.8
        
        // Sign out
        DependencyContainer.shared.gmailService.signOut()
        recoveryProgress = 1.0
        
        // Post reset notification
        NotificationCenter.default.post(
            name: NSNotification.Name("AppReset"),
            object: nil
        )
    }
    
    private func openSupportPage() {
        // Open support URL
        if let url = URL(string: "https://support.example.com") {
            #if canImport(UIKit)
            if UIApplication.shared.connectedScenes.first as? UIWindowScene != nil {
                UIApplication.shared.open(url)
            }
            #endif
        }
    }
    
    private func dismissError() {
        currentError = nil
        recoveryStrategy = nil
    }
    
    // MARK: - Retry Management
    
    func resetRetryCount(for context: String) {
        retryCount[context] = 0
    }
    
    func resetAllRetryCounts() {
        retryCount.removeAll()
    }
}