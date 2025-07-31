import SwiftUI
import SwiftData

struct ConversationDetailView: View {
    let conversation: Conversation
    @ObservedObject var gmailService: GmailService
    @Environment(\.modelContext) private var modelContext
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var scrollToId: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(conversation.sortedEmails, id: \.id) { email in
                            MessageBubbleView(email: email)
                                .id(email.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color.white)
                .onAppear {
                    // Mark conversation as read when opened
                    if !conversation.isRead {
                        conversation.isRead = true
                        for email in conversation.emails where !email.isRead {
                            email.isRead = true
                        }
                        try? modelContext.save()
                    }
                    
                    if let lastEmail = conversation.sortedEmails.last {
                        proxy.scrollTo(lastEmail.id, anchor: .bottom)
                    }
                }
                .onChange(of: scrollToId) { _, newValue in
                    if let id = newValue {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                        scrollToId = nil
                    }
                }
            }
            
            // Message input
            MessageInputView(messageText: $messageText, onSend: sendMessage)
        }
        .background(Color.white)
        .navigationTitle(conversation.contactName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSending = true
        let messageBody = messageText
        
        Task {
            do {
                // Send via Gmail API if authenticated
                if gmailService.isAuthenticated {
                    try await gmailService.sendEmail(to: conversation.contactEmail, body: messageBody)
                }
                
                // Create local email record
                let email = Email(
                    id: UUID().uuidString,
                    messageId: UUID().uuidString,
                    threadId: UUID().uuidString,
                    sender: "Me",
                    senderEmail: "me@example.com",
                    recipient: conversation.contactName,
                    recipientEmail: conversation.contactEmail,
                    body: messageBody,
                    snippet: MessageCleaner.createCleanSnippet(messageBody),
                    timestamp: Date(),
                    isRead: true,
                    isFromMe: true
                )
                
                await MainActor.run {
                    // Add email to conversation (this updates timestamp and snippet)
                    conversation.addEmail(email)
                    
                    // Mark conversation as read
                    conversation.isRead = true
                    
                    modelContext.insert(email)
                    
                    do {
                        try modelContext.save()
                        messageText = ""
                        isSending = false
                        // Trigger scroll to the new message
                        scrollToId = email.id
                    } catch {
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
}

struct MessageBubbleView: View {
    let email: Email
    
    var body: some View {
        HStack {
            if email.isFromMe {
                Spacer(minLength: 50)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(MessageCleaner.cleanMessageBody(email.body))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    
                    Text(email.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MessageCleaner.cleanMessageBody(email.body))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    
                    Text(email.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                
                Spacer(minLength: 50)
            }
        }
    }
}

struct MessageInputView: View {
    @Binding var messageText: String
    let onSend: () -> Void
    
    var body: some View {
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
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
        }
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