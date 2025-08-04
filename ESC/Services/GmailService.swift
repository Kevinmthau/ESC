import Foundation
import SwiftData

class GmailService: ObservableObject {
    private let authManager = GoogleAuthManager.shared
    private let apiClient = GmailAPIClient()
    
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
    
    // MARK: - Fetch Emails
    
    func fetchEmails() async throws -> [Email] {
        guard isAuthenticated else {
            throw GmailError.notAuthenticated
        }
        
        // Fetch message list first
        let messageIds = try await apiClient.fetchMessageIds()
        
        // Fetch full messages
        var emails: [Email] = []
        for messageId in messageIds {
            do {
                let gmailMessage = try await apiClient.fetchMessage(messageId: messageId)
                if let email = MessageParserService.parseGmailMessage(gmailMessage) {
                    emails.append(email)
                }
            } catch {
                // Continue with other messages if one fails
                print("Failed to fetch message \(messageId): \(error)")
            }
        }
        
        return emails
    }
    
    
    // MARK: - Send Email
    
    func sendEmail(to recipientEmail: String, body: String) async throws {
        print("🚀 Starting email send to: \(recipientEmail)")
        
        guard isAuthenticated else {
            throw GmailError.notAuthenticated
        }
        
        // Validate recipient email
        guard EmailValidator.isValid(recipientEmail) else {
            throw GmailError.invalidRecipient
        }
        
        // Get user's email address for From field
        let userEmail: String
        do {
            let profile = try await apiClient.getUserProfile()
            userEmail = profile.emailAddress
            print("📧 Sending from: \(userEmail)")
        } catch {
            print("❌ Failed to get user email: \(error)")
            throw error
        }
        
        // Create and validate email message
        let messageBuilder = EmailMessageBuilder(
            from: userEmail,
            to: recipientEmail,
            body: body
        )
        
        do {
            try messageBuilder.validate()
        } catch {
            throw GmailError.invalidMessageFormat
        }
        
        let message = messageBuilder.buildRFC2822Message()
        print("📝 Created email message (length: \(message.count) characters)")
        
        // Encode to Gmail's base64url format
        let base64Message = Base64Utils.encodeURLSafe(message)
        print("🔐 Base64url encoded message length: \(base64Message.count)")
        
        // Send via API client
        do {
            let response = try await apiClient.sendMessage(raw: base64Message)
            print("✅ Email sent successfully with ID: \(response.id)")
        } catch {
            print("❌ Failed to send email: \(error)")
            throw GmailError.sendFailed(error.localizedDescription)
        }
    }
    
    func getUserEmail() async throws -> String {
        let profile = try await apiClient.getUserProfile()
        return profile.emailAddress
    }
}