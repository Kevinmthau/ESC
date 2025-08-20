import SwiftUI
import SwiftData

struct ForwardComposeView: View {
    let originalEmail: Email
    let gmailService: GmailService
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contactsService: ContactsService
    @State private var toRecipients: [String] = []
    @State private var messageText = ""
    @State private var showingRecipientSection = true
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isRecipientFieldFocused: Bool
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
                // Recipients section with collapse/expand
                if showingRecipientSection {
                    SimpleRecipientsField(
                        recipients: $toRecipients,
                        isFieldFocused: _isRecipientFieldFocused
                    )
                    
                    Divider()
                }
                
                // Collapse/expand header for recipients
                if !showingRecipientSection && !toRecipients.isEmpty {
                    HStack {
                        Text("To: \(formatRecipientsList(toRecipients))")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingRecipientSection.toggle()
                            }
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingRecipientSection = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isRecipientFieldFocused = true
                            }
                        }
                    }
                    
                    Divider()
                }
                
                // Message composition area
                TextEditor(text: $messageText)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .onTapGesture {
                        // Collapse recipients when tapping message area
                        if showingRecipientSection && !toRecipients.isEmpty {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingRecipientSection = false
                                isRecipientFieldFocused = false
                            }
                        }
                    }
                
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
                    .disabled(toRecipients.isEmpty || isSending)
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
                isRecipientFieldFocused = true
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func formatRecipientsList(_ recipients: [String]) -> String {
        if recipients.isEmpty {
            return ""
        } else if recipients.count == 1 {
            if let name = contactsService.getContactName(for: recipients[0]) {
                return name
            }
            return recipients[0]
        } else {
            let firstRecipient = contactsService.getContactName(for: recipients[0]) ?? recipients[0]
            return "\(firstRecipient) and \(recipients.count - 1) other\(recipients.count == 2 ? "" : "s")"
        }
    }
    
    private func sendForwardedMessage() {
        guard !toRecipients.isEmpty else { return }
        
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
                    to: toRecipients,
                    body: messageText,
                    attachments: attachments
                )
                
                // Check if conversation already exists
                let targetConversation: Conversation
                if toRecipients.count == 1 {
                    // Single recipient
                    let recipient = toRecipients[0]
                    if let existing = conversations.first(where: { 
                        !$0.isGroupConversation && $0.contactEmail.lowercased() == recipient.lowercased() 
                    }) {
                        targetConversation = existing
                    } else {
                        // Create new single conversation
                        let conversation = Conversation(
                            contactName: contactsService.getContactName(for: recipient) ?? extractNameFromEmail(recipient),
                            contactEmail: recipient.lowercased(),
                            lastMessageTimestamp: Date(),
                            lastMessageSnippet: MessageCleaner.createCleanSnippet(messageText)
                        )
                        conversation.isGroupConversation = false
                        modelContext.insert(conversation)
                        try modelContext.save()
                        targetConversation = conversation
                    }
                } else {
                    // Group conversation
                    let sortedRecipients = toRecipients.map { $0.lowercased() }.sorted()
                    let conversationKey = sortedRecipients.joined(separator: ",")
                    
                    if let existing = conversations.first(where: {
                        $0.isGroupConversation && 
                        $0.participantEmails.sorted() == sortedRecipients
                    }) {
                        targetConversation = existing
                    } else {
                        // Create new group conversation
                        let conversation = Conversation(
                            contactName: formatRecipientsList(toRecipients),
                            contactEmail: conversationKey,
                            lastMessageTimestamp: Date(),
                            lastMessageSnippet: MessageCleaner.createCleanSnippet(messageText)
                        )
                        conversation.isGroupConversation = true
                        conversation.participantEmails = toRecipients
                        modelContext.insert(conversation)
                        try modelContext.save()
                        targetConversation = conversation
                    }
                }
                
                // Create the local email record
                let email = Email(
                    id: UUID().uuidString,
                    messageId: UUID().uuidString,
                    threadId: originalEmail.threadId,
                    sender: userName,
                    senderEmail: userEmail,
                    recipient: toRecipients.count == 1 ? 
                        (contactsService.getContactName(for: toRecipients[0]) ?? extractNameFromEmail(toRecipients[0])) :
                        formatRecipientsList(toRecipients),
                    recipientEmail: toRecipients.first ?? "",
                    allRecipients: toRecipients,
                    toRecipients: toRecipients,
                    ccRecipients: [],
                    bccRecipients: [],
                    body: messageText,
                    snippet: MessageCleaner.createCleanSnippet(messageText),
                    timestamp: Date(),
                    isRead: true,
                    isFromMe: true,
                    conversation: targetConversation,
                    subject: "Fwd: \(originalEmail.subject ?? "(no subject)")"
                )
                
                // Copy attachments to the new email
                for attachment in originalEmail.attachments {
                    let newAttachment = Attachment(
                        id: UUID().uuidString,
                        filename: attachment.filename,
                        mimeType: attachment.mimeType,
                        size: attachment.size,
                        data: attachment.data
                    )
                    newAttachment.email = email
                    email.attachments.append(newAttachment)
                }
                
                modelContext.insert(email)
                
                // Update conversation
                targetConversation.lastMessageTimestamp = email.timestamp
                targetConversation.lastMessageSnippet = email.snippet
                targetConversation.isRead = true
                targetConversation.emails.append(email)
                
                try modelContext.save()
                
                // Navigate to conversation
                await MainActor.run {
                    dismiss()
                    
                    // Post notification to navigate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToConversation"),
                            object: targetConversation
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSending = false
                }
            }
        }
    }
    
    private func extractNameFromEmail(_ email: String) -> String {
        let components = email.split(separator: "@")
        if let localPart = components.first {
            return String(localPart).replacingOccurrences(of: ".", with: " ").capitalized
        }
        return email
    }
    
    static func formatForwardedMessage(_ email: Email) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var result = "---------- Forwarded message ----------\n"
        result += "From: \(email.sender) <\(email.senderEmail)>\n"
        result += "Date: \(dateFormatter.string(from: email.timestamp))\n"
        if let subject = email.subject {
            result += "Subject: \(subject)\n"
        }
        result += "To: \(email.recipient) <\(email.recipientEmail)>\n"
        result += "\n"
        result += email.body
        
        return result
    }
}

#Preview {
    do {
        let container = try ModelContainer(for: Email.self, Conversation.self, Attachment.self)
        let modelContext = ModelContext(container)
        
        return ForwardComposeView(
            originalEmail: Email(
                id: "1",
                messageId: "1",
                sender: "John Doe",
                senderEmail: "john@example.com",
                recipient: "Me",
                recipientEmail: "me@example.com",
                body: "This is the original message",
                snippet: "This is the original message",
                timestamp: Date(),
                isFromMe: false,
                conversation: nil,
                subject: "Test Subject"
            ),
            gmailService: GmailService(),
            modelContext: modelContext
        )
        .environmentObject(ContactsService.shared)
    } catch {
        return Text("Failed to create preview")
    }
}