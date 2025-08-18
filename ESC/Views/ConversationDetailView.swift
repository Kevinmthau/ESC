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
    @State private var forwardedEmail: Email?
    @State private var showingForwardCompose = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var replyingToEmail: Email? = nil
    
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
        .sheet(isPresented: $showingForwardCompose) {
            if let emailToForward = forwardedEmail {
                ForwardComposeView(
                    originalEmail: emailToForward,
                    gmailService: gmailService,
                    modelContext: modelContext
                )
            }
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
                                    recipientEmail = contact.email.lowercased()
                                    conversation.contactEmail = contact.email.lowercased()
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
                                MessageBubbleView(
                                    email: email,
                                    allEmails: conversationEmails,
                                    onForward: { emailToForward in
                                        handleForwardEmail(emailToForward)
                                    },
                                    onReply: { emailToReply in
                                        handleReplyToEmail(emailToReply)
                                    }
                                )
                                .id(email.id)
                            }
                            
                            // Add invisible spacer at bottom for better scroll behavior
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.bottom, keyboardHeight > 0 ? 20 : 0)
                    }
                }
                .background(Color.white)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                    guard let keyboardValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
                    let keyboardFrame = keyboardValue.cgRectValue
                    withAnimation(.easeInOut(duration: 0.25)) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        keyboardHeight = 0
                    }
                }
                .scrollDismissesKeyboard(.interactively)
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
                        // Delay to let keyboard start showing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if let lastEmail = conversationEmails.last {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(lastEmail.id, anchor: .bottom)
                                }
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
                                proxy.scrollTo(lastEmail.id, anchor: .bottom)
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
            
            // Reply preview if replying
            if let replyEmail = replyingToEmail {
                replyPreviewView(for: replyEmail)
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
        // Normalize email for comparison
        let normalizedContactEmail = contactEmail.lowercased()
        let descriptor = FetchDescriptor<Email>(
            predicate: #Predicate<Email> { email in
                (email.isFromMe && email.recipientEmail == normalizedContactEmail) ||
                (!email.isFromMe && email.senderEmail == normalizedContactEmail)
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
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedAttachments.isEmpty else {
            print("⚠️ Prevented sending empty message")
            return
        }
        
        print("📤 sendMessage called with text: '\(messageText)'")
        print("   Is reply: \(replyingToEmail != nil)")
        
        // Store the conversation we'll actually send to
        var targetConversation = conversation
        var shouldNavigateToExisting = false
        
        // For new conversations, validate recipient
        if isNewConversation {
            guard !recipientEmail.isEmpty && recipientEmail.contains("@") else {
                errorMessage = "Please enter a valid email address"
                showingError = true
                return
            }
            
            // Check if we already have a conversation with this recipient
            if let existingConversation = conversations.first(where: { 
                $0.contactEmail.lowercased() == recipientEmail.lowercased() 
            }) {
                // Use existing conversation instead of creating new one
                print("🔄 Found existing conversation with \(recipientEmail), using it instead")
                targetConversation = existingConversation
                shouldNavigateToExisting = true
                
                // Load emails from existing conversation
                emails = existingConversation.emails.sorted { $0.timestamp < $1.timestamp }
            } else {
                // New conversation - update with recipient info
                conversation.contactEmail = recipientEmail.lowercased()
                conversation.contactName = extractNameFromEmail(recipientEmail)
                targetConversation = conversation
            }
        }
        
        isSending = true
        let messageBody = messageText.isEmpty ? "(Attachment)" : messageText
        let recipient = targetConversation.contactEmail.isEmpty ? recipientEmail : targetConversation.contactEmail
        let attachments = selectedAttachments
        let replyToEmail = replyingToEmail
        
        // Debug logging for reply tracking
        if let replyTo = replyToEmail {
            print("🔗 Creating reply to message:")
            print("   Reply to ID: \(replyTo.id)")
            print("   Reply to messageId: \(replyTo.messageId)")
            print("   Reply to snippet: \(replyTo.snippet)")
        } else {
            print("📨 Creating new message (not a reply)")
        }
        
        Task {
            do {
                // Get user's email and name for proper sender info
                let userEmail: String
                let userName: String
                if gmailService.isAuthenticated {
                    userEmail = try await gmailService.getUserEmail()
                    userName = try await gmailService.getUserDisplayName()
                    
                    // Build message body with history for replies
                    let bodyToSend = if let replyTo = replyToEmail {
                        buildReplyBodyWithHistory(newMessage: messageBody, replyingTo: replyTo)
                    } else {
                        messageBody
                    }
                    
                    // Send via Gmail API with attachments and reply headers if applicable
                    if let replyTo = replyToEmail {
                        print("📧 Sending reply - Original subject: '\(replyTo.subject ?? "nil")'")
                        try await gmailService.sendEmail(
                            to: recipient,
                            body: bodyToSend,
                            subject: replyTo.subject,
                            inReplyTo: replyTo.messageId,
                            attachments: attachments
                        )
                    } else {
                        try await gmailService.sendEmail(to: recipient, body: bodyToSend, attachments: attachments)
                    }
                } else {
                    userEmail = "me@example.com" // Fallback for offline mode
                    userName = "Me"
                }
                
                // Create local email record with proper sender info and attachments
                // IMPORTANT: Use original messageBody (without history) for local storage
                // For replies, use the id field which works for both local and Gmail messages
                let replyToId = replyToEmail?.id
                print("🔨 Creating local email with inReplyTo: \(replyToId ?? "nil")")
                
                let email = createLocalEmail(
                    body: messageBody,
                    senderName: userName,
                    senderEmail: userEmail,
                    attachments: attachments,
                    inReplyTo: replyToId,
                    subject: replyToEmail?.subject
                )
                
                print("✅ Created email with ID: \(email.id)")
                print("   inReplyToMessageId: \(email.inReplyToMessageId ?? "nil")")
                print("   snippet: \(email.snippet)")
                
                await MainActor.run {
                    // Clear message text and attachments immediately for better UX
                    messageText = ""
                    selectedAttachments = []
                    replyingToEmail = nil
                    isSending = false
                    
                    // Insert email first to ensure it's in the database
                    modelContext.insert(email)
                    
                    // Insert attachments
                    for attachment in email.attachments {
                        modelContext.insert(attachment)
                    }
                    
                    // Add email to the target conversation and update metadata
                    targetConversation.addEmail(email)
                    targetConversation.isRead = true
                    
                    // Force timestamp update to ensure list reordering
                    targetConversation.lastMessageTimestamp = email.timestamp
                    targetConversation.lastMessageSnippet = email.snippet
                    
                    // For new conversations, ensure the conversation is saved
                    if targetConversation.modelContext == nil {
                        modelContext.insert(targetConversation)
                    }
                    
                    print("✅ Added email to conversation, final timestamp: \(targetConversation.lastMessageTimestamp)")
                    print("📝 Final conversation snippet: \(targetConversation.lastMessageSnippet)")
                    
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
                            object: targetConversation
                        )
                        
                        // Notify sync service about the sent message
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MessageSent"),
                            object: targetConversation
                        )
                        
                        // If we found an existing conversation, navigate to it
                        if shouldNavigateToExisting && targetConversation !== conversation {
                            // Dismiss this view and navigate to the existing conversation
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("NavigateToConversation"),
                                    object: targetConversation
                                )
                            }
                        }
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
    
    private func createLocalEmail(
        body: String,
        senderName: String,
        senderEmail: String,
        attachments: [(filename: String, data: Data, mimeType: String)],
        inReplyTo: String? = nil,
        subject: String? = nil
    ) -> Email {
        let email = Email(
            id: UUID().uuidString,
            messageId: UUID().uuidString,
            threadId: UUID().uuidString,
            sender: senderName,
            senderEmail: senderEmail,
            recipient: conversation.contactName,
            recipientEmail: conversation.contactEmail,
            body: body,
            snippet: MessageCleaner.createCleanSnippet(body),
            timestamp: Date(),
            isRead: true,
            isFromMe: true,
            conversation: conversation,
            inReplyToMessageId: inReplyTo,
            subject: subject
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
    
    private func handleForwardEmail(_ email: Email) {
        forwardedEmail = email
        showingForwardCompose = true
    }
    
    private func handleReplyToEmail(_ email: Email) {
        print("📬 handleReplyToEmail called")
        print("   Email ID: \(email.id)")
        print("   Subject: '\(email.subject ?? "nil")'")
        print("   MessageId: \(email.messageId)")
        
        // If the email doesn't have a subject, try to fetch it
        if email.subject == nil || email.subject?.isEmpty == true {
            print("⚠️ Email missing subject, attempting to fetch from Gmail...")
            Task {
                if let fetchedSubject = await fetchSubjectForEmail(email) {
                    await MainActor.run {
                        email.subject = fetchedSubject
                        print("✅ Fetched subject: '\(fetchedSubject)'")
                        do {
                            try modelContext.save()
                        } catch {
                            print("❌ Failed to save subject: \(error)")
                        }
                    }
                }
            }
        }
        
        replyingToEmail = email
        isTextFieldFocused = true
    }
    
    private func fetchSubjectForEmail(_ email: Email) async -> String? {
        guard gmailService.isAuthenticated else { return nil }
        
        do {
            // Fetch the specific message from Gmail to get its subject
            let gmailMessage = try await gmailService.fetchMessage(messageId: email.messageId)
            
            // Extract subject from headers
            if let payload = gmailMessage.payload,
               let headers = payload.headers {
                for header in headers {
                    if header.name.lowercased() == "subject" {
                        return header.value
                    }
                }
            }
        } catch {
            print("❌ Failed to fetch subject for email \(email.messageId): \(error)")
        }
        
        return nil
    }
    
    @ViewBuilder
    private func replyPreviewView(for email: Email) -> some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                
                // Dismiss button
                Button(action: {
                    // Clear reply state and any typed message
                    replyingToEmail = nil
                    messageText = ""
                    selectedAttachments = []
                    isTextFieldFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            
            // Dimmed bubble showing the message being replied to
            HStack {
                Spacer(minLength: 60)
                
                Text(email.snippet.isEmpty ? MessageCleaner.createCleanSnippet(email.body) : email.snippet)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .lineLimit(2)
                    .opacity(0.8)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
    
    private func buildReplyBodyWithHistory(newMessage: String, replyingTo: Email?) -> String {
        guard let replyingTo = replyingTo else {
            return newMessage
        }
        
        // Start with the new message
        var fullBody = newMessage
        
        // Add separator for quoted content
        fullBody += "\n\n"
        
        // Format the date for the email being replied to
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        // Add email header for the specific email being replied to
        fullBody += "On \(dateFormatter.string(from: replyingTo.timestamp)), "
        
        if replyingTo.isFromMe {
            fullBody += "you wrote:\n"
        } else {
            fullBody += "\(replyingTo.sender) wrote:\n"
        }
        
        // Get the email content - use HTML if available, otherwise plain text
        let emailContent: String
        if let htmlBody = replyingTo.htmlBody, !htmlBody.isEmpty {
            // Convert HTML to plain text while preserving structure
            emailContent = convertHTMLToPlainText(htmlBody)
        } else {
            emailContent = replyingTo.body
        }
        
        // Quote the email body with > prefix, preserving all line breaks
        let lines = emailContent.components(separatedBy: "\n")
        let quotedBody = lines.map { line in
            // Don't add extra space after > for empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                return ">"
            } else {
                return "> \(line)"
            }
        }.joined(separator: "\n")
        fullBody += quotedBody
        
        return fullBody
    }
    
    private func convertHTMLToPlainText(_ html: String) -> String {
        // Use NSAttributedString to convert HTML to plain text while preserving formatting
        guard let data = html.data(using: .utf8) else {
            return html
        }
        
        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            let attributedString = try NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )
            
            // Get the plain text with preserved formatting
            return attributedString.string
        } catch {
            print("❌ Failed to convert HTML to plain text: \(error)")
            // Fall back to basic HTML stripping
            return stripBasicHTML(html)
        }
    }
    
    private func stripBasicHTML(_ html: String) -> String {
        // Basic fallback HTML stripping
        var text = html
        
        // Replace common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        
        // Replace <br> and <p> tags with newlines
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        
        // Remove all remaining HTML tags
        let pattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: text.utf16.count)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // Clean up multiple consecutive newlines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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