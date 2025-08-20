import Foundation
import SwiftData

@MainActor
class DataSyncService: ObservableObject, DataSyncServiceProtocol {
    private let modelContext: ModelContext
    private let gmailService: GmailService
    private let contactsService: ContactsService
    private var syncTimer: Timer?
    
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var hasNewMessages = false
    
    // Notification for new messages
    static let newMessagesNotification = Notification.Name("DataSyncService.newMessages")
    
    init(modelContext: ModelContext, gmailService: GmailService, contactsService: ContactsService) {
        self.modelContext = modelContext
        self.gmailService = gmailService
        self.contactsService = contactsService
        
        // Migrate duplicate conversations, fix sender names, and update previews on init
        Task { @MainActor in
            await self.mergeDuplicateConversations()
            await self.fixSentEmailSenderNames()
            await self.updateAllConversationPreviews()
        }
        
        // Listen for message sent notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MessageSent"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleMessageSent()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    // MARK: - Migration
    
    func mergeDuplicateConversations() async {
        do {
            // Get all conversations
            let allConversations = try modelContext.fetch(FetchDescriptor<Conversation>())
            
            // Group conversations by normalized email
            var conversationGroups: [String: [Conversation]] = [:]
            for conversation in allConversations {
                let normalizedEmail = conversation.contactEmail.lowercased()
                if conversationGroups[normalizedEmail] == nil {
                    conversationGroups[normalizedEmail] = []
                }
                conversationGroups[normalizedEmail]?.append(conversation)
            }
            
            // Merge duplicate conversations
            for (email, conversations) in conversationGroups where conversations.count > 1 {
                print("🔀 Merging \(conversations.count) duplicate conversations for \(email)")
                
                // Sort by timestamp to keep the most recent as primary
                let sortedConversations = conversations.sorted { $0.lastMessageTimestamp > $1.lastMessageTimestamp }
                guard let primaryConversation = sortedConversations.first else { continue }
                
                // Update primary conversation email to normalized version
                primaryConversation.contactEmail = email
                
                // Merge emails from duplicate conversations into primary
                for duplicateConversation in sortedConversations.dropFirst() {
                    // Move all emails to the primary conversation
                    for email in duplicateConversation.emails {
                        email.conversation = primaryConversation
                        primaryConversation.emails.append(email)
                    }
                    
                    // Delete the duplicate conversation
                    modelContext.delete(duplicateConversation)
                }
                
                // Update primary conversation metadata
                if let latestEmail = primaryConversation.sortedEmails.last {
                    primaryConversation.lastMessageTimestamp = latestEmail.timestamp
                    primaryConversation.lastMessageSnippet = latestEmail.snippet
                    primaryConversation.isRead = primaryConversation.emails.allSatisfy { $0.isRead }
                }
            }
            
            // Now remove duplicate emails within each conversation
            await removeDuplicateEmails()
            
            // Save changes
            try modelContext.save()
            print("✅ Duplicate conversation merge complete")
            
        } catch {
            print("❌ Error merging duplicate conversations: \(error)")
        }
    }
    
    func fixSentEmailSenderNames() async {
        do {
            // Get user display name
            guard gmailService.isAuthenticated else { return }
            let userDisplayName = try? await gmailService.getUserDisplayName()
            guard let displayName = userDisplayName else { return }
            
            // Get all sent emails
            let descriptor = FetchDescriptor<Email>(
                predicate: #Predicate<Email> { email in
                    email.isFromMe == true
                }
            )
            let sentEmails = try modelContext.fetch(descriptor)
            
            var updatedCount = 0
            for email in sentEmails {
                // Update sender name if it's just an email address
                if email.sender == email.senderEmail || email.sender == "Me" {
                    email.sender = displayName
                    updatedCount += 1
                }
            }
            
            if updatedCount > 0 {
                try modelContext.save()
                print("✅ Updated sender name for \(updatedCount) sent emails to '\(displayName)'")
            }
            
        } catch {
            print("❌ Error fixing sender names: \(error)")
        }
    }
    
