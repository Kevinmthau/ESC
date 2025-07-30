import SwiftUI
import SwiftData

struct ConversationDetailView: View {
    let conversation: Conversation
    @State private var messageText = ""
    
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
                    if let lastEmail = conversation.sortedEmails.last {
                        proxy.scrollTo(lastEmail.id, anchor: .bottom)
                    }
                }
            }
            
            // Message input
            MessageInputView(messageText: $messageText, onSend: sendMessage)
        }
        .background(Color.white)
        .navigationTitle(conversation.contactName)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // TODO: Implement sending email via Gmail API
        messageText = ""
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
        HStack(spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(1...4)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white)
    }
}

#Preview {
    let sampleConversation = Conversation(
        contactName: "John Doe",
        contactEmail: "john@example.com",
        lastMessageTimestamp: Date(),
        lastMessageSnippet: "Hey, how are you?"
    )
    
    ConversationDetailView(conversation: sampleConversation)
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}