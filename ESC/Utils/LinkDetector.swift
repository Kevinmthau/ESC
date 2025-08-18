import Foundation

struct LinkDetector {
    static func detectLinks(in text: String) -> [(url: URL, range: NSRange)] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
        
        var links: [(url: URL, range: NSRange)] = []
        for match in matches {
            if let url = match.url {
                links.append((url: url, range: match.range))
            }
        }
        return links
    }
    
    static func extractFirstLink(from text: String) -> URL? {
        let links = detectLinks(in: text)
        return links.first?.url
    }
    
    static func containsLink(_ text: String) -> Bool {
        return !detectLinks(in: text).isEmpty
    }
}