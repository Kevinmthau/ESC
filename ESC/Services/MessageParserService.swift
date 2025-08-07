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
        
        // Extract body and attachments
        let body = extractBody(from: payload)
        let attachmentInfos = extractAttachments(from: payload, messageId: message.id)
        
        let timestamp = Date(timeIntervalSince1970: (TimeInterval(message.internalDate ?? "0") ?? 0) / 1000)
        
        let email = Email(
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
        
        // Create attachment objects (without data for now)
        for attachmentInfo in attachmentInfos {
            let attachment = Attachment(
                id: attachmentInfo.attachmentId,
                filename: attachmentInfo.filename,
                mimeType: attachmentInfo.mimeType,
                size: attachmentInfo.size
            )
            email.attachments.append(attachment)
        }
        
        return email
    }
    
    private static func extractBody(from payload: GmailPayload) -> String {
        var textBody = ""
        var htmlBody = ""
        
        func processPayload(_ payload: GmailPayload) {
            // Skip parts that have attachments (they have filename)
            if payload.filename != nil && !payload.filename!.isEmpty {
                return
            }
            
            // Check for text/plain or text/html in this part
            if payload.mimeType == "text/plain", let data = payload.body?.data {
                let decoded = Base64Utils.decodeURLSafe(data)
                if !decoded.isEmpty {
                    textBody = decoded
                }
            } else if payload.mimeType == "text/html", let data = payload.body?.data {
                let decoded = Base64Utils.decodeURLSafe(data)
                if !decoded.isEmpty {
                    htmlBody = decoded
                }
            }
            
            // Recursively process parts
            if let parts = payload.parts {
                for part in parts {
                    processPayload(part)
                }
            }
        }
        
        processPayload(payload)
        
        // Clean up the body text
        var finalBody = ""
        
        // Prefer plain text, fall back to HTML (stripped of tags)
        if !textBody.isEmpty {
            finalBody = textBody
        } else if !htmlBody.isEmpty {
            // Basic HTML stripping
            finalBody = htmlBody
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let body = payload.body?.data {
            // Handle simple message
            finalBody = Base64Utils.decodeURLSafe(body)
        }
        
        // Remove any attachment filenames that might have leaked into the body
        let lines = finalBody.components(separatedBy: .newlines)
        let cleanedLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Filter out lines that are just filenames or attachment indicators
            if trimmed.hasPrefix("[image:") && trimmed.hasSuffix("]") {
                return false
            }
            // Check if it's just a filename
            if trimmed.contains(".") && !trimmed.contains(" ") {
                let components = trimmed.split(separator: ".")
                if components.count >= 2 {
                    let ext = String(components.last ?? "").lowercased()
                    let imageExts = ["png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "tiff", "tif"]
                    let docExts = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv"]
                    if imageExts.contains(ext) || docExts.contains(ext) {
                        return false
                    }
                }
            }
            return true
        }
        
        return cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractAttachments(from payload: GmailPayload, messageId: String) -> [(attachmentId: String, filename: String, mimeType: String, size: Int)] {
        var attachments: [(attachmentId: String, filename: String, mimeType: String, size: Int)] = []
        
        func processPayload(_ payload: GmailPayload) {
            // Check if this part is an attachment
            if let filename = payload.filename,
               !filename.isEmpty,
               let body = payload.body,
               let attachmentId = body.attachmentId ?? payload.partId {
                attachments.append((
                    attachmentId: attachmentId,
                    filename: filename,
                    mimeType: payload.mimeType ?? "application/octet-stream",
                    size: body.size ?? 0
                ))
            }
            
            // Recursively process parts
            if let parts = payload.parts {
                for part in parts {
                    processPayload(part)
                }
            }
        }
        
        processPayload(payload)
        return attachments
    }
}