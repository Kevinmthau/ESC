import Foundation
import SwiftData

// MARK: - Conversation Computed Properties
extension Conversation {
    
    // MARK: - Email Management
    
    /// Most recent email in the conversation
    var latestEmail: Email? {
        emails.max { $0.timestamp < $1.timestamp }
    }
    
    /// Oldest email in the conversation
    var oldestEmail: Email? {
        emails.min { $0.timestamp < $1.timestamp }
    }
    
    /// Unread emails in the conversation
    var unreadEmails: [Email] {
        emails.filter { !$0.isRead }
    }
    
    /// Count of unread emails
    var unreadCount: Int {
        unreadEmails.count
    }
    
    /// Check if conversation has unread emails
    var hasUnreadEmails: Bool {
        unreadCount > 0
    }
    
    // MARK: - Participant Management
    
    /// All unique participants in the conversation (normalized)
    var allParticipants: [String] {
        let participants = emails.flatMap { email in
            var people = email.allRecipients
            people.append(email.senderEmail)
            return people
        }
        return participants.map { $0.lowercased() }.uniqued()
    }
    
    /// Participants excluding the current user
    func participantsExcludingUser(_ userEmail: String) -> [String] {
        let normalized = userEmail.lowercased()
        return allParticipants.filter { $0 != normalized }
    }
    
    /// Display name for the conversation (handles groups)
    func displayName(userEmail: String) -> String {
        if isGroupConversation {
            let participants = participantsExcludingUser(userEmail)
            let names = participants.prefix(3).map { email in
                ContactsService.shared.getContactName(for: email) ?? email
            }
            
            if participants.count > 3 {
                return names.joined(separator: ", ") + " +\(participants.count - 3)"
            } else {
                return names.joined(separator: ", ")
            }
        } else {
            return contactName
        }
    }
    
    // MARK: - Content Helpers
    
    /// Generate a snippet from the latest email
    var snippet: String {
        guard let latest = latestEmail else { return "" }
        
        let content = latest.body.isEmpty ? latest.snippet : latest.body
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        return String(cleaned.prefix(100))
    }
    
    /// Check if conversation has attachments
    var hasAttachments: Bool {
        emails.contains { $0.hasAttachments }
    }
    
    /// Total attachment count across all emails
    var totalAttachmentCount: Int {
        emails.reduce(0) { $0 + $1.attachments.count }
    }
    
    // MARK: - Update Methods
    
    /// Update conversation metadata based on emails
    func updateMetadata() {
        guard let latest = latestEmail else { return }
        
        // Update timestamp
        lastMessageTimestamp = latest.timestamp
        
        // Update snippet
        lastMessageSnippet = snippet
        
        // Update read status
        isRead = !hasUnreadEmails
        
        // Update participant info for groups
        if isGroupConversation {
            let participants = allParticipants
            participantEmails = participants
        }
    }
    
    /// Add an email to the conversation
    @MainActor
    func addEmail(_ email: Email, in context: ModelContext) throws {
        email.conversation = self
        emails.append(email)
        updateMetadata()
        try context.save()
    }
    
    /// Remove an email from the conversation
    @MainActor
    func removeEmail(_ email: Email, in context: ModelContext) throws {
        emails.removeAll { $0.id == email.id }
        
        // If no emails left, delete the conversation
        if emails.isEmpty {
            context.delete(self)
        } else {
            updateMetadata()
        }
        
        try context.save()
    }
    
    /// Mark all emails as read
    @MainActor
    func markAllAsRead(in context: ModelContext) throws {
        for email in emails where !email.isRead {
            email.isRead = true
        }
        isRead = true
        try context.save()
    }
    
    // MARK: - Search
    
    /// Check if conversation matches search query
    func matches(searchQuery: String) -> Bool {
        let query = searchQuery.lowercased()
        
        // Check contact info
        if contactName.lowercased().contains(query) ||
           contactEmail.lowercased().contains(query) {
            return true
        }
        
        // Check participants for groups
        if isGroupConversation {
            for participant in participantEmails {
                if participant.lowercased().contains(query) {
                    return true
                }
            }
        }
        
        // Check email content
        for email in emails {
            if (email.subject ?? "").lowercased().contains(query) ||
               email.snippet.lowercased().contains(query) ||
               email.sender.lowercased().contains(query) {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Conversation Factory
extension Conversation {
    
    /// Create a conversation from an email
    @MainActor
    static func createFrom(email: Email, userEmail: String, in context: ModelContext) -> Conversation {
        let participants = email.allParticipants.filter { $0.lowercased() != userEmail.lowercased() }
        let isGroup = participants.count > 1
        
        let conversation = Conversation(
            contactName: isGroup ? "Group Conversation" : (email.isFromMe ? email.toRecipients.first ?? "" : email.sender),
            contactEmail: isGroup ? participants.sorted().joined(separator: ",") : participants.first ?? "",
            lastMessageTimestamp: email.timestamp,
            lastMessageSnippet: email.snippet
        )
        
        conversation.isGroupConversation = isGroup
        conversation.participantEmails = participants
        conversation.emails = [email]
        conversation.isRead = email.isRead
        
        email.conversation = conversation
        
        return conversation
    }
    
    /// Find or create a conversation for an email
    @MainActor
    static func findOrCreate(for email: Email, userEmail: String, in context: ModelContext) throws -> Conversation {
        let participants = email.allParticipants
            .filter { $0.lowercased() != userEmail.lowercased() }
            .map { $0.lowercased() }
            .sorted()
        
        let conversationKey = participants.joined(separator: ",")
        
        // Try to find existing conversation
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.contactEmail == conversationKey }
        )
        
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        
        // Create new conversation
        return createFrom(email: email, userEmail: userEmail, in: context)
    }
}