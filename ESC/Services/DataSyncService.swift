import Foundation
import SwiftData

@MainActor
class DataSyncService: ObservableObject {
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
    }
    
    // MARK: - Auto Sync
    
    func startAutoSync() {
        // Stop any existing timer
        stopAutoSync()
        
        // Sync every 10 seconds for better responsiveness
        syncTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task { @MainActor in
                if self.gmailService.isAuthenticated && !self.isSyncing {
                    await self.syncData(silent: true)
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
        
        do {
            // Fetch new emails from Gmail
            let fetchedEmails = try await gmailService.fetchEmails()
            
            // Get existing conversations and update their names if needed
            let existingConversations = try modelContext.fetch(FetchDescriptor<Conversation>())
            var conversationMap: [String: Conversation] = [:]
            for conversation in existingConversations {
                conversationMap[conversation.contactEmail] = conversation
                
                // Update conversation name if we have a better one from contacts
                if let addressBookName = contactsService.getContactName(for: conversation.contactEmail),
                   conversation.contactName != addressBookName {
                    print("🔄 DataSyncService: Updating conversation name from '\(conversation.contactName)' to '\(addressBookName)'")
                    conversation.contactName = addressBookName
                }
            }
            
            // Get existing email IDs to avoid duplicates
            let existingEmails = try modelContext.fetch(FetchDescriptor<Email>())
            let existingEmailIds = Set(existingEmails.map { $0.messageId })
            var newMessageCount = 0
            
            // Process fetched emails
            for email in fetchedEmails {
                // Skip if we already have this email
                if existingEmailIds.contains(email.messageId) {
                    continue
                }
                
                // Find or create conversation
                let contactEmail = email.isFromMe ? email.recipientEmail : email.senderEmail
                var contactName = email.isFromMe ? email.recipient : email.sender
                
                // Try to get the contact name from the address book
                print("🔍 DataSyncService: Looking up name for email: \(contactEmail), current name: \(contactName)")
                if let addressBookName = contactsService.getContactName(for: contactEmail) {
                    print("✅ DataSyncService: Using address book name: \(addressBookName)")
                    contactName = addressBookName
                } else if contactName == contactEmail {
                    // If the name is just the email, try to extract a better name
                    let nameFromEmail = contactEmail.split(separator: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? contactEmail
                    if nameFromEmail != contactEmail {
                        print("📧 DataSyncService: Using extracted name: \(nameFromEmail)")
                        contactName = nameFromEmail
                    } else {
                        print("⚠️ DataSyncService: No name found, using email: \(contactEmail)")
                    }
                } else {
                    print("📝 DataSyncService: Using Gmail header name: \(contactName)")
                }
                
                let conversation: Conversation
                if let existing = conversationMap[contactEmail] {
                    conversation = existing
                    // Update the name if we have a better one from contacts
                    if let addressBookName = contactsService.getContactName(for: contactEmail),
                       existing.contactName != addressBookName {
                        existing.contactName = addressBookName
                    }
                } else {
                    conversation = Conversation(
                        contactName: contactName,
                        contactEmail: contactEmail,
                        lastMessageTimestamp: email.timestamp,
                        lastMessageSnippet: email.snippet,
                        isRead: email.isRead
                    )
                    modelContext.insert(conversation)
                    conversationMap[contactEmail] = conversation
                }
                
                // Add email to conversation
                conversation.addEmail(email)
                modelContext.insert(email)
                newMessageCount += 1
                
                // Update conversation metadata only for received messages
                // Don't override sent message timestamps (which are in the future)
                if !email.isFromMe && email.timestamp > conversation.lastMessageTimestamp.addingTimeInterval(-60) {
                    conversation.lastMessageTimestamp = email.timestamp
                    conversation.lastMessageSnippet = email.snippet
                    conversation.isRead = email.isRead
                }
            }
            
            try modelContext.save()
            lastSyncTime = Date()
            
            // Notify if we have new messages
            if newMessageCount > 0 {
                hasNewMessages = true
                NotificationCenter.default.post(name: DataSyncService.newMessagesNotification, object: nil)
            }
            
        } catch {
            print("Sync error: \(error)")
        }
    }
    
    // MARK: - Immediate Actions
    
    func handleMessageSent() {
        // After sending a message, we don't need to do a full sync
        // The local state is already updated
        // Just mark the sync time
        lastSyncTime = Date()
        
        // Schedule a sync after a short delay to catch any server-side changes
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await syncData(silent: true)
        }
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