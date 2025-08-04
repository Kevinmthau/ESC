import Foundation

struct Base64Utils {
    /// Decodes Gmail's URL-safe base64 format
    static func decodeURLSafe(_ data: String) -> String {
        var base64 = data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        
        guard let decodedData = Data(base64Encoded: base64),
              let string = String(data: decodedData, encoding: .utf8) else {
            return ""
        }
        
        return string
    }
    
    /// Encodes data to Gmail's URL-safe base64 format (without padding)
    static func encodeURLSafe(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Encodes string to Gmail's URL-safe base64 format
    static func encodeURLSafe(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return encodeURLSafe(data)
    }
}