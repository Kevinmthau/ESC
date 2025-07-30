import Foundation

struct MessageCleaner {
    static func cleanMessageBody(_ body: String) -> String {
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split into lines for processing
        let lines = cleanedBody.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var inQuotedSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if this line starts a quoted section
            if isQuotedLine(trimmedLine) {
                inQuotedSection = true
                continue
            }
            
            // Skip empty lines that might be part of quoted sections
            if inQuotedSection && trimmedLine.isEmpty {
                continue
            }
            
            // If we're not in a quoted section, add the line
            if !inQuotedSection {
                cleanedLines.append(line)
            }
        }
        
        // Join back together and trim
        let result = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Return original if cleaning resulted in empty string
        return result.isEmpty ? body : result
    }
    
    private static func isQuotedLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Common quoted text patterns
        let quotedIndicators = [
            // Gmail-style quotes starting with ">"
            trimmedLine.hasPrefix(">"),
            // "On [date], [person] wrote:" pattern
            trimmedLine.hasPrefix("On ") && trimmedLine.contains("wrote:"),
            // Email headers in quoted text
            trimmedLine.hasPrefix("From:"),
            trimmedLine.hasPrefix("Sent:"),
            trimmedLine.hasPrefix("To:"),
            trimmedLine.hasPrefix("Subject:"),
            trimmedLine.hasPrefix("Date:"),
            // Common forwarded/reply indicators
            trimmedLine.contains("Original Message"),
            trimmedLine.contains("Forwarded message"),
            trimmedLine.contains("Begin forwarded message:"),
            // Separator lines
            trimmedLine.hasPrefix("-----") && trimmedLine.count > 10,
            trimmedLine.hasPrefix("_____") && trimmedLine.count > 10,
            // HTML indicators
            trimmedLine.contains("<div") && trimmedLine.contains("quoted"),
            // Mobile signatures that often appear in quoted text
            trimmedLine.hasPrefix("Sent from my iPhone"),
            trimmedLine.hasPrefix("Sent from my Android"),
            trimmedLine.hasPrefix("Get Outlook for")
        ]
        
        return quotedIndicators.contains(true)
    }
    
    static func createCleanSnippet(_ body: String, maxLength: Int = 100) -> String {
        let cleanedBody = cleanMessageBody(body)
        
        // Remove extra whitespace and newlines for snippet
        let singleLine = cleanedBody
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Truncate to max length
        if singleLine.count > maxLength {
            let endIndex = singleLine.index(singleLine.startIndex, offsetBy: maxLength)
            return String(singleLine[..<endIndex]) + "..."
        }
        
        return singleLine
    }
}