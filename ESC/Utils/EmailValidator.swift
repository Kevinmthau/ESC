import Foundation

struct EmailValidator {
    static func isValid(_ email: String) -> Bool {
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }
    
    static func parseEmailAddress(_ address: String) -> (name: String, email: String) {
        // Parse "Name <email@domain.com>" format
        if let range = address.range(of: "<.*>", options: .regularExpression) {
            let email = String(address[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>")).lowercased()
            let name = address.replacingOccurrences(of: " <.*>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? email : name, email)
        }
        
        // Just an email address - normalize to lowercase
        let normalizedEmail = address.lowercased()
        return (address, normalizedEmail)
    }
    
    static func formatEmailAddress(name: String, email: String) -> String {
        if name.isEmpty || name == email {
            return email
        }
        return "\(name) <\(email)>"
    }
}