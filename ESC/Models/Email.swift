import Foundation
import SwiftData

@Model
final class Email: @unchecked Sendable {
    var id: String
    var messageId: String
    var threadId: String?
    var sender: String
    var senderEmail: String
    var recipient: String
    var recipientEmail: String
    var body: String
    var snippet: String
    var timestamp: Date
    var isRead: Bool
    var isFromMe: Bool
    
    init(
        id: String,
        messageId: String,
        threadId: String? = nil,
        sender: String,
        senderEmail: String,
        recipient: String,
        recipientEmail: String,
        body: String,
        snippet: String,
        timestamp: Date,
        isRead: Bool = false,
        isFromMe: Bool = false
    ) {
        self.id = id
        self.messageId = messageId
        self.threadId = threadId
        self.sender = sender
        self.senderEmail = senderEmail
        self.recipient = recipient
        self.recipientEmail = recipientEmail
        self.body = body
        self.snippet = snippet
        self.timestamp = timestamp
        self.isRead = isRead
        self.isFromMe = isFromMe
    }
}