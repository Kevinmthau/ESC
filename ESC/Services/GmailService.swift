import Foundation
import SwiftData

class GmailService: ObservableObject {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private let authManager = GoogleAuthManager.shared
    
    var isAuthenticated: Bool {
        let authenticated = authManager.isAuthenticated
        print("🔑 GmailService: isAuthenticated called, returning: \(authenticated)")
        return authenticated
    }
    
    func signOut() {
        authManager.signOut()
        print("✅ GmailService: User signed out")
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws {
        try await authManager.authenticate()
    }
    
    private var accessToken: String? {
        authManager.accessToken
    }
    
    // MARK: - Fetch Emails
    
    func fetchEmails() async throws -> [Email] {
        guard accessToken != nil else {
            throw GmailError.notAuthenticated
        }
        
        // Fetch message list first
        let messageIds = try await fetchMessageIds()
        
        // Fetch full messages
        var emails: [Email] = []
        for messageId in messageIds {
            if let email = try await fetchMessage(messageId: messageId) {
                emails.append(email)
            }
        }
        
        return emails
    }
    
    private func fetchMessageIds() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/users/me/messages") else {
            throw GmailError.invalidURL
        }
        
        guard let token = accessToken else {
            throw GmailError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                try await authManager.refreshAccessToken()
                guard let refreshedToken = accessToken else {
                    throw GmailError.notAuthenticated
                }
                request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                let (retryData, _) = try await URLSession.shared.data(for: request)
                let messageResponse = try JSONDecoder().decode(MessageListResponse.self, from: retryData)
                return messageResponse.messages?.map { $0.id } ?? []
            }
            
