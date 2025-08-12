import SwiftUI
import SwiftData

struct ConversationDetailView: View {
    @Bindable var conversation: Conversation
    @ObservedObject var gmailService: GmailService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contactsService: ContactsService
    @State private var messageText = ""
    @State private var recipientEmail = ""
    @State private var isSending = false
    @State private var selectedAttachments: [(filename: String, data: Data, mimeType: String)] = []
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var scrollToId: String?
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isRecipientFocused: Bool
    @State private var emails: [Email] = []
    @State private var refreshTrigger = 0
    @State private var isEditingRecipient = false
    @State private var filteredContacts: [(name: String, email: String)] = []
    @State private var hasScrolledToBottom = false
    @Query private var conversations: [Conversation]
    
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
                recipientSection
            } else {
                // Contact header with profile picture for existing conversations
                ContactHeaderView(
                    conversation: conversation
                )
            }
            
            messageScrollView
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(isNewConversation ? "New Message" : conversation.contactName)
        .onDisappear {
            handleOnDisappear()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var recipientSection: some View {
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
                            .onChange(of: recipientEmail) { _, newValue in
                                isEditingRecipient = true
                                updateFilteredContacts()
                            }
                            .onChange(of: isRecipientFocused) { _, focused in
                                isEditingRecipient = focused
                                if focused {
                                    updateFilteredContacts()
                                }
                            }
                        
                        Button(action: {
                            Task {
                                if contactsService.authorizationStatus != .authorized {
                                    _ = await contactsService.requestAccess()
                                }
                                if contactsService.authorizationStatus == .authorized {
                                    await contactsService.fetchContacts()
                                    updateFilteredContacts()
                                }
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
                    // Contact suggestions dropdown
                    if isEditingRecipient && !filteredContacts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(filteredContacts.prefix(5), id: \.email) { contact in
                                Button(action: {
                                    recipientEmail = contact.email
                                    conversation.contactEmail = contact.email
                                    conversation.contactName = contact.name
                                    isEditingRecipient = false
                                    isRecipientFocused = false
                                }) {
                                    HStack {
                                        ContactAvatarView(
                                            email: contact.email,
                                            name: contact.name,
                                            size: 32
                                        )
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(contact.name)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(contact.email)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if contact.email != filteredContacts.prefix(5).last?.email {
                                    Divider()
                                        .padding(.leading, 60)
                                }
                            }
                        }
                        .background(Color.white)
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
            Divider()
                .background(Color.gray.opacity(0.3))
        }
        .background(Color.white)
    }
    
    private var messageScrollView: some View {
        VStack(spacing: 0) {
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
                            // Add invisible spacer at top to ensure proper scrolling
                            Color.clear
                                .frame(height: 1)
                                .id("top")
                            
                            ForEach(conversationEmails, id: \.id) { email in
                                MessageBubbleView(email: email)
                                    .id(email.id)
                            }
                            
                            // Add invisible spacer at bottom for better scroll behavior
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color.white)
                .onAppear {
                    // Request contacts access and fetch contacts
                    Task {
                        if contactsService.authorizationStatus == .notDetermined {
                            _ = await contactsService.requestAccess()
                        }
                        if contactsService.authorizationStatus == .authorized {
                            await contactsService.fetchContacts()
                        }
                    }
                    
                    if !isNewConversation {
                        loadEmails()
                        markAsRead()
                        
                        // Immediately scroll to bottom without animation for instant positioning
                        if let lastEmail = conversationEmails.last {
                            print("📍 OnAppear: Instant scroll to last email \(lastEmail.id)")
                            proxy.scrollTo(lastEmail.id, anchor: .bottom)
                        }
                        
                        // Then scroll again with animation after a delay to ensure content is loaded
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastEmail = conversationEmails.last {
                                print("📍 OnAppear: Animated scroll to last email \(lastEmail.id)")
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(lastEmail.id, anchor: .bottom)
                                }
                            }
                        }
                    } else {
                        // Focus the recipient field for new conversations
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRecipientFocused = true
                            isEditingRecipient = true
                            updateFilteredContacts()
                        }
                    }
                }
                .onChange(of: contactsService.contacts.count) { _, _ in
                    if isNewConversation && isEditingRecipient {
                        updateFilteredContacts()
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
                    
                    // Scroll to bottom when emails first load or when new emails are added
                    if (oldCount == 0 && newCount > 0) || newCount > oldCount {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastEmail = conversationEmails.last {
                                print("📍 ScrollToBottom: Scrolling to \(lastEmail.id)")
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(lastEmail.id, anchor: .bottom)
                                }
                                hasScrolledToBottom = true
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
                selectedAttachments: $selectedAttachments,
                isTextFieldFocused: $isTextFieldFocused,
                onSend: sendMessage
            )
        }
    }
    
    private func handleOnDisappear() {
        // Save any unsent draft for new conversations if needed
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
            let fetchedEmails = try modelContext.fetch(descriptor)
            
            // Remove duplicates based on message content and timestamp
            var uniqueEmails: [Email] = []
            var seenMessages = Set<String>()
            
            for email in fetchedEmails {
                // Create a unique key based on content and approximate timestamp
                let timeKey = Int(email.timestamp.timeIntervalSince1970 / 10) // Round to 10 seconds
                let uniqueKey = "\(email.isFromMe)_\(timeKey)_\(email.body.prefix(100))"
                
                if !seenMessages.contains(uniqueKey) {
                    seenMessages.insert(uniqueKey)
                    uniqueEmails.append(email)
                } else {
                    print("⚠️ LoadEmails: Skipping duplicate email \(email.id) with key: \(uniqueKey.prefix(50))...")
                }
            }
            
            emails = uniqueEmails
            print("📧 LoadEmails: Loaded \(uniqueEmails.count) unique emails for \(contactEmail) (filtered from \(fetchedEmails.count) total)")
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
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedAttachments.isEmpty else { return }
        
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
        let messageBody = messageText.isEmpty ? "(Attachment)" : messageText
        let recipient = isNewConversation ? recipientEmail : conversation.contactEmail
        let attachments = selectedAttachments
        
        Task {
            do {
                // Get user's email first for proper sender info
                let userEmail: String
                if gmailService.isAuthenticated {
                    userEmail = try await gmailService.getUserEmail()
                    // Send via Gmail API with attachments
                    try await gmailService.sendEmail(to: recipient, body: messageBody, attachments: attachments)
                } else {
                    userEmail = "me@example.com" // Fallback for offline mode
                }
                
                // Create local email record with proper sender info and attachments
                let email = createLocalEmail(body: messageBody, senderEmail: userEmail, attachments: attachments)
                
                await MainActor.run {
                    // Clear message text and attachments immediately for better UX
                    messageText = ""
                    selectedAttachments = []
                    isSending = false
                    
                    // Insert email first to ensure it's in the database
                    modelContext.insert(email)
                    
                    // Insert attachments
                    for attachment in email.attachments {
                        modelContext.insert(attachment)
                    }
                    
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
                        
                        // Immediately add to local state for instant UI update (avoid duplicates)
                        if !emails.contains(where: { $0.id == email.id }) {
                            emails.append(email)
                            print("📧 Added email to local state. Now showing \(emails.count) emails")
                        } else {
                            print("⚠️ Email already in local state, skipping addition")
                        }
                        
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
    
    private func createLocalEmail(body: String, senderEmail: String, attachments: [(filename: String, data: Data, mimeType: String)]) -> Email {
        let email = Email(
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
        
        // Add attachments to the email
        for attachment in attachments {
            let attachmentModel = Attachment(
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                size: attachment.data.count,
                data: attachment.data
            )
            email.attachments.append(attachmentModel)
        }
        
        return email
    }
    
    private func updateFilteredContacts() {
        // Combine all contacts from conversations and address book
        var allContacts: [(name: String, email: String)] = []
        var seenEmails = Set<String>()
        
        // Add conversation contacts first (recent/frequent)
        for conversation in conversations {
            let email = conversation.contactEmail.lowercased()
            if !seenEmails.contains(email) && !email.isEmpty {
                allContacts.append((name: conversation.contactName, email: conversation.contactEmail))
                seenEmails.insert(email)
            }
        }
        
        // Add all address book contacts
        for contact in contactsService.contacts {
            let email = contact.email.lowercased()
            if !seenEmails.contains(email) && !email.isEmpty {
                allContacts.append(contact)
                seenEmails.insert(email)
            }
        }
        
        // Filter based on query
        if recipientEmail.isEmpty {
            // Show first 10 contacts when field is empty but focused
            filteredContacts = Array(allContacts.prefix(10))
        } else {
            // Filter contacts that match the typed text
            let query = recipientEmail.lowercased()
            filteredContacts = allContacts.filter { contact in
                contact.name.lowercased().contains(query) ||
                contact.email.lowercased().contains(query)
            }
        }
        
        // Limit to 5 suggestions
        filteredContacts = Array(filteredContacts.prefix(5))
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