import SwiftUI
import SwiftData

struct ForwardComposeView: View {
    let originalEmail: Email
    let gmailService: GmailService
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contactsService: ContactsService
    @State private var recipientEmail = ""
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isRecipientFocused: Bool
    @State private var isEditingRecipient = false
    @State private var filteredContacts: [(name: String, email: String)] = []
    @Query private var conversations: [Conversation]
    @State private var navigationPath = NavigationPath()
    
    init(originalEmail: Email, gmailService: GmailService, modelContext: ModelContext) {
        self.originalEmail = originalEmail
        self.gmailService = gmailService
        self.modelContext = modelContext
        
        // Pre-populate the message text with forward formatting
        let forwardedContent = Self.formatForwardedMessage(originalEmail)
        _messageText = State(initialValue: "\n\n" + forwardedContent)
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // To field
                recipientSection
                
                Divider()
                
                // Message composition area
                ScrollView {
                    TextEditor(text: $messageText)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .frame(minHeight: 300)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
                .background(Color.white)
                
                // Send button
                HStack {
                    Spacer()
                    Button(action: sendForwardedMessage) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(recipientEmail.isEmpty || isSending)
                    .padding()
                }
            }
            .navigationTitle("Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: Conversation.self) { conversation in
                ConversationDetailView(
                    conversation: conversation,
                    gmailService: gmailService
                )
            }
        }
        .onAppear {
            // Focus recipient field immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isRecipientFocused = true
                isEditingRecipient = true
                updateFilteredContacts()
            }
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
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .zIndex(1000)
            }
        }
    }
    
    private func sendForwardedMessage() {
        guard !recipientEmail.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Prepare attachments from original email
                var attachments: [(filename: String, data: Data, mimeType: String)] = []
                for attachment in originalEmail.attachments {
                    if let data = attachment.data {
                        attachments.append((
                            filename: attachment.filename,
                            data: data,
                            mimeType: attachment.mimeType
                        ))
                    }
                }
                
                // Get user info for proper sender details
                let userEmail = try await gmailService.getUserEmail()
                let userName = try await gmailService.getUserDisplayName()
                
                // Send the email with attachments
                try await gmailService.sendEmail(
                    to: recipientEmail,
                    body: messageText,
                    attachments: attachments
                )
                
                // Find or create conversation
                let normalizedRecipientEmail = recipientEmail.lowercased()
                let descriptor = FetchDescriptor<Conversation>(
                    predicate: #Predicate<Conversation> { conv in
                        conv.contactEmail == normalizedRecipientEmail
                    }
                )
                
                let existingConversations = try modelContext.fetch(descriptor)
                let conversation: Conversation
                
                if let existing = existingConversations.first {
                    conversation = existing
                } else {
                    // Extract name from email or contacts
                    let contactName = contactsService.getContactName(for: recipientEmail) ?? extractNameFromEmail(recipientEmail)
                    
                    conversation = Conversation(
                        contactName: contactName,
                        contactEmail: normalizedRecipientEmail,
                        lastMessageTimestamp: Date(),
                        lastMessageSnippet: messageText.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines),
                        isRead: true
                    )
                    modelContext.insert(conversation)
                }
                
                // Create local email record
                let sentEmail = Email(
                    id: UUID().uuidString,
                    messageId: "local-\(UUID().uuidString)",
                    sender: userName,
                    senderEmail: userEmail,
                    recipient: conversation.contactName,
                    recipientEmail: recipientEmail,
                    body: messageText,
                    snippet: String(messageText.prefix(100)),
                    timestamp: Date(),
                    isFromMe: true,
                    conversation: conversation
                )
                
                // Copy attachments to new email
                for attachment in originalEmail.attachments {
                    if let data = attachment.data {
                        let newAttachment = Attachment(
                            id: attachment.id,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            size: attachment.size,
                            data: data
                        )
                        newAttachment.email = sentEmail
                        sentEmail.attachments.append(newAttachment)
                        modelContext.insert(newAttachment)
                    }
                }
                
                conversation.addEmail(sentEmail)
                modelContext.insert(sentEmail)
                
                // Update conversation metadata
                conversation.lastMessageTimestamp = sentEmail.timestamp
                conversation.lastMessageSnippet = sentEmail.snippet
                
                try modelContext.save()
                
                // Dismiss and navigate to conversation
                dismiss()
                
                // Post notification to navigate to conversation
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToConversation"),
                    object: conversation
                )
                
            } catch {
                handleError(error)
            }
        }
    }
    
    private func updateFilteredContacts() {
        var allContacts: [(name: String, email: String)] = []
        var seenEmails = Set<String>()
        
        // Add conversation contacts first
        for conversation in conversations {
            let email = conversation.contactEmail.lowercased()
            if !seenEmails.contains(email) && !email.isEmpty {
                allContacts.append((name: conversation.contactName, email: conversation.contactEmail))
                seenEmails.insert(email)
            }
        }
        
        // Add address book contacts
        for contact in contactsService.contacts {
            let email = contact.email.lowercased()
            if !seenEmails.contains(email) && !email.isEmpty {
                allContacts.append(contact)
                seenEmails.insert(email)
            }
        }
        
        // Filter based on query
        if recipientEmail.isEmpty {
            filteredContacts = Array(allContacts.prefix(10))
        } else {
            let query = recipientEmail.lowercased()
            filteredContacts = allContacts.filter { contact in
                contact.name.lowercased().contains(query) ||
                contact.email.lowercased().contains(query)
            }
        }
        
        filteredContacts = Array(filteredContacts.prefix(5))
    }
    
    private func handleError(_ error: Error) {
        isSending = false
        errorMessage = error.localizedDescription
        showingError = true
    }
    
    private func extractNameFromEmail(_ email: String) -> String {
        // Try to get name from contacts first
        if let name = contactsService.getContactName(for: email) {
            return name
        }
        
        // Extract from email address
        let nameFromEmail = email.split(separator: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? email
        return nameFromEmail != email ? nameFromEmail : email
    }
    
    private static func formatForwardedMessage(_ email: Email) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        
        var forwardedText = "---------- Forwarded message ---------\n"
        forwardedText += "From: \(email.sender) <\(email.senderEmail)>\n"
        forwardedText += "Date: \(dateFormatter.string(from: email.timestamp))\n"
        
        // Add subject if available (we'll use the snippet as subject for now)
        let subject = email.snippet.prefix(50).trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty {
            forwardedText += "Subject: \(subject)\n"
        }
        
        forwardedText += "To: \(email.recipient) <\(email.recipientEmail)>\n\n"
        
        // Add the body with ">" prefix for each line
        let bodyLines = email.body.components(separatedBy: .newlines)
        for line in bodyLines {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                forwardedText += "> \(line)\n"
            } else {
                forwardedText += ">\n"
            }
        }
        
        // Add attachment info if present
        if !email.attachments.isEmpty {
            forwardedText += "\n> Attachments:\n"
            for attachment in email.attachments {
                forwardedText += "> - \(attachment.filename) (\(attachment.formattedSize))\n"
            }
        }
        
        return forwardedText
    }
}