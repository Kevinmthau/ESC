import SwiftUI

struct ConversationRowView: View {
    let conversation: Conversation
    @EnvironmentObject private var contactsService: ContactsService
    
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
    
    @ViewBuilder
    private var contactAvatar: some View {
        if conversation.isGroupConversation {
            // Show group icon for group conversations
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.gray)
            }
        } else {
            ContactAvatarView(
                email: conversation.contactEmail,
                name: conversation.contactName,
                size: 50
            )
        }
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
            HStack(spacing: 4) {
                Text(conversation.contactName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if conversation.isGroupConversation && conversation.participantEmails.count > 0 {
                    Text("(\(conversation.participantEmails.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 8)
            
            Text(formatTimestamp(conversation.lastMessageTimestamp))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if it's today
        if calendar.isDateInToday(date) {
            // Show time only (e.g., "3:45 PM")
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }
        
        // Check if it's yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // Check if it's within the last week
        if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            // Show day of week (e.g., "Monday")
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
        
        // More than a week old - show mm/dd/yy
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: date)
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
            )
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.white)
    }
    .listStyle(PlainListStyle())
    .environmentObject(ContactsService.shared)
}