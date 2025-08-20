import Foundation

// MARK: - Validation Result
enum ValidationResult {
    case valid
    case invalid(String)
    
    var isValid: Bool {
        switch self {
        case .valid: return true
        case .invalid: return false
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .valid: return nil
        case .invalid(let message): return message
        }
    }
}

// MARK: - Validation Service
class ValidationService {
    static let shared = ValidationService()
    
    private init() {}
    
    // MARK: - Email Validation
    
    func validateEmail(_ email: String) -> ValidationResult {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return .invalid("Email address is required")
        }
        
        if !EmailValidator.isValid(trimmed) {
            return .invalid("Please enter a valid email address")
        }
        
        return .valid
    }
    
    func validateEmails(_ emails: [String]) -> ValidationResult {
        if emails.isEmpty {
            return .invalid("At least one email address is required")
        }
        
        for email in emails {
            let result = validateEmail(email)
            if !result.isValid {
                return result
            }
        }
        
        return .valid
    }
    
    // MARK: - Message Validation
    
    func validateMessageBody(_ body: String) -> ValidationResult {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return .invalid("Message cannot be empty")
        }
        
        if trimmed.count > 500000 { // Gmail's limit is around 25MB, but we'll use a character limit
            return .invalid("Message is too long")
        }
        
        return .valid
    }
    
    func validateSubject(_ subject: String) -> ValidationResult {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count > 998 { // RFC 2822 limit
            return .invalid("Subject is too long (max 998 characters)")
        }
        
        return .valid
    }
    
    // MARK: - Attachment Validation
    
    func validateAttachment(filename: String, data: Data, mimeType: String) -> ValidationResult {
        // Check file size (25MB limit for Gmail)
        let maxSize = 25 * 1024 * 1024 // 25MB in bytes
        if data.count > maxSize {
            let sizeInMB = data.count / (1024 * 1024)
            return .invalid("Attachment too large: \(sizeInMB)MB (max 25MB)")
        }
        
        // Check filename
        if filename.isEmpty {
            return .invalid("Attachment filename is required")
        }
        
        // Check for dangerous file extensions
        let dangerousExtensions = ["exe", "bat", "cmd", "com", "pif", "scr", "vbs", "js"]
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        if dangerousExtensions.contains(fileExtension) {
            return .invalid("File type .\(fileExtension) is not allowed")
        }
        
        // Validate MIME type
        if mimeType.isEmpty {
            return .invalid("MIME type is required")
        }
        
        return .valid
    }
    
    func validateAttachments(_ attachments: [(filename: String, data: Data, mimeType: String)]) -> ValidationResult {
        // Check total size
        let totalSize = attachments.reduce(0) { $0 + $1.data.count }
        let maxTotalSize = 25 * 1024 * 1024 // 25MB total
        
        if totalSize > maxTotalSize {
            let sizeInMB = totalSize / (1024 * 1024)
            return .invalid("Total attachment size too large: \(sizeInMB)MB (max 25MB)")
        }
        
        // Validate each attachment
        for attachment in attachments {
            let result = validateAttachment(
                filename: attachment.filename,
                data: attachment.data,
                mimeType: attachment.mimeType
            )
            if !result.isValid {
                return result
            }
        }
        
        return .valid
    }
    
    // MARK: - Compose Validation
    
    func validateComposeForm(recipients: [String],
                            cc: [String] = [],
                            bcc: [String] = [],
                            subject: String,
                            body: String,
                            attachments: [(filename: String, data: Data, mimeType: String)] = []) -> ValidationResult {
        
        // Validate recipients
        let allRecipients = recipients + cc + bcc
        let recipientResult = validateEmails(allRecipients)
        if !recipientResult.isValid {
            return recipientResult
        }
        
        // Validate subject
        let subjectResult = validateSubject(subject)
        if !subjectResult.isValid {
            return subjectResult
        }
        
        // Validate body
        let bodyResult = validateMessageBody(body)
        if !bodyResult.isValid {
            return bodyResult
        }
        
        // Validate attachments if any
        if !attachments.isEmpty {
            let attachmentResult = validateAttachments(attachments)
            if !attachmentResult.isValid {
                return attachmentResult
            }
        }
        
        return .valid
    }
    
    // MARK: - User Input Validation
    
    func validateUsername(_ username: String) -> ValidationResult {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return .invalid("Username is required")
        }
        
        if trimmed.count < 3 {
            return .invalid("Username must be at least 3 characters")
        }
        
        if trimmed.count > 50 {
            return .invalid("Username is too long (max 50 characters)")
        }
        
        // Check for valid characters
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        if trimmed.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
            return .invalid("Username contains invalid characters")
        }
        
        return .valid
    }
    
    func validatePassword(_ password: String) -> ValidationResult {
        if password.isEmpty {
            return .invalid("Password is required")
        }
        
        if password.count < 8 {
            return .invalid("Password must be at least 8 characters")
        }
        
        // Check for complexity
        let hasUppercase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowercase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        
        if !hasUppercase || !hasLowercase || !hasNumber {
            return .invalid("Password must contain uppercase, lowercase, and numbers")
        }
        
        return .valid
    }
    
    // MARK: - Search Validation
    
    func validateSearchQuery(_ query: String) -> ValidationResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count > 200 {
            return .invalid("Search query is too long")
        }
        
        // Check for SQL injection patterns
        let dangerousPatterns = ["DROP", "DELETE", "INSERT", "UPDATE", "EXEC", "--", "/*", "*/"]
        let uppercased = trimmed.uppercased()
        for pattern in dangerousPatterns {
            if uppercased.contains(pattern) {
                return .invalid("Search query contains invalid characters")
            }
        }
        
        return .valid
    }
}

// MARK: - Validation Extensions
extension String {
    var isValidEmailAddress: Bool {
        ValidationService.shared.validateEmail(self).isValid
    }
    
    var isValidUsername: Bool {
        ValidationService.shared.validateUsername(self).isValid
    }
    
    var isValidSearchQuery: Bool {
        ValidationService.shared.validateSearchQuery(self).isValid
    }
}