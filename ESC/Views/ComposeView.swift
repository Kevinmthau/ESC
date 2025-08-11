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
    let existingConversation: Conversation?
    
    init(gmailService: GmailService, existingConversation: Conversation? = nil, onMessageSent: ((Conversation) -> Void)? = nil) {
        self.gmailService = gmailService
        self.existingConversation = existingConversation
        self.onMessageSent = onMessageSent
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                toFieldSection
                messageInputSection
            }
            .background(Color.white)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                handleOnAppear()
            }
            .onChange(of: contactsService.contacts.count) { _, _ in
                print("📱 ComposeView: Contacts list changed, updating filtered contacts...")
                updateFilteredContacts()
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
    
    private var toFieldSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("To:")
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(width: 30, alignment: .leading)
                
                toEmailTextField
                
                Spacer()
                
                addContactButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
                    
            contactSuggestionsView
            
            Divider()
                .background(Color.gray.opacity(0.3))
        }
        .background(Color.white)
    }
    
    private var toEmailTextField: some View {
        TextField("Email address", text: $toEmail)
            .textFieldStyle(PlainTextFieldStyle())
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($isToFieldFocused)
            .onChange(of: toEmail) { _, newValue in
                print("📝 ComposeView: To field changed to: '\(newValue)'")
                if isToFieldFocused {
                    isEditingTo = true
                }
                updateFilteredContacts()
                print("📝 ComposeView: Filtered contacts count: \(filteredContacts.count)")
                print("📝 ComposeView: isEditingTo: \(isEditingTo)")
            }
            .onChange(of: isToFieldFocused) { _, focused in
                print("🎯 ComposeView: To field focus changed to: \(focused)")
                isEditingTo = focused
                if focused {
                    updateFilteredContacts()
                    print("🎯 ComposeView: To field focused, showing suggestions")
                } else {
                    print("🎯 ComposeView: To field unfocused, hiding suggestions")
                }
            }
    }
    
    private var addContactButton: some View {
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
    
    @ViewBuilder
    private var contactSuggestionsView: some View {
        if isEditingTo && filteredContacts.count > 0 {
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
    }
    
    private var messageInputSection: some View {
        VStack(spacing: 0) {
            // Message input area at bottom
            Spacer()
                .onTapGesture {
                    isEditingTo = false
                    isToFieldFocused = false
                }
            
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
    }
    
    private func handleOnAppear() {
        print("🚀 ComposeView: View appeared")
        print("🚀 ComposeView: Current contacts count: \(contactsService.contacts.count)")
        
        // Auto-focus the To field when compose view appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isToFieldFocused = true
            isEditingTo = true
            print("🚀 ComposeView: Set focus and editing to true")
        }
        
        // Request contacts access and fetch contacts
        Task {
            print("📱 ComposeView: Checking contacts authorization...")
            print("📱 ComposeView: Current auth status: \(contactsService.authorizationStatus.rawValue)")
            
            if contactsService.authorizationStatus == .notDetermined {
                print("📱 ComposeView: Requesting contacts access...")
                let granted = await contactsService.requestAccess()
                print("📱 ComposeView: Access granted: \(granted)")
            }
            
            if contactsService.authorizationStatus == .authorized {
                print("📱 ComposeView: Fetching contacts...")
                await contactsService.fetchContacts()
                
                // After fetching, update filtered contacts to show suggestions
                await MainActor.run {
                    print("📱 ComposeView: Contacts fetched, total: \(self.contactsService.contacts.count)")
                    print("📱 ComposeView: Updating filtered list...")
                    self.updateFilteredContacts()
                    
                    // Force another update after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.isToFieldFocused {
                            self.isEditingTo = true
                            self.updateFilteredContacts()
                            print("📱 ComposeView: Forced update of filtered contacts")
                        }
                    }
                }
            } else {
                print("❌ ComposeView: Contacts not authorized: \(contactsService.authorizationStatus.rawValue)")
            }
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
                        // Process pending changes first
                        modelContext.processPendingChanges()
                        try modelContext.save()
                        print("✅ ComposeView: Successfully saved conversation and email")
                        print("💾 ComposeView: Final conversation timestamp: \(conversation.lastMessageTimestamp)")
                        
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
                        
                        isSending = false
                        // Call the callback first, then dismiss
                        onMessageSent?(conversation)
                        dismiss()
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
        print("🔍 ComposeView: Updating filtered contacts...")
        print("🔍 ComposeView: Total address book contacts: \(contactsService.contacts.count)")
        print("🔍 ComposeView: Total conversations: \(conversations.count)")
        print("🔍 ComposeView: isEditingTo: \(isEditingTo)")
        
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
        
        print("🔍 ComposeView: Combined total: \(allContacts.count) unique contacts")
        
        // Filter based on query
        if toEmail.isEmpty {
            // Show first 10 contacts when field is empty but focused
            filteredContacts = Array(allContacts.prefix(10))
            print("🔍 ComposeView: Showing first 10 contacts for empty field")
        } else {
            // Filter contacts that match the typed text
            let query = toEmail.lowercased()
            filteredContacts = allContacts.filter { contact in
                contact.name.lowercased().contains(query) ||
                contact.email.lowercased().contains(query)
            }
            print("🔍 ComposeView: Filtered to \(filteredContacts.count) matches for query: '\(toEmail)'")
        }
        
        // Limit to 5 suggestions
        filteredContacts = Array(filteredContacts.prefix(5))
        
        print("🔍 ComposeView: Final filtered contacts: \(filteredContacts.count)")
        for contact in filteredContacts {
            print("  - \(contact.name): \(contact.email)")
        }
    }
}

#Preview {
    ComposeView(gmailService: GmailService())
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}