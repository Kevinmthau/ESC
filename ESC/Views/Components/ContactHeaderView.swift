import SwiftUI

struct ContactHeaderView: View {
    let conversation: Conversation
    @EnvironmentObject private var contactsService: ContactsService
    
    var body: some View {
        HStack {
            Spacer()
            
            ContactAvatarView(
                email: conversation.contactEmail,
                name: conversation.contactName,
                size: 50
            )
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
}

#Preview {
    ContactHeaderView(
        conversation: Conversation(
            contactName: "John Doe",
            contactEmail: "john@example.com",
            lastMessageTimestamp: Date(),
            lastMessageSnippet: "Hey, how are you?"
        )
    )
    .environmentObject(ContactsService.shared)
}