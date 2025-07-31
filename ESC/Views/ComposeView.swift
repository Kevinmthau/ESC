import SwiftUI
import SwiftData
import Contacts

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var toEmail = ""
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isEditingTo = false
    @State private var filteredContacts: [(name: String, email: String)] = []
    @FocusState private var isToFieldFocused: Bool
    
    @ObservedObject var gmailService: GmailService
    @Query private var conversations: [Conversation]
    @StateObject private var contactsService = ContactsService()
    
    let onMessageSent: ((Conversation) -> Void)?
    
    init(gmailService: GmailService, onMessageSent: ((Conversation) -> Void)? = nil) {
        self.gmailService = gmailService
        self.onMessageSent = onMessageSent
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // To field with + button
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("To:")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 30, alignment: .leading)
                        
                        TextField("", text: $toEmail)
                            .textFieldStyle(PlainTextFieldStyle())
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isToFieldFocused)
                            .onTapGesture {
                                isEditingTo = true
                                updateFilteredContacts()
                            }
                            .onChange(of: toEmail) { _, newValue in
                                updateFilteredContacts()
                            }
                            .onChange(of: isToFieldFocused) { _, focused in
                                isEditingTo = focused
                                if focused {
                                    updateFilteredContacts()
                                }
                            }
                        
                        Spacer()
                        
                        Button(action: {
                            Task {
                                if contactsService.authorizationStatus != .authorized {
                                    _ = await contactsService.requestAccess()
                                }
                                if contactsService.authorizationStatus == .authorized {
                                    await contactsService.fetchContacts()
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
                    
                    // Contact suggestions
                    if isEditingTo && !filteredContacts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(filteredContacts.prefix(5), id: \.email) { contact in
                                Button(action: {
                                    toEmail = contact.email
                                    isEditingTo = false
                                    isToFieldFocused = false
                                }) {
                                    HStack {
                                        ContactAvatarView(
                                            email: contact.email,
                                            name: contact.name,
                                            contactsService: contactsService,
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
                
                // Message input area at bottom
                Spacer()
                
                // iMessage-style input bar
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    HStack(spacing: 8) {
                        // Text input
                        TextField("", text: $messageText, axis: .vertical)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.body)
                            .lineLimit(1...6)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(20)
                            .frame(minHeight: 36)
                        
                        // Send button
                        if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: {
                                print("🚀 ComposeView: Send button tapped!")
                                sendMessage()
                            }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 32, height: 32)
                            }
                            .disabled(isSending || toEmail.isEmpty)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                }
            }
            .background(Color.white)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
                isEditingTo = false
                isToFieldFocused = false
            }
            .onAppear {
                // Auto-focus the To field when compose view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isToFieldFocused = true
                }
                
                // Request contacts access and fetch contacts
                Task {
                    if contactsService.authorizationStatus == .notDetermined {
                        _ = await contactsService.requestAccess()
                    }
                    if contactsService.authorizationStatus == .authorized {
                        await contactsService.fetchContacts()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func sendMessage() {
        print("🎯 ComposeView: sendMessage() called")
        print("🎯 To email: '\(toEmail)'")
        print("🎯 Message text: '\(messageText)'")
        
        guard !toEmail.isEmpty && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { 
            print("❌ ComposeView: Empty email or message, returning early")
            return 
        }
        
        print("✅ ComposeView: Starting send process...")
        isSending = true
        
        Task {
            do {
                // Try to send via Gmail API if authenticated
                let senderEmail = "me@example.com"
                let senderName = "Me"
                
                print("🔑 ComposeView: Gmail authenticated: \(gmailService.isAuthenticated)")
                
                if gmailService.isAuthenticated {
                    print("📤 ComposeView: Calling Gmail sendEmail...")
                    try await gmailService.sendEmail(to: toEmail, body: messageText)
                    print("✅ ComposeView: Gmail sendEmail completed successfully")
                    // Get actual sender email for the record
                    // Note: We could cache this, but for now we'll use a placeholder
                    // since the email was successfully sent
                } else {
                    print("⚠️ ComposeView: Gmail not authenticated, skipping API call")
                }
                
                // Create local email record
                let email = Email(
                    id: UUID().uuidString,
                    messageId: UUID().uuidString,
                    threadId: UUID().uuidString,
                    sender: senderName,
                    senderEmail: senderEmail,
                    recipient: extractNameFromEmail(toEmail),
                    recipientEmail: toEmail,
                    body: messageText,
                    snippet: MessageCleaner.createCleanSnippet(messageText),
                    timestamp: Date(),
                    isRead: true,
                    isFromMe: true
                )
                
                await MainActor.run {
                    print("💾 ComposeView: Creating local conversation record...")
                    
                    // Find or create conversation
                    let conversation = findOrCreateConversation(for: toEmail, email: email)
                    
                    // Add email to conversation (this updates timestamp and snippet)
                    conversation.addEmail(email)
                    
                    // Mark conversation as read
                    conversation.isRead = true
                    
                    print("💾 ComposeView: Conversation timestamp updated to: \(conversation.lastMessageTimestamp)")
                    
                    modelContext.insert(email)
                    
                    // Force SwiftData to recognize the conversation changes
                    if conversation.modelContext == nil {
                        print("💾 ComposeView: Inserting new conversation into context")
                        modelContext.insert(conversation)
                    } else {
                        print("💾 ComposeView: Conversation already in context, forcing refresh")
                    }
                    
                    do {
                        try modelContext.save()
                        print("✅ ComposeView: Successfully saved conversation and email")
                        print("💾 ComposeView: Final conversation timestamp: \(conversation.lastMessageTimestamp)")
                        isSending = false
                        // Dismiss compose view and navigate to conversation
                        dismiss()
                        onMessageSent?(conversation)
                    } catch {
                        print("❌ ComposeView: Failed to save: \(error.localizedDescription)")
                        isSending = false
                        errorMessage = "Failed to save message: \(error.localizedDescription)"
                        showingError = true
                    }
                }
                
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Failed to send message: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
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
    
    private func findOrCreateConversation(for email: String, email emailObject: Email) -> Conversation {
        print("🔍 ComposeView: Looking for conversation with email: \(email)")
        
        // Try to find existing conversation
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.contactEmail == email }
        )
        
        if let existingConversation = try? modelContext.fetch(descriptor).first {
            print("📋 ComposeView: Found existing conversation for \(email)")
            print("📋 ComposeView: Current timestamp: \(existingConversation.lastMessageTimestamp)")
            return existingConversation
        }
        
        print("➕ ComposeView: Creating new conversation for \(email)")
        
        // Create new conversation
        let conversation = Conversation(
            contactName: extractNameFromEmail(email),
            contactEmail: email,
            lastMessageTimestamp: Date(),
            lastMessageSnippet: emailObject.snippet,
            isRead: true
        )
        
        print("➕ ComposeView: New conversation created with timestamp: \(conversation.lastMessageTimestamp)")
        return conversation
    }
    
    private func updateFilteredContacts() {
        let conversationContacts = conversations.map { (name: $0.contactName, email: $0.contactEmail) }
        let addressBookContacts = contactsService.searchContacts(query: toEmail)
        
        // Combine and deduplicate contacts
        var allContacts: [(name: String, email: String)] = []
        var seenEmails = Set<String>()
        
        // Add conversation contacts first (recent/frequent)
        for contact in conversationContacts {
            if !seenEmails.contains(contact.email) {
                allContacts.append(contact)
                seenEmails.insert(contact.email)
            }
        }
        
        // Add address book contacts
        for contact in addressBookContacts {
            if !seenEmails.contains(contact.email) {
                allContacts.append(contact)
                seenEmails.insert(contact.email)
            }
        }
        
        if toEmail.isEmpty {
            filteredContacts = Array(allContacts.prefix(5))
        } else {
            filteredContacts = allContacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(toEmail) ||
                contact.email.localizedCaseInsensitiveContains(toEmail)
            }.prefix(5).map { $0 }
        }
    }
}

#Preview {
    ComposeView(gmailService: GmailService())
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}