    func updateAllConversationPreviews() async {
        do {
            let allConversations = try modelContext.fetch(FetchDescriptor<Conversation>())
            var updatedCount = 0
            
            for conversation in allConversations {
                // Get the most recent email in the conversation
                // sortedEmails sorts by timestamp ascending, so last is newest
                if let latestEmail = conversation.sortedEmails.last {
                    // Always update to ensure we have the correct preview
                    conversation.lastMessageSnippet = latestEmail.snippet
                    conversation.lastMessageTimestamp = latestEmail.timestamp
                    updatedCount += 1
                    print("🔄 Updated preview for \(conversation.contactEmail) to: \(latestEmail.snippet.prefix(50))... (timestamp: \(latestEmail.timestamp))")
                } else if !conversation.emails.isEmpty {
                    // Fallback if sortedEmails doesn't work for some reason
                    let sortedEmails = conversation.emails.sorted { $0.timestamp < $1.timestamp }
                    if let latestEmail = sortedEmails.last {
                        conversation.lastMessageSnippet = latestEmail.snippet
                        conversation.lastMessageTimestamp = latestEmail.timestamp
                        updatedCount += 1
                        print("🔄 Updated preview (fallback) for \(conversation.contactEmail)")
                    }
                }
            }
            
            if updatedCount > 0 {
                try modelContext.save()
                print("✅ Updated previews for \(updatedCount) conversations to show most recent messages")
            }
            
        } catch {
            print("❌ Error updating conversation previews: \(error)")
        }
    }
    
    func removeDuplicateEmails() async {
        do {
            let allConversations = try modelContext.fetch(FetchDescriptor<Conversation>())
            
            for conversation in allConversations {
                var seenBodies = Set<String>()
                var emailsToRemove: [Email] = []
                
                // Sort emails by timestamp to keep the oldest version
                let sortedEmails = conversation.emails.sorted { $0.timestamp < $1.timestamp }
                
                for email in sortedEmails {
                    let normalizedBody = email.body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    
                    // Check if we've seen this exact message before (same recipient and body)
                    let messageKey = "\(email.recipientEmail.lowercased()):\(normalizedBody)"
                    
                    if seenBodies.contains(messageKey) {
                        print("🗑️ Removing duplicate email to \(email.recipientEmail): \(email.snippet.prefix(30))...")
                        emailsToRemove.append(email)
                    } else {
                        seenBodies.insert(messageKey)
                    }
                }
                
                // Remove duplicates
                for email in emailsToRemove {
                    conversation.emails.removeAll { $0.id == email.id }
                    modelContext.delete(email)
                }
                
                if !emailsToRemove.isEmpty {
                    print("✅ Removed \(emailsToRemove.count) duplicate emails from conversation with \(conversation.contactEmail)")
                    
                    // Update conversation metadata
                    if let latestEmail = conversation.sortedEmails.last {
                        conversation.lastMessageTimestamp = latestEmail.timestamp
                        conversation.lastMessageSnippet = latestEmail.snippet
                    }
                }
            }
            
            try modelContext.save()
            
        } catch {
            print("❌ Error removing duplicate emails: \(error)")
        }
    }
    
    // MARK: - Email Merging
    
    func mergeEmails(_ emails: [Email]) async {
        // This method is called to merge fetched emails into the database
        // The actual merging happens in syncData method
        // This is a placeholder for protocol conformance
        await syncData(silent: true)
    }
    
    // MARK: - Auto Sync
    
