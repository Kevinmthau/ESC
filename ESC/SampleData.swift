import Foundation
import SwiftData

class SampleData {
    static func createSampleConversations() -> [Conversation] {
        let conversations = [
            createConversation(
                name: "John Doe",
                email: "john@example.com",
                messages: [
                    ("Hey! How's the project going?", false, Date().addingTimeInterval(-3600)),
                    ("Going well! Should be done by Friday", true, Date().addingTimeInterval(-1800)),
                    ("Awesome, let me know if you need help", false, Date().addingTimeInterval(-900))
                ]
            ),
            createConversation(
                name: "Sarah Wilson",
                email: "sarah@company.com",
                messages: [
                    ("Can we schedule a meeting for tomorrow?", false, Date().addingTimeInterval(-7200)),
                    ("Sure! How about 2 PM?", true, Date().addingTimeInterval(-3600)),
                    ("Perfect, see you then!", false, Date().addingTimeInterval(-1800))
                ]
            ),
            createConversation(
                name: "Mike Johnson",
                email: "mike@startup.io",
                messages: [
                    ("The new design looks great!", false, Date().addingTimeInterval(-14400)),
                    ("Thanks! Took a while to get right", true, Date().addingTimeInterval(-10800)),
                    ("Worth the effort for sure", false, Date().addingTimeInterval(-7200)),
                    ("Agreed! Ready for the next phase?", true, Date().addingTimeInterval(-3600))
                ]
            ),
            createConversation(
                name: "Lisa Chen",
                email: "lisa@tech.com",
                messages: [
                    ("Quick question about the API", false, Date().addingTimeInterval(-21600)),
                    ("What's up?", true, Date().addingTimeInterval(-18000)),
                    ("Is the rate limit per user or global?", false, Date().addingTimeInterval(-14400)),
                    ("Per user, 1000 requests per hour", true, Date().addingTimeInterval(-10800))
                ]
            )
        ]
        
        return conversations
    }
    
    private static func createConversation(name: String, email: String, messages: [(String, Bool, Date)]) -> Conversation {
        let lastMessage = messages.last!
        let conversation = Conversation(
            contactName: name,
            contactEmail: email,
            lastMessageTimestamp: lastMessage.2,
            lastMessageSnippet: lastMessage.0,
            isRead: true
        )
        
        for (_, (text, isFromMe, timestamp)) in messages.enumerated() {
            let email = Email(
                id: UUID().uuidString,
                messageId: UUID().uuidString,
                threadId: UUID().uuidString,
                sender: isFromMe ? "Me" : name,
                senderEmail: isFromMe ? "me@myemail.com" : email,
                recipient: isFromMe ? name : "Me",
                recipientEmail: isFromMe ? email : "me@myemail.com",
                body: text,
                snippet: text,
                timestamp: timestamp,
                isRead: true,
                isFromMe: isFromMe
            )
            conversation.addEmail(email)
        }
        
        return conversation
    }
}