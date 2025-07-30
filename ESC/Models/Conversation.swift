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
        emails.append(email)
        
        // Update conversation metadata
        if email.timestamp > lastMessageTimestamp {
            lastMessageTimestamp = email.timestamp
            lastMessageSnippet = email.snippet
        }
        
        if !email.isRead {
            isRead = false
        }
    }
    
    var sortedEmails: [Email] {
        emails.sorted { $0.timestamp < $1.timestamp }
    }
}