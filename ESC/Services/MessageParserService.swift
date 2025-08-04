import Foundation

struct MessageParserService {
    static func parseGmailMessage(_ message: GmailMessage) -> Email? {
        guard let payload = message.payload else { return nil }
        
        var sender = ""
        var senderEmail = ""
        var recipient = ""
        var recipientEmail = ""
        
        // Extract headers
        for header in payload.headers ?? [] {
            switch header.name.lowercased() {
            case "from":
                (sender, senderEmail) = EmailValidator.parseEmailAddress(header.value)
            case "to":
                (recipient, recipientEmail) = EmailValidator.parseEmailAddress(header.value)
            default:
                break
            }
        }
        
        // Extract body
        let body = extractBody(from: payload)
        
        let timestamp = Date(timeIntervalSince1970: (TimeInterval(message.internalDate ?? "0") ?? 0) / 1000)
        
        return Email(
            id: message.id,
            messageId: message.id,
            threadId: message.threadId,
            sender: sender,
            senderEmail: senderEmail,
            recipient: recipient,
            recipientEmail: recipientEmail,
            body: body,
            snippet: MessageCleaner.createCleanSnippet(body),
            timestamp: timestamp,
            isRead: !(message.labelIds?.contains("UNREAD") ?? false),
            isFromMe: message.labelIds?.contains("SENT") ?? false
        )
    }
    
    private static func extractBody(from payload: GmailPayload) -> String {
        // Handle multipart messages
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/plain" || part.mimeType == "text/html" {
                    if let body = part.body?.data {
                        return Base64Utils.decodeURLSafe(body)
                    }
                }
            }
        }
        
        // Handle simple message
        if let body = payload.body?.data {
            return Base64Utils.decodeURLSafe(body)
        }
        
        return ""
    }
}