import Foundation
import SwiftData

@Model
final class Conversation: @unchecked Sendable {
    var contactName: String
    var contactEmail: String
    var lastMessageTimestamp: Date
    var lastMessageSnippet: String
    var isRead: Bool
    var emails: [Email] = []
    
    init(
        contactName: String,
        contactEmail: String,
        lastMessageTimestamp: Date,
        lastMessageSnippet: String,
        isRead: Bool = false
    ) {
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.lastMessageTimestamp = lastMessageTimestamp
        self.lastMessageSnippet = lastMessageSnippet
        self.isRead = isRead
    }
    
    func addEmail(_ email: Email) {
        // Establish the bidirectional relationship
        email.conversation = self
        emails.append(email)
        print("📨 Added email \(email.id) to conversation. Total emails: \(emails.count)")
        
        // Always update conversation metadata to ensure it moves to top
        lastMessageTimestamp = email.timestamp
        lastMessageSnippet = email.snippet
        print("🕐 Conversation timestamp updated to: \(email.timestamp)")
        
        if !email.isRead {
            isRead = false
        }
    }
    
    var sortedEmails: [Email] {
        emails.sorted { $0.timestamp < $1.timestamp }
    }
}