import Foundation
import SwiftData

@Model
final class Email: @unchecked Sendable {
    var id: String
    var messageId: String
    var threadId: String?
    var sender: String
    var senderEmail: String
    var recipient: String  // Primary recipient display name
    var recipientEmail: String  // Primary recipient email
    var allRecipientsString: String = ""  // All recipient emails (To, CC, BCC) as comma-separated
    var toRecipientsString: String = ""  // To field recipients as comma-separated
    var ccRecipientsString: String = ""  // CC field recipients as comma-separated
    var bccRecipientsString: String = ""  // BCC field recipients as comma-separated
    
    // Computed properties for array access - marked as @Transient to exclude from persistence
    @Transient var allRecipients: [String] {
        get { allRecipientsString.isEmpty ? [] : allRecipientsString.split(separator: ",").map { String($0) } }
        set { allRecipientsString = newValue.joined(separator: ",") }
    }
    
    @Transient var toRecipients: [String] {
        get { toRecipientsString.isEmpty ? [] : toRecipientsString.split(separator: ",").map { String($0) } }
        set { toRecipientsString = newValue.joined(separator: ",") }
    }
    
    @Transient var ccRecipients: [String] {
        get { ccRecipientsString.isEmpty ? [] : ccRecipientsString.split(separator: ",").map { String($0) } }
        set { ccRecipientsString = newValue.joined(separator: ",") }
    }
    
    @Transient var bccRecipients: [String] {
        get { bccRecipientsString.isEmpty ? [] : bccRecipientsString.split(separator: ",").map { String($0) } }
        set { bccRecipientsString = newValue.joined(separator: ",") }
    }
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
        allRecipients: [String] = [],
        toRecipients: [String] = [],
        ccRecipients: [String] = [],
        bccRecipients: [String] = [],
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
        self.allRecipientsString = allRecipients.map { $0.lowercased() }.joined(separator: ",")
        self.toRecipientsString = toRecipients.map { $0.lowercased() }.joined(separator: ",")
        self.ccRecipientsString = ccRecipients.map { $0.lowercased() }.joined(separator: ",")
        self.bccRecipientsString = bccRecipients.map { $0.lowercased() }.joined(separator: ",")
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