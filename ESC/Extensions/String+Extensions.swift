import Foundation

extension String {
    /// Validates if the string is a valid email address
    var isValidEmail: Bool {
        EmailValidator.isValid(self)
    }
    
    /// Trims whitespace and newlines from the string
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Returns true if the string is empty after trimming
    var isBlank: Bool {
        self.trimmed.isEmpty
    }
    
    /// Truncates the string to a specified length
    func truncated(to length: Int, trailing: String = "...") -> String {
        guard self.count > length else { return self }
        return String(self.prefix(length)) + trailing
    }
    
    /// Extracts the domain from an email address
    var emailDomain: String? {
        guard self.contains("@") else { return nil }
        return self.split(separator: "@").last.map(String.init)
    }
    
    /// Extracts the username from an email address
    var emailUsername: String? {
        guard self.contains("@") else { return nil }
        return self.split(separator: "@").first.map(String.init)
    }
    
    /// Converts the string to a human-readable name from email format
    var emailToName: String {
        guard let username = self.emailUsername else { return self }
        return username
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    /// Removes HTML tags from the string
    var stripHTML: String {
        guard self.contains("<") && self.contains(">") else { return self }
        
        var text = self
        
        // Replace common HTML entities
        let htmlEntities = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]
        
        for (entity, replacement) in htmlEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Replace line break tags with newlines
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        
        // Remove all HTML tags
        let pattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: text.utf16.count)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // Clean up multiple consecutive newlines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return text.trimmed
    }
    
    /// Converts a comma-separated string to an array
    var commaSeparatedArray: [String] {
        guard !self.isEmpty else { return [] }
        return self.split(separator: ",").map { String($0).trimmed }
    }
    
    /// Returns the initials from a name
    var initials: String {
        let words = self.split(separator: " ")
        let initials = words.compactMap { $0.first }.prefix(2)
        return String(initials).uppercased()
    }
}

// MARK: - Localization
extension String {
    /// Returns a localized version of the string
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// Returns a localized version with format arguments
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
}