    func startAutoSync() {
        // Stop any existing timer
        stopAutoSync()
        
        // Track consecutive failures for backoff
        var consecutiveFailures = 0
        
        // Sync every 10 seconds for better responsiveness
        syncTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task { @MainActor in
                if self.gmailService.isAuthenticated && !self.isSyncing {
                    // Implement exponential backoff for consecutive failures
                    if consecutiveFailures > 0 {
                        let backoffInterval = min(60.0, 10.0 * pow(2.0, Double(consecutiveFailures - 1)))
                        if Date().timeIntervalSince(self.lastSyncTime ?? Date.distantPast) < backoffInterval {
                            print("⏸️ DataSyncService: Skipping sync due to backoff (failures: \(consecutiveFailures))")
                            return
                        }
                    }
                    
                    let syncStartTime = Date()
                    await self.syncData(silent: true)
                    
                    // Check if sync was successful by comparing timestamps
                    if self.lastSyncTime ?? Date.distantPast >= syncStartTime {
                        consecutiveFailures = 0
                    } else {
                        consecutiveFailures += 1
                        print("⚠️ DataSyncService: Sync may have failed, consecutive failures: \(consecutiveFailures)")
                    }
                }
            }
        }
        
        // Initial sync with loading indicator
        Task {
            await syncData(silent: false)
        }
    }
    
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    // MARK: - Conversation Management
    
    private func createConversationKey(for email: Email, userEmail: String) -> String {
        // For group conversations, create a key from all participants
        if email.allRecipients.count > 1 {
            var participants = Set(email.allRecipients)
            participants.insert(email.senderEmail.lowercased())
            participants.remove(userEmail.lowercased())  // Remove self from participants
            
            // Sort participants to ensure consistent key regardless of order
            let sortedParticipants = participants.sorted()
            return sortedParticipants.joined(separator: ",")
        } else {
            // For single recipient, use the contact email as before
            return email.isFromMe ? email.recipientEmail.lowercased() : email.senderEmail.lowercased()
        }
    }
    
    private func createConversationName(for email: Email, contactsService: ContactsService, userEmail: String) -> String {
        // For group conversations, concatenate names
        if email.allRecipients.count > 1 {
            var participantNames: [String] = []
            let userEmailLower = userEmail.lowercased()
            
            // Add sender if not from me
            if !email.isFromMe {
                let senderName = contactsService.getContactName(for: email.senderEmail) ?? email.sender
                participantNames.append(senderName)
            }
            
            // Add recipients (excluding self)
            for recipientEmail in email.allRecipients {
                // Skip if this is the user's email
                if recipientEmail.lowercased() == userEmailLower {
                    continue
                }
                
                if let name = contactsService.getContactName(for: recipientEmail) {
                    participantNames.append(name)
                } else {
                    // Extract name from email or use email itself
                    let emailParts = recipientEmail.split(separator: "@")
                    if let localPart = emailParts.first {
                        participantNames.append(String(localPart).replacingOccurrences(of: ".", with: " ").capitalized)
                    } else {
                        participantNames.append(recipientEmail)
                    }
                }
            }
            
            // Limit to first 3 names and add "and X more" if needed
            if participantNames.count > 3 {
                let firstThree = participantNames.prefix(3).joined(separator: ", ")
                return "\(firstThree) and \(participantNames.count - 3) more"
            } else {
                return participantNames.joined(separator: ", ")
            }
        } else {
            // Single recipient - use existing logic
            let contactEmail = email.isFromMe ? email.recipientEmail : email.senderEmail
            var contactName = email.isFromMe ? email.recipient : email.sender
            
            if let addressBookName = contactsService.getContactName(for: contactEmail) {
                contactName = addressBookName
            } else if contactName == contactEmail {
                let nameFromEmail = contactEmail.split(separator: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? contactEmail
                if nameFromEmail != contactEmail {
                    contactName = nameFromEmail
                }
            }
            
            return contactName
        }
    }
    
    // MARK: - Smart Sync
    
    func syncData(silent: Bool = false) async {
        guard !isSyncing else { return }
        
        if !silent {
            isSyncing = true
        }
        defer { 
            if !silent {
                isSyncing = false
            }
        }
        
        // Ensure we have the current user's email address
        var currentUserEmail = ""
        if gmailService.isAuthenticated {
            do {
                currentUserEmail = try await gmailService.getUserEmail()
                print("📧 DataSyncService: Syncing for user: \(currentUserEmail)")
                // Update the cached email in case it was stale
                gmailService.cachedUserEmail = currentUserEmail
            } catch {
                print("❌ DataSyncService: Failed to get user email: \(error)")
                return
            }
        }
        
        do {
            // Fetch new emails from Gmail (attachments are fetched in GmailService.fetchEmails)
            let fetchedEmails = try await gmailService.fetchEmails()
            
            // Get existing conversations and update their names if needed
            let existingConversations = try modelContext.fetch(FetchDescriptor<Conversation>())
            var conversationMap: [String: Conversation] = [:]
            for conversation in existingConversations {
                // Use lowercase email as key for case-insensitive matching
                conversationMap[conversation.contactEmail.lowercased()] = conversation
                
                // Update conversation name if we have a better one from contacts
                if let addressBookName = contactsService.getContactName(for: conversation.contactEmail),
                   conversation.contactName != addressBookName {
                    print("🔄 DataSyncService: Updating conversation name from '\(conversation.contactName)' to '\(addressBookName)'")
                    conversation.contactName = addressBookName
                }
            }
            
            // Get existing email IDs to avoid duplicates
            let existingEmails = try modelContext.fetch(FetchDescriptor<Email>())
            let existingEmailIds = Set(existingEmails.map { $0.id })
            var newMessageCount = 0
            
            // Process fetched emails
            for email in fetchedEmails {
                // Skip if we already have this email (check by Gmail ID)
                if existingEmailIds.contains(email.id) {
                    continue
                }
                
                // For sent messages, check if we recently created a local copy
                if email.isFromMe {
                    let recentCutoff = Date().addingTimeInterval(-300) // Within last 5 minutes
                    
                    // Find matching local emails that could be duplicates
                    let matchingLocalEmails = existingEmails.filter { existingEmail in
                        existingEmail.isFromMe &&
                        existingEmail.recipientEmail == email.recipientEmail &&
                        existingEmail.timestamp > recentCutoff &&
                        existingEmail.id != email.id
                    }
                    
                    // Check if any match by content (comparing cleaned versions)
                    let cleanedNewBody = email.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasRecentLocal = matchingLocalEmails.contains { existingEmail in
                        let cleanedExistingBody = existingEmail.body.trimmingCharacters(in: .whitespacesAndNewlines)
                        return cleanedExistingBody == cleanedNewBody
                    }
                    
                    if hasRecentLocal {
                        print("⏭️ DataSyncService: Found duplicate sent message to \(email.recipientEmail) with body: \(email.snippet.prefix(30))...")
                        
                        // Find and remove the local copy to replace with the synced version
                        if let localCopy = matchingLocalEmails.first(where: { 
                            $0.body.trimmingCharacters(in: .whitespacesAndNewlines) == cleanedNewBody 
                        }) {
                            print("🔄 DataSyncService: Replacing local copy \(localCopy.id) with synced message \(email.id)")
                            
                            // Remove the local copy from the conversation
                            if let conversation = localCopy.conversation {
                                conversation.emails.removeAll { $0.id == localCopy.id }
                            }
                            
                            // Delete the local copy
                            modelContext.delete(localCopy)
                        }
                        
                        // Now add the synced version with the proper Gmail message ID
                        // This continues below to add the email normally
                    }
                }
                
                // Use the current user email we fetched at the start
                let userEmail = currentUserEmail.isEmpty ? (gmailService.cachedUserEmail ?? "") : currentUserEmail
                
                // Find or create conversation based on participants
                let conversationKey = createConversationKey(for: email, userEmail: userEmail)
                let conversationName = createConversationName(for: email, contactsService: contactsService, userEmail: userEmail)
                let isGroupConversation = email.allRecipients.count > 1
                
                print("🔍 DataSyncService: Processing email with \(email.allRecipients.count) recipients")
                if isGroupConversation {
                    print("👥 Group conversation key: \(conversationKey)")
                    print("👥 Group conversation name: \(conversationName)")
                }
                
                let conversation: Conversation
                if let existing = conversationMap[conversationKey] {
                    conversation = existing
                    // Update the name if group participants changed
                    if isGroupConversation && existing.contactName != conversationName {
                        existing.contactName = conversationName
                    }
                } else {
                    // Create participant list for group conversations
                    var participantEmails: [String] = []
                    if isGroupConversation {
                        participantEmails = email.allRecipients + [email.senderEmail.lowercased()]
                        participantEmails = Array(Set(participantEmails).subtracting([userEmail.lowercased()]))
                    }
                    
                    conversation = Conversation(
                        contactName: conversationName,
                        contactEmail: conversationKey,  // Use conversation key
                        participantEmails: participantEmails,
                        isGroupConversation: isGroupConversation,
                        lastMessageTimestamp: email.timestamp,
                        lastMessageSnippet: email.snippet,
                        isRead: email.isRead
                    )
                    modelContext.insert(conversation)
                    conversationMap[conversationKey] = conversation
                }
                
                // Add email to conversation (this will set the bidirectional relationship)
                conversation.addEmail(email)
                modelContext.insert(email)
                
                // Insert attachments too
                for attachment in email.attachments {
                    modelContext.insert(attachment)
                }
                
                newMessageCount += 1
                
                // Update read status for received messages
                if !email.isFromMe && !email.isRead {
                    conversation.isRead = false
                }
            }
            
            // After processing all emails, update conversation previews to show the most recent message
            for (_, conversation) in conversationMap {
                if let latestEmail = conversation.sortedEmails.last {
                    conversation.lastMessageTimestamp = latestEmail.timestamp
                    conversation.lastMessageSnippet = latestEmail.snippet
                    print("📊 Final preview for \(conversation.contactEmail): \(latestEmail.snippet.prefix(30))...")
                }
            }
            
            try modelContext.save()
            lastSyncTime = Date()
            
            // Notify if we have new messages
            if newMessageCount > 0 {
                hasNewMessages = true
                NotificationCenter.default.post(name: DataSyncService.newMessagesNotification, object: nil)
                
                // Notify about conversation updates for UI refresh
                for conversation in conversationMap.values {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ConversationUpdated"),
                        object: conversation
                    )
                }
                print("📢 DataSyncService: Posted ConversationUpdated notifications for \(conversationMap.count) conversations")
            }
            
        } catch {
            // Log error with more context
            if let networkError = error as? NetworkError {
                print("🔴 DataSyncService: Network error during sync: \(networkError)")
            } else if let gmailError = error as? GmailError {
                print("🔴 DataSyncService: Gmail API error: \(gmailError)")
            } else {
                print("🔴 DataSyncService: Sync error: \(error)")
            }
            
            // Don't stop auto-sync for transient errors
            // The next sync attempt will retry
        }
    }
    
    // MARK: - Immediate Actions
    
    func handleMessageSent() {
        // After sending a message, we don't need to do a full sync
        // The local state is already updated
        // Just mark the sync time
        lastSyncTime = Date()
        
        // Don't sync immediately after sending to avoid duplicates
        // The next regular sync will pick up any server-side changes
    }
    
    func handleConversationOpened(_ conversation: Conversation) {
        // Mark conversation as read locally
        conversation.isRead = true
        
        // Update Gmail read status in background
        Task {
            for email in conversation.emails where !email.isRead {
                // TODO: Call Gmail API to mark as read
                email.isRead = true
            }
            try? modelContext.save()
        }
    }
}