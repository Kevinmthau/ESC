import Foundation

struct EmailMessageBuilder {
    private let from: String
    private let to: String
    private let subject: String
    private let body: String
    private let date: Date
    
    init(from: String, to: String, subject: String = "(no subject)", body: String, date: Date = Date()) {
        self.from = from
        self.to = to
        self.subject = subject
        self.body = body
        self.date = date
    }
    
    func buildRFC2822Message() -> String {
        let dateString = DateFormatters.rfc2822.string(from: date)
        
        let message = """
        From: \(from)
        To: \(to)
        Subject: \(subject)
        Date: \(dateString)
        MIME-Version: 1.0
        Content-Type: text/plain; charset=UTF-8
        Content-Transfer-Encoding: quoted-printable

        \(body)
        """
        
        return message
    }
    
    func validate() throws {
        guard EmailValidator.isValid(from) else {
            throw GmailError.invalidMessageFormat
        }
        
        guard EmailValidator.isValid(to) else {
            throw GmailError.invalidRecipient
        }
        
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GmailError.invalidMessageFormat
        }
    }
}