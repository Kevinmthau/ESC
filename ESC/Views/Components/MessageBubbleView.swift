import SwiftUI

struct MessageBubbleView: View {
    let email: Email
    
    var body: some View {
        HStack {
            if email.isFromMe {
                Spacer(minLength: 50)
                sentMessageBubble
            } else {
                receivedMessageBubble
                Spacer(minLength: 50)
            }
        }
    }
    
    private var sentMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(MessageCleaner.cleanMessageBody(email.body))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            
            timestampView
                .padding(.trailing, 4)
        }
    }
    
    private var receivedMessageBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MessageCleaner.cleanMessageBody(email.body))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            
            timestampView
                .padding(.leading, 4)
        }
    }
    
    private var timestampView: some View {
        Text(email.timestamp, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

#Preview {
    VStack(spacing: 8) {
        MessageBubbleView(email: Email(
            id: "1",
            messageId: "1",
            sender: "John",
            senderEmail: "john@example.com",
            recipient: "Me",
            recipientEmail: "me@example.com",
            body: "Hello there!",
            snippet: "Hello there!",
            timestamp: Date(),
            isFromMe: false,
            conversation: nil
        ))
        
        MessageBubbleView(email: Email(
            id: "2",
            messageId: "2",
            sender: "Me",
            senderEmail: "me@example.com",
            recipient: "John",
            recipientEmail: "john@example.com",
            body: "Hi! How are you?",
            snippet: "Hi! How are you?",
            timestamp: Date(),
            isFromMe: true,
            conversation: nil
        ))
    }
    .padding()
}