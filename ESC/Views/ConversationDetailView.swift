import SwiftUI
import SwiftData

struct ConversationDetailView: View {
    let conversation: Conversation
    @ObservedObject var gmailService: GmailService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var contactsService = ContactsService()
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var scrollToId: String?
    @State private var isTextFieldFocused = false
    @State private var emails: [Email] = []
    @State private var refreshTrigger = 0
    
    private var conversationEmails: [Email] {
        let sorted = emails.sorted { $0.timestamp < $1.timestamp }
        print("🔍 ConversationDetailView: Showing \(sorted.count) emails")
        for (index, email) in sorted.enumerated() {
            print("📧 Email \(index): \(email.id.prefix(8)) - \(email.timestamp) - isFromMe: \(email.isFromMe) - snippet: \(email.snippet.prefix(20))")
        }
        return sorted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Contact header with profile picture
            ContactHeaderView(
                conversation: conversation,
                contactsService: contactsService
            )
            
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(conversationEmails, id: \.id) { email in
                            MessageBubbleView(email: email)
                                .id(email.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color.white)
                .onAppear {
                    loadEmails()
                    markAsRead()
                    
                    // Scroll to bottom after emails load with longer delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let lastEmail = conversationEmails.last {
                            print("📍 OnAppear: Scrolling to last email \(lastEmail.id) at \(lastEmail.timestamp)")
                            proxy.scrollTo(lastEmail.id, anchor: .bottom)
                        } else {
                            print("⚠️ OnAppear: No emails found to scroll to")
                        }
                    }
                }
                .onChange(of: scrollToId) { _, newValue in
                    if let id = newValue {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                        scrollToId = nil
                    }
                }
                .onChange(of: isTextFieldFocused) { _, focused in
                    if focused {
                        // Scroll to bottom when text field is focused
                        if let lastEmail = conversationEmails.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastEmail.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: emails.count) { oldCount, newCount in
                    print("📊 Email count changed from \(oldCount) to \(newCount)")
                    if newCount > oldCount {
                        // New email added, scroll to bottom
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastEmail = conversationEmails.last {
                                print("📍 ScrollToBottom: Scrolling to \(lastEmail.id)")
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(lastEmail.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .onChange(of: refreshTrigger) { _, _ in
                    print("🔄 ConversationDetailView: RefreshTrigger changed, reloading emails")
                    loadEmails()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConversationUpdated"))) { notification in
                    if let updatedConversation = notification.object as? Conversation,
                       updatedConversation.contactEmail == conversation.contactEmail {
                        print("🔄 ConversationDetailView: Received update for this conversation, reloading emails")
                        loadEmails()
                    }
                }
            }
            
            // Message input
            MessageInputView(
                messageText: $messageText,
                isTextFieldFocused: $isTextFieldFocused,
                onSend: sendMessage
            )
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func loadEmails() {
        let contactEmail = conversation.contactEmail
        let descriptor = FetchDescriptor<Email>(
            predicate: #Predicate<Email> { email in
                (email.isFromMe && email.recipientEmail == contactEmail) ||
                (!email.isFromMe && email.senderEmail == contactEmail)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            emails = try modelContext.fetch(descriptor)
            print("📧 LoadEmails: Loaded \(emails.count) emails for \(contactEmail)")
        } catch {
            print("❌ LoadEmails: Failed to fetch emails: \(error)")
            emails = []
        }
    }
    
    private func markAsRead() {
        guard !conversation.isRead else { return }
        
        conversation.isRead = true
        // Use conversationEmails to mark all as read
        for email in conversationEmails where !email.isRead {
            email.isRead = true
        }
        
        do {
            try modelContext.save()
        } catch {
            handleError(error)
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSending = true
        let messageBody = messageText
        
        Task {
            do {
                // Get user's email first for proper sender info
                let userEmail: String
                if gmailService.isAuthenticated {
                    userEmail = try await gmailService.getUserEmail()
                    // Send via Gmail API
                    try await gmailService.sendEmail(to: conversation.contactEmail, body: messageBody)
                } else {
                    userEmail = "me@example.com" // Fallback for offline mode
                }
                
                // Create local email record with proper sender info
                let email = createLocalEmail(body: messageBody, senderEmail: userEmail)
                
                await MainActor.run {
                    // Clear message text immediately for better UX
                    messageText = ""
                    isSending = false
                    
                    // Insert email first to ensure it's in the database
                    modelContext.insert(email)
                    
                    // Add email to conversation and update conversation metadata
                    conversation.addEmail(email)
                    conversation.isRead = true
                    
                    // Force timestamp update to ensure list reordering
                    conversation.lastMessageTimestamp = email.timestamp
                    conversation.lastMessageSnippet = email.snippet
                    
                    print("✅ Added email to conversation, final timestamp: \(conversation.lastMessageTimestamp)")
                    print("📝 Final conversation snippet: \(conversation.lastMessageSnippet)")
                    
                    do {
                        // Process any pending changes first
                        modelContext.processPendingChanges()
                        try modelContext.save()
                        
                        print("✅ Saved sent message with ID: \(email.id), timestamp: \(email.timestamp)")
                        
                        // Immediately add to local state for instant UI update
                        emails.append(email)
                        print("📧 Added email to local state. Now showing \(emails.count) emails")
                        
                        // Trigger scroll to new message
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToId = email.id
                            print("🔄 Triggering scroll to message: \(email.id)")
                        }
                        
                        // Notify about the conversation update
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ConversationUpdated"),
                            object: conversation
                        )
                        
                        // Notify sync service about the sent message
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MessageSent"),
                            object: conversation
                        )
                    } catch {
                        print("❌ Failed to save sent message: \(error)")
                        handleError(error)
                    }
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    handleError(error)
                }
            }
        }
    }
    
    private func createLocalEmail(body: String, senderEmail: String) -> Email {
        return Email(
            id: UUID().uuidString,
            messageId: UUID().uuidString,
            threadId: UUID().uuidString,
            sender: "Me",
            senderEmail: senderEmail,
            recipient: conversation.contactName,
            recipientEmail: conversation.contactEmail,
            body: body,
            snippet: MessageCleaner.createCleanSnippet(body),
            timestamp: Date(),
            isRead: true,
            isFromMe: true,
            conversation: conversation
        )
    }
    
    private func handleError(_ error: Error) {
        isSending = false
        errorMessage = error.localizedDescription
        showingError = true
    }
}

#Preview {
    let sampleConversation = Conversation(
        contactName: "John Doe",
        contactEmail: "john@example.com",
        lastMessageTimestamp: Date(),
        lastMessageSnippet: "Hey, how are you?"
    )
    
    ConversationDetailView(conversation: sampleConversation, gmailService: GmailService())
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}