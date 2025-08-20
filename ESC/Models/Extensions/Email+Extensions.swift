import Foundation
import SwiftData

// MARK: - Email Computed Properties
extension Email {
    
    // MARK: - Participant Helpers
    
    /// All participants in the email (sender + recipients)
    var allParticipants: [String] {
        var participants = allRecipients
        participants.append(senderEmail.lowercased())
        return participants.uniqued()
    }
    
    /// Get display names for recipients
    func displayName(for email: String) -> String {
        ContactsService.shared.getContactName(for: email) ?? email
    }
    
    // MARK: - Reply Helpers
    
    /// Recipients for a reply (original sender + CC, excluding self)
    func replyRecipients(userEmail: String) -> (to: [String], cc: [String]) {
        let normalizedUserEmail = userEmail.lowercased()
        
        // Reply to sender
        let replyTo = [senderEmail]
        
        // Include original recipients in CC (excluding self)
        let replyCc = (toRecipients + ccRecipients)
            .filter { $0.lowercased() != normalizedUserEmail }
            .filter { $0.lowercased() != senderEmail.lowercased() }
        
        return (to: replyTo, cc: replyCc.uniqued())
    }
    
    /// Recipients for reply-all (all original participants excluding self)
    func replyAllRecipients(userEmail: String) -> (to: [String], cc: [String]) {
        let normalizedUserEmail = userEmail.lowercased()
        
        // Original sender goes to "To"
        let replyTo = [senderEmail]
        
        // All other recipients go to CC (excluding self and sender)
        let replyCc = allRecipients
            .filter { $0.lowercased() != normalizedUserEmail }
            .filter { $0.lowercased() != senderEmail.lowercased() }
        
        return (to: replyTo, cc: replyCc.uniqued())
    }
    
    // MARK: - Content Helpers
    
    /// Get the best available content for display
    var displayContent: String {
        // Prefer HTML if available and not empty
        if let html = htmlBody, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return html
        }
        // Fall back to body text
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        // Use snippet as last resort
        return snippet
    }
    
    /// Check if email has attachments
    var hasAttachments: Bool {
        !attachments.isEmpty
    }
    
    /// Total size of all attachments
    var totalAttachmentSize: Int64 {
        attachments.reduce(Int64(0)) { $0 + Int64($1.size) }
    }
    
    /// Formatted total attachment size
    var formattedTotalAttachmentSize: String {
        ByteCountFormatter.string(fromByteCount: totalAttachmentSize, countStyle: .file)
    }
    
    // MARK: - Thread Helpers
    
    /// Check if this is part of a thread
    var isThreaded: Bool {
        inReplyToMessageId != nil || threadId != nil
    }
    
    /// Get the root message ID for threading
    var threadRootId: String? {
        // Use thread ID if available
        if let threadId = threadId {
            return threadId
        }
        // Otherwise, use in-reply-to
        return inReplyToMessageId
    }
    
    // MARK: - Status Helpers
    
    /// Check if email needs sync
    var needsSync: Bool {
        // Add logic for determining if email needs to be synced
        return false
    }
    
    /// Mark email as read and save
    @MainActor
    func markAsRead(in context: ModelContext) throws {
        guard !isRead else { return }
        isRead = true
        try context.save()
    }
    
    /// Mark email as unread and save
    @MainActor
    func markAsUnread(in context: ModelContext) throws {
        guard isRead else { return }
        isRead = false
        try context.save()
    }
}

// MARK: - Array Helpers
extension Array where Element == String {
    /// Remove duplicates while preserving order
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { element in
            let normalized = element.lowercased()
            if seen.contains(normalized) {
                return false
            }
            seen.insert(normalized)
            return true
        }
    }
}