            let messageResponse = try JSONDecoder().decode(MessageListResponse.self, from: data)
            return messageResponse.messages?.map { $0.id } ?? []
        } catch {
            throw GmailError.networkError
        }
    }
    
    private func fetchMessage(messageId: String) async throws -> Email? {
        guard let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)") else {
            throw GmailError.invalidURL
        }
        
        guard let token = accessToken else {
            throw GmailError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                try await authManager.refreshAccessToken()
                guard let refreshedToken = accessToken else {
                    throw GmailError.notAuthenticated
                }
                request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                let (retryData, _) = try await URLSession.shared.data(for: request)
                let message = try JSONDecoder().decode(GmailMessage.self, from: retryData)
                return parseGmailMessage(message)
            }
            
            let message = try JSONDecoder().decode(GmailMessage.self, from: data)
            return parseGmailMessage(message)
        } catch {
            throw GmailError.networkError
        }
    }
    
    // MARK: - Parse Gmail Message
    
    private func parseGmailMessage(_ message: GmailMessage) -> Email? {
        guard let payload = message.payload else { return nil }
        
        var sender = ""
        var senderEmail = ""
        var recipient = ""
        var recipientEmail = ""
        var body = ""
        
        // Extract headers
        for header in payload.headers ?? [] {
            switch header.name.lowercased() {
            case "from":
                (sender, senderEmail) = parseEmailAddress(header.value)
            case "to":
                (recipient, recipientEmail) = parseEmailAddress(header.value)
            default:
                break
            }
        }
        
        // Extract body
        body = extractBody(from: payload)
        
        let timestamp = Date(timeIntervalSince1970: (TimeInterval(message.internalDate ?? "0") ?? 0) / 1000)
        
        return Email(
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
    }
    
    private func parseEmailAddress(_ address: String) -> (name: String, email: String) {
        // Parse "Name <email@domain.com>" format
        if let range = address.range(of: "<.*>", options: .regularExpression) {
            let email = String(address[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            let name = address.replacingOccurrences(of: " <.*>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? email : name, email)
        }
        
        // Just an email address
        return (address, address)
    }
    
    private func extractBody(from payload: GmailPayload) -> String {
        // Handle multipart messages
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/plain" || part.mimeType == "text/html" {
                    if let body = part.body?.data {
                        return decodeBase64URLSafe(body)
                    }
                }
            }
        }
        
        // Handle simple message
        if let body = payload.body?.data {
            return decodeBase64URLSafe(body)
        }
        
        return ""
    }
    
    private func decodeBase64URLSafe(_ data: String) -> String {
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
    
    // MARK: - Thread Emails into Conversations
    
    func createConversations(from emails: [Email]) -> [Conversation] {
        var conversationDict: [String: Conversation] = [:]
        
        for email in emails {
            let contactEmail = email.isFromMe ? email.recipientEmail : email.senderEmail
            let contactName = email.isFromMe ? email.recipient : email.sender
            
            if let conversation = conversationDict[contactEmail] {
                conversation.addEmail(email)
            } else {
                let conversation = Conversation(
                    contactName: contactName,
                    contactEmail: contactEmail,
                    lastMessageTimestamp: email.timestamp,
                    lastMessageSnippet: email.snippet,
                    isRead: email.isRead
                )
                conversation.addEmail(email)
                conversationDict[contactEmail] = conversation
            }
        }
        
        return Array(conversationDict.values)
    }
    
    // MARK: - Send Email
    
    func sendEmail(to recipientEmail: String, body: String) async throws {
        print("🚀 Starting email send to: \(recipientEmail)")
        
        guard let token = accessToken else {
            print("❌ No access token available")
            throw GmailError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/users/me/messages/send") else {
            print("❌ Invalid URL: \(baseURL)/users/me/messages/send")
            throw GmailError.invalidURL
        }
        
        print("🔑 Using access token: \(String(token.prefix(20)))...")
        
        // Get user's email address for From field
        let userEmail: String
        do {
            userEmail = try await getUserEmail()
            print("📧 Sending from: \(userEmail)")
        } catch {
            print("❌ Failed to get user email: \(error)")
            throw error
        }
        
        // Create email message in RFC2822 format
        let message = createEmailMessage(from: userEmail, to: recipientEmail, body: body)
        print("📝 Created email message:")
        print(message)
        print("📝 Message length: \(message.count) characters")
        
        // Validate message format
        validateEmailMessage(message)
        
        // Encode to base64url (Gmail's format) - no padding
        let messageData = Data(message.utf8)
        let base64Message = messageData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        print("🔐 Base64url encoded message length: \(base64Message.count)")
        
        let requestBody = [
            "raw": base64Message
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("📦 Request body size: \(request.httpBody?.count ?? 0) bytes")
        } catch {
            print("❌ Failed to serialize request body: \(error)")
            throw GmailError.networkError
        }
        
        print("🌐 Making API request to: \(url)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response status: \(httpResponse.statusCode)")
                print("📡 Response headers: \(httpResponse.allHeaderFields)")
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📡 Response body: \(responseString)")
                } else {
                    print("📡 Unable to decode response body as UTF-8")
                    print("📡 Raw response data length: \(data.count) bytes")
                }
                
                // Log specific Gmail API errors
                if httpResponse.statusCode >= 400 {
                    print("🚨 Gmail API Error Details:")
                    print("   Status Code: \(httpResponse.statusCode)")
                    print("   Content-Type: \(httpResponse.allHeaderFields["Content-Type"] ?? "unknown")")
                    
                    if let responseString = String(data: data, encoding: .utf8) {
                        // Try to parse as JSON error
                        if let errorData = responseString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                           let error = json["error"] as? [String: Any] {
                            print("   Error Code: \(error["code"] ?? "unknown")")
                            print("   Error Message: \(error["message"] ?? "unknown")")
                            if let details = error["details"] as? [[String: Any]] {
                                print("   Error Details: \(details)")
                            }
                        }
                    }
                }
                
                if httpResponse.statusCode == 401 {
                    print("🔄 Token expired, refreshing...")
                    // Token expired, refresh and retry
                    try await authManager.refreshAccessToken()
                    
                    guard let newToken = accessToken else {
                        print("❌ Failed to refresh token")
                        throw GmailError.notAuthenticated
                    }
                    
                    print("🔑 Using refreshed token: \(String(newToken.prefix(20)))...")
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                    
                    if let retryHttpResponse = retryResponse as? HTTPURLResponse {
                        print("📡 Retry response status: \(retryHttpResponse.statusCode)")
                        if let retryResponseString = String(data: retryData, encoding: .utf8) {
                            print("📡 Retry response body: \(retryResponseString)")
                        }
                        
                        if retryHttpResponse.statusCode < 200 || retryHttpResponse.statusCode >= 300 {
                            print("❌ Gmail send failed after retry with status: \(retryHttpResponse.statusCode)")
                            throw GmailError.networkError
                        } else {
                            print("✅ Email sent successfully after retry with status: \(retryHttpResponse.statusCode)")
                        }
                    }
                } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    print("❌ Gmail send failed with status: \(httpResponse.statusCode)")
                    throw GmailError.networkError
                } else {
                    print("✅ Email sent successfully with status: \(httpResponse.statusCode)")
                }
            } else {
                print("❌ No HTTP response received")
                throw GmailError.networkError
            }
        } catch {
            print("❌ Network error during Gmail send: \(error)")
            throw GmailError.networkError
        }
    }
    
    func getUserEmail() async throws -> String {
        guard let url = URL(string: "\(baseURL)/users/me/profile") else {
            throw GmailError.invalidURL
        }
        
        guard let token = accessToken else {
            throw GmailError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                try await authManager.refreshAccessToken()
                guard let refreshedToken = accessToken else {
                    throw GmailError.notAuthenticated
                }
                request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                let (retryData, _) = try await URLSession.shared.data(for: request)
                let profile = try JSONDecoder().decode(GmailProfile.self, from: retryData)
                return profile.emailAddress
            }
            
            let profile = try JSONDecoder().decode(GmailProfile.self, from: data)
            return profile.emailAddress
        } catch {
            throw GmailError.networkError
        }
    }
    
    private func createEmailMessage(from senderEmail: String, to recipientEmail: String, body: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        let dateString = dateFormatter.string(from: Date())
        
        // Gmail API requires a Subject header, even if empty
        let message = """
        From: \(senderEmail)
        To: \(recipientEmail)
        Subject: (no subject)
        Date: \(dateString)
        MIME-Version: 1.0
        Content-Type: text/plain; charset=UTF-8
        Content-Transfer-Encoding: quoted-printable

        \(body)
        """
        
        return message
    }
    
    private func validateEmailMessage(_ message: String) {
        print("🔍 Validating email message format...")
        
        let lines = message.components(separatedBy: .newlines)
        var hasFrom = false
        var hasTo = false
        var hasSubject = false
        var hasDate = false
        var hasMimeVersion = false
        var hasContentType = false
        var hasEmptyLine = false
        
        for (index, line) in lines.enumerated() {
            if line.starts(with: "From:") { hasFrom = true }
            if line.starts(with: "To:") { hasTo = true }
            if line.starts(with: "Subject:") { hasSubject = true }
            if line.starts(with: "Date:") { hasDate = true }
            if line.starts(with: "MIME-Version:") { hasMimeVersion = true }
            if line.starts(with: "Content-Type:") { hasContentType = true }
            if line.isEmpty && index > 0 { hasEmptyLine = true }
        }
        
        print("✅ Header validation:")
        print("   From header: \(hasFrom ? "✓" : "✗")")
        print("   To header: \(hasTo ? "✓" : "✗")")
        print("   Subject header: \(hasSubject ? "✓" : "✗")")
        print("   Date header: \(hasDate ? "✓" : "✗")")
        print("   MIME-Version header: \(hasMimeVersion ? "✓" : "✗")")
        print("   Content-Type header: \(hasContentType ? "✓" : "✗")")
        print("   Header/body separator: \(hasEmptyLine ? "✓" : "✗")")
        
        if hasFrom && hasTo && hasSubject && hasDate && hasMimeVersion && hasContentType && hasEmptyLine {
            print("✅ Email message format is valid!")
        } else {
            print("⚠️ Email message format may have issues")
        }
    }
}

// MARK: - Data Models for Gmail API

struct MessageListResponse: Codable {
    let messages: [MessageItem]?
}

struct MessageItem: Codable {
    let id: String
    let threadId: String
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String?
    let snippet: String?
    let internalDate: String?
    let labelIds: [String]?
    let payload: GmailPayload?
}

struct GmailPayload: Codable {
    let headers: [GmailHeader]?
    let parts: [GmailPayload]?
    let body: GmailBody?
    let mimeType: String?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailBody: Codable {
    let data: String?
}

struct GmailProfile: Codable {
    let emailAddress: String
    let messagesTotal: Int?
    let threadsTotal: Int?
    let historyId: String?
}

// MARK: - Error Types

enum GmailError: Error {
    case notAuthenticated
    case invalidURL
    case networkError
    case parseError
}