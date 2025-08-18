import Foundation
import SwiftData
import Combine

class GmailService: ObservableObject {
    private let authManager = GoogleAuthManager.shared
    private let apiClient = GmailAPIClient()
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isAuthenticated: Bool = false
    private var cachedUserName: String?
    var cachedUserEmail: String?  // Made public for DataSyncService
    
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
        cachedUserName = nil
        cachedUserEmail = nil
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
        
        // Get user display name for sent messages
        let userDisplayName = try? await getUserDisplayName()
        
        // Fetch message list first
        let messageIds = try await apiClient.fetchMessageIds()
        
        // Fetch full messages
        var emails: [Email] = []
        for messageId in messageIds {
            do {
                let gmailMessage = try await apiClient.fetchMessage(messageId: messageId)
                if let email = MessageParserService.parseGmailMessage(gmailMessage) {
                    // For sent messages, use the cached display name instead of email address
                    if email.isFromMe, let displayName = userDisplayName {
                        email.sender = displayName
                    }
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
    
    // Single recipient convenience method (backward compatibility)
    func sendEmail(to recipientEmail: String, body: String, subject: String? = nil, inReplyTo: String? = nil, attachments: [(filename: String, data: Data, mimeType: String)] = []) async throws {
        try await sendEmail(to: [recipientEmail], cc: [], bcc: [], body: body, subject: subject, inReplyTo: inReplyTo, attachments: attachments)
    }
    
    // Multiple recipients support
    func sendEmail(to recipients: [String], cc: [String] = [], bcc: [String] = [], body: String, subject: String? = nil, inReplyTo: String? = nil, attachments: [(filename: String, data: Data, mimeType: String)] = []) async throws {
        print("🚀 Starting email send to: \(recipients.joined(separator: ", ")) with \(attachments.count) attachments")
        if !cc.isEmpty {
            print("📄 CC: \(cc.joined(separator: ", "))")
        }
        if !bcc.isEmpty {
            print("🔒 BCC: \(bcc.joined(separator: ", "))")
        }
        if let replyTo = inReplyTo {
            print("📬 This is a reply to message: \(replyTo)")
        }
        
        guard isAuthenticated else {
            throw GmailError.notAuthenticated
        }
        
        // Validate all recipient emails
        for recipient in recipients + cc + bcc {
            guard EmailValidator.isValid(recipient) else {
                throw GmailError.invalidRecipient
            }
        }
        
        // Get user's email address and display name for From field
        let userEmail: String
        let userDisplayName: String
        do {
            userEmail = try await getUserEmail()
            userDisplayName = try await getUserDisplayName()
            print("📧 Sending from: \(userDisplayName) <\(userEmail)>")
        } catch {
            print("❌ Failed to get user info: \(error)")
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
        // Format the From field with display name: "Name <email@example.com>"
        let fromField = userDisplayName != userEmail ? "\(userDisplayName) <\(userEmail)>" : userEmail
        
        let messageBuilder = EmailMessageBuilder(
            from: fromField,
            to: recipients,
            cc: cc,
            bcc: bcc,
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
        // Return cached email if available
        if let cachedEmail = cachedUserEmail {
            return cachedEmail
        }
        
        let profile = try await apiClient.getUserProfile()
        cachedUserEmail = profile.emailAddress
        
        // Also fetch and cache the user's name if we don't have it
        if cachedUserName == nil {
            cachedUserName = try? await apiClient.getUserName()
        }
        
        return profile.emailAddress
    }
    
    func getUserDisplayName() async throws -> String {
        // Return cached name if available
        if let cachedName = cachedUserName {
            return cachedName
        }
        
        // Try to fetch the user's name
        if let name = try? await apiClient.getUserName() {
            cachedUserName = name
            return name
        }
        
        // Fall back to email address
        return try await getUserEmail()
    }
    
    // MARK: - Fetch Single Message
    
    func fetchMessage(messageId: String) async throws -> GmailMessage {
        guard isAuthenticated else {
            throw GmailError.notAuthenticated
        }
        
        return try await apiClient.fetchMessage(messageId: messageId)
    }
}