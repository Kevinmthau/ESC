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
    var htmlBody: String?  // Store HTML version if available
    var snippet: String
    var timestamp: Date
    var isRead: Bool
    var isFromMe: Bool
    var conversation: Conversation?
    var attachments: [Attachment] = []
    var inReplyToMessageId: String?
    var subject: String?
    
    init(
        id: String,
        messageId: String,
        threadId: String? = nil,
        sender: String,
        senderEmail: String,
        recipient: String,
        recipientEmail: String,
        body: String,
        htmlBody: String? = nil,
        snippet: String,
        timestamp: Date,
        isRead: Bool = false,
        isFromMe: Bool = false,
        conversation: Conversation? = nil,
        inReplyToMessageId: String? = nil,
        subject: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.threadId = threadId
        self.sender = sender
        self.senderEmail = senderEmail.lowercased()
        self.recipient = recipient
        self.recipientEmail = recipientEmail.lowercased()
        self.body = body
        self.htmlBody = htmlBody
        self.snippet = snippet
        self.timestamp = timestamp
        self.isRead = isRead
        self.isFromMe = isFromMe
        self.conversation = conversation
        self.inReplyToMessageId = inReplyToMessageId
        self.subject = subject
    }
}