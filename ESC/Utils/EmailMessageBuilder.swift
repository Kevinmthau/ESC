import Foundation

struct EmailMessageBuilder {
    private let from: String
    private let to: String
    private let subject: String
    private let body: String
    private let date: Date
    private let attachments: [(filename: String, data: Data, mimeType: String)]
    private let inReplyTo: String?
    private let references: String?
    
    init(from: String, to: String, subject: String = "(no subject)", body: String, date: Date = Date(), attachments: [(filename: String, data: Data, mimeType: String)] = [], inReplyTo: String? = nil, references: String? = nil) {
        self.from = from
        self.to = to
        self.subject = subject
        self.body = body
        self.date = date
        self.attachments = attachments
        self.inReplyTo = inReplyTo
        self.references = references
    }
    
    func buildRFC2822Message() -> String {
        let dateString = DateFormatters.rfc2822.string(from: date)
        
        if attachments.isEmpty {
            // Simple message without attachments
            var headers = """
            From: \(from)
            To: \(to)
            Subject: \(subject)
            Date: \(dateString)
            """
            
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
            To: \(to)
            Subject: \(subject)
            Date: \(dateString)
            """
            
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
        let toEmail = extractEmailAddress(from: to)
        
        guard EmailValidator.isValid(fromEmail) else {
            throw GmailError.invalidMessageFormat
        }
        
        guard EmailValidator.isValid(toEmail) else {
            throw GmailError.invalidRecipient
        }
        
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GmailError.invalidMessageFormat
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