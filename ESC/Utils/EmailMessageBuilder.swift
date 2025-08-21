import Foundation

struct EmailMessageBuilder {
    private let from: String
    private let to: [String]  // Changed to array for multiple recipients
    private let cc: [String]
    private let bcc: [String]
    private let subject: String
    private let body: String
    private let date: Date
    private let attachments: [(filename: String, data: Data, mimeType: String)]
    private let inReplyTo: String?
    private let references: String?
    
    init(from: String, to: [String], cc: [String] = [], bcc: [String] = [], subject: String = "(no subject)", body: String, date: Date = Date(), attachments: [(filename: String, data: Data, mimeType: String)] = [], inReplyTo: String? = nil, references: String? = nil) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.date = date
        self.attachments = attachments
        self.inReplyTo = inReplyTo
        self.references = references
    }
    
    // Convenience init for single recipient (backward compatibility)
    init(from: String, to: String, subject: String = "(no subject)", body: String, date: Date = Date(), attachments: [(filename: String, data: Data, mimeType: String)] = [], inReplyTo: String? = nil, references: String? = nil) {
        self.init(from: from, to: [to], cc: [], bcc: [], subject: subject, body: body, date: date, attachments: attachments, inReplyTo: inReplyTo, references: references)
    }
    
    func buildRFC2822Message() -> String {
        let dateString = DateFormatters.rfc2822.string(from: date)
        
        if attachments.isEmpty {
            // Simple message without attachments
            var headers = """
            From: \(from)
            To: \(to.joined(separator: ", "))
            Subject: \(subject)
            Date: \(dateString)
            """
            
            // Add CC and BCC if present
            if !cc.isEmpty {
                headers += "\nCc: \(cc.joined(separator: ", "))"
            }
            if !bcc.isEmpty {
                headers += "\nBcc: \(bcc.joined(separator: ", "))"
            }
            
            // Add reply headers if present
            if let inReplyTo = inReplyTo {
                headers += "\nIn-Reply-To: <\(inReplyTo)>"
            }
            if let references = references {
                headers += "\nReferences: <\(references)>"
            }
            
            let message = """
            \(headers)
            MIME-Version: 1.0
            Content-Type: text/plain; charset=UTF-8
            Content-Transfer-Encoding: quoted-printable

            \(body)
            """
            
            return message
        } else {
            // Multipart message with attachments
            let boundary = "boundary_\(UUID().uuidString)"
            
            var headers = """
            From: \(from)
            To: \(to.joined(separator: ", "))
            Subject: \(subject)
            Date: \(dateString)
            """
            
            // Add CC and BCC if present
            if !cc.isEmpty {
                headers += "\nCc: \(cc.joined(separator: ", "))"
            }
            if !bcc.isEmpty {
                headers += "\nBcc: \(bcc.joined(separator: ", "))"
            }
            
            // Add reply headers if present
            if let inReplyTo = inReplyTo {
                headers += "\nIn-Reply-To: <\(inReplyTo)>"
            }
            if let references = references {
                headers += "\nReferences: <\(references)>"
            }
            
            var message = """
            \(headers)
            MIME-Version: 1.0
            Content-Type: multipart/mixed; boundary="\(boundary)"

            --\(boundary)
            Content-Type: text/plain; charset=UTF-8
            Content-Transfer-Encoding: quoted-printable

            \(body)

            """
            
            // Add attachments
            for attachment in attachments {
                let base64Data = attachment.data.base64EncodedString(options: .lineLength64Characters)
                message += """
                --\(boundary)
                Content-Type: \(attachment.mimeType); name="\(attachment.filename)"
                Content-Disposition: attachment; filename="\(attachment.filename)"
                Content-Transfer-Encoding: base64

                \(base64Data)

                """
            }
            
            message += "--\(boundary)--"
            
            return message
        }
    }
    
    func validate() throws {
        // Extract email from "Name <email@example.com>" format if present
        let fromEmail = extractEmailAddress(from: from)
        
        guard EmailValidator.isValid(fromEmail) else {
            throw AppError.invalidEmailFormat
        }
        
        // Validate all To recipients
        for recipient in to {
            let toEmail = extractEmailAddress(from: recipient)
            guard EmailValidator.isValid(toEmail) else {
                throw AppError.invalidEmail(recipient)
            }
        }
        
        // Validate all CC recipients
        for recipient in cc {
            let ccEmail = extractEmailAddress(from: recipient)
            guard EmailValidator.isValid(ccEmail) else {
                throw AppError.invalidEmail(recipient)
            }
        }
        
        // Validate all BCC recipients
        for recipient in bcc {
            let bccEmail = extractEmailAddress(from: recipient)
            guard EmailValidator.isValid(bccEmail) else {
                throw AppError.invalidEmail(recipient)
            }
        }
        
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidEmailFormat
        }
    }
    
    private func extractEmailAddress(from field: String) -> String {
        // Handle "Name <email@example.com>" format
        if let startIndex = field.firstIndex(of: "<"),
           let endIndex = field.firstIndex(of: ">"),
           startIndex < endIndex {
            let email = String(field[field.index(after: startIndex)..<endIndex])
            return email.trimmingCharacters(in: .whitespaces)
        }
        // Return as-is if not in angle bracket format
        return field
    }
}