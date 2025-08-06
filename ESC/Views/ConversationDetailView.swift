import SwiftUI
import SwiftData

struct ConversationDetailView: View {
    @Bindable var conversation: Conversation
    @ObservedObject var gmailService: GmailService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var contactsService = ContactsService()
    @State private var messageText = ""
    @State private var recipientEmail = ""
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var scrollToId: String?
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isRecipientFocused: Bool
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
    
    private var isNewConversation: Bool {
        conversation.contactEmail.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // For new conversations, show recipient field
            if isNewConversation {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("To:")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 30, alignment: .leading)
                        
                        TextField("Email address", text: $recipientEmail)
                            .textFieldStyle(PlainTextFieldStyle())
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isRecipientFocused)
                        
                        Button(action: {
                            // TODO: Add contacts picker
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
                    Divider()
                        .background(Color.gray.opacity(0.3))
                }
                .background(Color.white)
            } else {
                // Contact header with profile picture for existing conversations
                ContactHeaderView(
                    conversation: conversation,
                    contactsService: contactsService
                )
            }
            
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    if isNewConversation {
                        VStack {
                            Spacer()
                            Text("Start a new conversation with \(conversation.contactName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(conversationEmails, id: \.id) { email in
                                MessageBubbleView(email: email)
                                    .id(email.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color.white)
                .onAppear {
                    if !isNewConversation {
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
                    } else {
                        // Focus the recipient field for new conversations
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRecipientFocused = true
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
        .navigationTitle(isNewConversation ? "New Message" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNewConversation {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
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
        
        // For new conversations, validate recipient
        if isNewConversation {
            guard !recipientEmail.isEmpty && recipientEmail.contains("@") else {
                errorMessage = "Please enter a valid email address"
                showingError = true
                return
            }
            
            // Update conversation with recipient info
            conversation.contactEmail = recipientEmail
            conversation.contactName = extractNameFromEmail(recipientEmail)
        }
        
        isSending = true
        let messageBody = messageText
        let recipient = isNewConversation ? recipientEmail : conversation.contactEmail
        
        Task {
            do {
                // Get user's email first for proper sender info
                let userEmail: String
                if gmailService.isAuthenticated {
                    userEmail = try await gmailService.getUserEmail()
                    // Send via Gmail API
                    try await gmailService.sendEmail(to: recipient, body: messageBody)
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
                    
                    // For new conversations, ensure the conversation is saved
                    if conversation.modelContext == nil {
                        modelContext.insert(conversation)
                    }
                    
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
    
    private func extractNameFromEmail(_ email: String) -> String {
        // First try to get name from contacts
        if let contactName = contactsService.getContactName(for: email) {
            return contactName
        }
        
        // Otherwise extract name from email
        if let atIndex = email.firstIndex(of: "@") {
            let username = String(email[..<atIndex])
            // Try to make it more human-readable
            let nameFromEmail = username.replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            return nameFromEmail
        }
        return email
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