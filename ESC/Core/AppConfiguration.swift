import Foundation

enum AppConfiguration {
    
    enum Sync {
        static let pollingInterval: TimeInterval = 10.0
        static let duplicateWindowMinutes = 5
        static let maxRetries = 3
        static let retryDelay: TimeInterval = 2.0
    }
    
    enum UI {
        static let maxContactsShown = 10
        static let messagePreviewLength = 100
        static let scrollDebounceInterval: TimeInterval = 0.3
        static let keyboardAnimationDuration: TimeInterval = 0.25
        static let bottomSpacerHeight: CGFloat = 50
        static let minMessageBubbleWidth: CGFloat = 50
        static let maxMessageBubbleWidthRatio: CGFloat = 0.75
    }
    
    enum Gmail {
        static let scopes = ["https://www.googleapis.com/auth/gmail.modify",
                             "https://www.googleapis.com/auth/gmail.send",
                             "https://www.googleapis.com/auth/userinfo.profile"]
        static let maxResults = 100
        static let labelIds = ["UNREAD", "INBOX"]
        static let quotaRetryDelay: TimeInterval = 60.0
    }
    
    enum Storage {
        static let maxAttachmentSize = 25 * 1024 * 1024 // 25MB
        static let cacheExpirationDays = 7
        static let maxCachedContacts = 500
    }
    
    enum Validation {
        static let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        static let minSubjectLength = 0
        static let maxSubjectLength = 500
        static let maxBodyLength = 100_000
    }
    
    enum Animation {
        static let defaultDuration: TimeInterval = 0.3
        static let quickDuration: TimeInterval = 0.15
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.8
    }
}