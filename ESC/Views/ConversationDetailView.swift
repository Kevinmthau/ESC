import SwiftUI
import SwiftData

struct ConversationDetailView: View {
    @Bindable var conversation: Conversation
    @ObservedObject var gmailService: GmailService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contactsService: ContactsService
    @State private var messageText = ""
    @State private var recipientEmail = ""  // For single recipient (backward compatibility)
    @State private var toRecipients: [String] = []
    @State private var ccRecipients: [String] = []
    @State private var bccRecipients: [String] = []
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
    @Query private var conversations: [Conversation]
    @State private var forwardedEmail: Email?
    @State private var showingForwardCompose = false
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
        GeometryReader { geometry in
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
            MultipleRecipientsField(
                recipients: $toRecipients,
                ccRecipients: $ccRecipients,
                bccRecipients: $bccRecipients
            )
            
            Divider()
                .background(Color.gray.opacity(0.3))
        }
        .background(Color.white)
        .onAppear {
            // Initialize recipients for existing conversations
            if !isNewConversation && toRecipients.isEmpty {
                // For existing conversations, set the contact as the default recipient
                if conversation.isGroupConversation {
                    toRecipients = conversation.participantEmails
                } else if !conversation.contactEmail.isEmpty {
                    toRecipients = [conversation.contactEmail]
                }
            }
        }
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
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 200)
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
                                    isGroupConversation: conversation.isGroupConversation,
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
                                .frame(height: 50)
                                .id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
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
                        
                        // Initial scroll to bottom when view appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastEmail = conversationEmails.last {
                                proxy.scrollTo(lastEmail.id, anchor: .bottom)
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
                .onChange(of: emails.count) { oldCount, newCount in
                    // Scroll to bottom when new emails are added
                    if newCount > oldCount {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastEmail = conversationEmails.last {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(lastEmail.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .onChange(of: refreshTrigger) { _, _ in
                    loadEmails()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConversationUpdated"))) { notification in
                    if let updatedConversation = notification.object as? Conversation,
                       updatedConversation.contactEmail == conversation.contactEmail {
                        loadEmails()
                    }
                }
            }
            
            VStack(spacing: 0) {
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
    }
    
    private func handleOnDisappear() {
        // Save any unsent draft for new conversations if needed
    }
    
    private func loadEmails() {
        // For group conversations, we need to match against all participants
        if conversation.isGroupConversation {
            // Use the conversation's emails directly if they're already loaded
            if !conversation.emails.isEmpty {
                emails = conversation.emails.sorted { $0.timestamp < $1.timestamp }
                print("📧 LoadEmails: Loaded \(emails.count) emails from group conversation")
                return
            }
            
            // Otherwise fetch emails that match the conversation key
            let conversationKey = conversation.contactEmail.lowercased()
            let descriptor = FetchDescriptor<Email>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            
            do {
                let allEmails = try modelContext.fetch(descriptor)
                // Filter emails that belong to this group conversation
                let groupEmails = allEmails.filter { email in
                    // Check if this email's participants match our conversation
                    let emailParticipants = Set(email.allRecipients + [email.senderEmail.lowercased()])
                    let conversationParticipants = Set(conversationKey.split(separator: ",").map { String($0) })
                    
                    // Check for significant overlap (at least 2 common participants for group)
                    let commonParticipants = emailParticipants.intersection(conversationParticipants)
                    return commonParticipants.count >= min(2, conversationParticipants.count)
                }
                emails = groupEmails
                print("👥 LoadEmails: Loaded \(emails.count) emails for group conversation")
            } catch {
                print("❌ LoadEmails: Failed to fetch group emails: \(error)")
                emails = []
            }
        } else {
            // Single recipient conversation - use existing logic
            let contactEmail = conversation.contactEmail
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
        
        // For existing group conversations, ensure recipients are populated
        if !isNewConversation && conversation.isGroupConversation {
            // Parse the participant emails from the conversation
            if toRecipients.isEmpty {
                toRecipients = conversation.participantEmails
            }
        }
        
        // For new conversations, validate recipients
        if isNewConversation {
            // Check if we have at least one recipient
            guard !toRecipients.isEmpty else {
                errorMessage = "Please add at least one recipient"
                showingError = true
                return
            }
            
            // Validate all recipients
            for recipient in toRecipients + ccRecipients + bccRecipients {
                guard EmailValidator.isValid(recipient) else {
                    errorMessage = "Invalid email address: \(recipient)"
                    showingError = true
                    return
                }
            }
            
            // For group conversations, create a unique key based on all participants
            let isGroupMessage = toRecipients.count + ccRecipients.count + bccRecipients.count > 1
            
            if isGroupMessage {
                // Group conversation - create a new conversation with all participants
                // Get user email to exclude from participants
                let userEmail = gmailService.cachedUserEmail ?? ""
                let allRecipients = Array(Set(toRecipients + ccRecipients + bccRecipients))
                
                // Filter out user's own email for display
                let otherParticipants = allRecipients.filter { $0.lowercased() != userEmail.lowercased() }
                let participantNames = otherParticipants.map { email in
                    contactsService.getContactName(for: email) ?? extractNameFromEmail(email)
                }
                
                // Create conversation key from participants (excluding self)
                let conversationKey = otherParticipants.sorted().joined(separator: ",")
                
                // Check if we already have this group conversation
                if let existingConversation = conversations.first(where: {
                    $0.contactEmail == conversationKey
                }) {
                    print("🔄 Found existing group conversation")
                    targetConversation = existingConversation
                    shouldNavigateToExisting = true
                    emails = existingConversation.emails.sorted { $0.timestamp < $1.timestamp }
                } else {
                    // New group conversation
                    conversation.contactEmail = conversationKey
                    conversation.contactName = participantNames.prefix(3).joined(separator: ", ")
                    if participantNames.count > 3 {
                        conversation.contactName += " and \(participantNames.count - 3) more"
                    }
                    conversation.participantEmails = otherParticipants  // Store only other participants
                    conversation.isGroupConversation = true
                    targetConversation = conversation
                }
            } else {
                // Single recipient conversation
                let primaryRecipient = toRecipients.first ?? ""
                
                // Check if we already have a conversation with this recipient
                if let existingConversation = conversations.first(where: { 
                    !$0.isGroupConversation && $0.contactEmail.lowercased() == primaryRecipient.lowercased() 
                }) {
                    print("🔄 Found existing conversation with \(primaryRecipient)")
                    targetConversation = existingConversation
                    shouldNavigateToExisting = true
                    emails = existingConversation.emails.sorted { $0.timestamp < $1.timestamp }
                } else {
                    // New single conversation
                    conversation.contactEmail = primaryRecipient.lowercased()
                    conversation.contactName = contactsService.getContactName(for: primaryRecipient) ?? extractNameFromEmail(primaryRecipient)
                    conversation.isGroupConversation = false
                    targetConversation = conversation
                }
            }
        }
        
        isSending = true
        let messageBody = messageText.isEmpty ? "(Attachment)" : messageText
        let attachments = selectedAttachments
        let replyToEmail = replyingToEmail
        
        // Ensure we have valid recipients
        var finalToRecipients = toRecipients
        if finalToRecipients.isEmpty {
            if targetConversation.isGroupConversation {
                // For group conversations, use participant emails
                finalToRecipients = targetConversation.participantEmails
            } else {
                // For single conversations, use the contact email
                finalToRecipients = [targetConversation.contactEmail]
            }
        }
        
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
                        print("👥 Sending to recipients: \(finalToRecipients.joined(separator: ", "))")
                        try await gmailService.sendEmail(
                            to: finalToRecipients,
                            cc: ccRecipients,
                            bcc: bccRecipients,
                            body: bodyToSend,
                            subject: replyTo.subject,
                            inReplyTo: replyTo.messageId,
                            attachments: attachments
                        )
                    } else {
                        print("👥 Sending to recipients: \(finalToRecipients.joined(separator: ", "))")
                        try await gmailService.sendEmail(
                            to: finalToRecipients,
                            cc: ccRecipients,
                            bcc: bccRecipients,
                            body: bodyToSend,
                            attachments: attachments
                        )
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
                    subject: replyToEmail?.subject,
                    recipients: finalToRecipients
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
                        scrollToId = email.id
                        
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
        subject: String? = nil,
        recipients: [String]? = nil
    ) -> Email {
        // Use provided recipients or fall back to toRecipients
        let actualRecipients = recipients ?? toRecipients
        
        // For group conversations, use the first recipient as primary
        let primaryRecipient: String
        let primaryRecipientName: String
        
        if !actualRecipients.isEmpty {
            primaryRecipient = actualRecipients.first!
            primaryRecipientName = contactsService.getContactName(for: primaryRecipient) ?? extractNameFromEmail(primaryRecipient)
        } else if !conversation.contactEmail.isEmpty && !conversation.contactEmail.contains(",") {
            // Single conversation with valid email
            primaryRecipient = conversation.contactEmail
            primaryRecipientName = conversation.contactName
        } else {
            // Fallback for group conversations - use first participant
            primaryRecipient = conversation.participantEmails.first ?? ""
            primaryRecipientName = conversation.contactName
        }
        
        let email = Email(
            id: UUID().uuidString,
            messageId: UUID().uuidString,
            threadId: UUID().uuidString,
            sender: senderName,
            senderEmail: senderEmail,
            recipient: primaryRecipientName,
            recipientEmail: primaryRecipient,
            allRecipients: actualRecipients + ccRecipients + bccRecipients,
            toRecipients: actualRecipients,
            ccRecipients: ccRecipients,
            bccRecipients: bccRecipients,
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