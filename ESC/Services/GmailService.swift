import Foundation
import SwiftData
import Combine

class GmailService: ObservableObject {
    private let authManager = GoogleAuthManager.shared
    private let apiClient = GmailAPIClient()
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isAuthenticated: Bool = false
    
    init() {
        // Subscribe to auth manager's authentication state
        authManager.$isAuthenticated
            .sink { [weak self] authenticated in
                print("🔑 GmailService: Authentication state changed to: \(authenticated)")
                self?.isAuthenticated = authenticated
            }
            .store(in: &cancellables)
        
        // Set initial state
        isAuthenticated = authManager.isAuthenticated
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
                    // Fetch attachment data for each attachment
                    for attachment in email.attachments {
                        if attachment.data == nil && !attachment.id.isEmpty {
                            do {
                                let attachmentData = try await apiClient.fetchAttachment(
                                    messageId: email.messageId,
                                    attachmentId: attachment.id
                                )
                                attachment.data = attachmentData
                                print("✅ Downloaded attachment: \(attachment.filename) (\(attachment.formattedSize))")
                            } catch {
                                print("❌ Failed to fetch attachment \(attachment.filename): \(error)")
                            }
                        }
                    }
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
    
    func sendEmail(to recipientEmail: String, body: String, subject: String? = nil, inReplyTo: String? = nil, attachments: [(filename: String, data: Data, mimeType: String)] = []) async throws {
        print("🚀 Starting email send to: \(recipientEmail) with \(attachments.count) attachments")
        if let replyTo = inReplyTo {
            print("📬 This is a reply to message: \(replyTo)")
        }
        
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
        
        // Determine subject - use provided subject or generate reply subject
        let emailSubject: String
        if let subject = subject, !subject.isEmpty {
            // If replying and subject doesn't start with "Re:", add it
            if inReplyTo != nil && !subject.lowercased().hasPrefix("re:") {
                emailSubject = "Re: \(subject)"
            } else {
                emailSubject = subject
            }
        } else if inReplyTo != nil {
            // This is a reply but we don't have the subject - this shouldn't happen
            // but if it does, at least mark it as a reply
            print("⚠️ GmailService: Reply email missing subject! Using fallback.")
            emailSubject = "Re: (no subject)"
        } else {
            emailSubject = "(no subject)"
        }
        
        // Create and validate email message
        let messageBuilder = EmailMessageBuilder(
            from: userEmail,
            to: recipientEmail,
            subject: emailSubject,
            body: body,
            attachments: attachments,
            inReplyTo: inReplyTo,
            references: inReplyTo  // For replies, references should include the message being replied to
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
    
    // MARK: - Fetch Single Message
    
    func fetchMessage(messageId: String) async throws -> GmailMessage {
        guard isAuthenticated else {
            throw GmailError.notAuthenticated
        }
        
        return try await apiClient.fetchMessage(messageId: messageId)
    }
}