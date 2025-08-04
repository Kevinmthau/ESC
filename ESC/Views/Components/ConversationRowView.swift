import SwiftUI

struct ConversationRowView: View {
    let conversation: Conversation
    let contactsService: ContactsService
    
    var body: some View {
        VStack(spacing: 0) {
            conversationContent
            separatorLine
        }
        .background(Color.white)
    }
    
    private var conversationContent: some View {
        HStack(spacing: 12) {
            contactAvatar
            conversationDetails
            unreadIndicator
        }
        .padding(.vertical, 8)
        .frame(minHeight: 66)
    }
    
    private var contactAvatar: some View {
        ContactAvatarView(
            email: conversation.contactEmail,
            name: conversation.contactName,
            contactsService: contactsService,
            size: 50
        )
    }
    
    private var conversationDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            conversationHeader
            messagePreview
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var conversationHeader: some View {
        HStack {
            Text(conversation.contactName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 8)
            
            Text(conversation.lastMessageTimestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()
        }
    }
    
    private var messagePreview: some View {
        Text(conversation.lastMessageSnippet)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var unreadIndicator: some View {
        if !conversation.isRead {
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .fixedSize()
        }
    }
    
    private var separatorLine: some View {
        Divider()
            .background(Color.gray.opacity(0.3))
            .padding(.leading, 62) // Align with text content
    }
}

#Preview {
    List {
        ConversationRowView(
            conversation: Conversation(
                contactName: "John Doe",
                contactEmail: "john@example.com",
                lastMessageTimestamp: Date(),
                lastMessageSnippet: "Hey, how are you doing today?"
            ),
            contactsService: ContactsService()
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.white)
    }
    .listStyle(PlainListStyle())
}