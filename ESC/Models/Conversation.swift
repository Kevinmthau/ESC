import Foundation
import SwiftData

@Model
final class Conversation: @unchecked Sendable {
    var contactName: String  // Display name for single recipient, or "X, Y, Z" for groups
    var contactEmail: String  // Primary contact email for single, comma-separated for groups
    var participantEmailsString: String = ""  // All participant emails as comma-separated string
    var isGroupConversation: Bool = false  // True if multiple recipients
    
    // Computed property for array access - marked as @Transient to exclude from persistence
    @Transient var participantEmails: [String] {
        get { participantEmailsString.isEmpty ? [] : participantEmailsString.split(separator: ",").map { String($0) } }
        set { participantEmailsString = newValue.joined(separator: ",") }
    }
    var lastMessageTimestamp: Date
    var lastMessageSnippet: String
    var isRead: Bool
    var emails: [Email] = []
    
    init(
        contactName: String,
        contactEmail: String,
        participantEmails: [String] = [],
        isGroupConversation: Bool = false,
        lastMessageTimestamp: Date,
        lastMessageSnippet: String,
        isRead: Bool = false
    ) {
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.participantEmailsString = participantEmails.map { $0.lowercased() }.joined(separator: ",")
        self.isGroupConversation = isGroupConversation
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