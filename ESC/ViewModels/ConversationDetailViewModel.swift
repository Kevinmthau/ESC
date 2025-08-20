import SwiftUI
import SwiftData
import Combine

@MainActor
class ConversationDetailViewModel: BaseDetailViewModel<Conversation> {
    // MARK: - Published Properties
    @Published var messageText = ""
    @Published var toRecipients: [String] = []
    @Published var ccRecipients: [String] = []
    @Published var bccRecipients: [String] = []
    @Published var isSending = false
    @Published var selectedAttachments: [(filename: String, data: Data, mimeType: String)] = []
    @Published var emails: [Email] = []
    @Published var replyingToEmail: Email?
    @Published var filteredContacts: [(name: String, email: String)] = []
    
    // MARK: - Properties
    var conversation: Conversation { item! }
    let gmailService: GmailServiceProtocol
    let modelContext: ModelContext
    let contactsService: ContactsServiceProtocol
    
    var conversationEmails: [Email] {
        emails.sorted { $0.timestamp < $1.timestamp }
    }
    
    var isNewConversation: Bool {
        conversation.contactEmail.isEmpty
    }
    
    // MARK: - Initialization
    init(conversation: Conversation, 
         gmailService: GmailServiceProtocol,
         modelContext: ModelContext,
         contactsService: ContactsServiceProtocol = ContactsService.shared) {
        self.gmailService = gmailService
        self.modelContext = modelContext
        self.contactsService = contactsService
        super.init(item: conversation)
        
        initializeRecipients()
    }
    
    // MARK: - Public Methods
    func loadEmails() {
        if conversation.isGroupConversation {
            loadGroupEmails()
        } else {
            loadSingleConversationEmails()
        }
    }
    
    func markAsRead() {
        guard !conversation.isRead else { return }
        
        conversation.isRead = true
        for email in conversationEmails where !email.isRead {
            email.isRead = true
        }
        
        do {
            try modelContext.save()
        } catch {
            handleSendError(error)
        }
    }
    
    func sendMessage() async {
        guard validateMessage() else { return }
        
        isSending = true
        defer { isSending = false }
        
        do {
            let email = try await createAndSendEmail()
            await addEmailToConversation(email)
            clearComposer()
        } catch {
            handleSendError(error)
        }
    }
    
    func handleReply(to email: Email) {
        replyingToEmail = email
        fetchSubjectIfNeeded(for: email)
    }
    
    func cancelReply() {
        replyingToEmail = nil
        messageText = ""
        selectedAttachments = []
    }
    
    func updateFilteredContacts(query: String) {
        let allContacts = fetchAllContacts()
        
        if query.isEmpty {
            filteredContacts = Array(allContacts.prefix(10))
        } else {
            let lowercaseQuery = query.lowercased()
            filteredContacts = allContacts.filter { contact in
                contact.name.lowercased().contains(lowercaseQuery) ||
                contact.email.lowercased().contains(lowercaseQuery)
            }.prefix(5).map { $0 }
        }
    }
    
    // MARK: - Private Methods
    private func initializeRecipients() {
        guard !isNewConversation && toRecipients.isEmpty else { return }
        
        if conversation.isGroupConversation {
            toRecipients = conversation.participantEmails
        } else if !conversation.contactEmail.isEmpty {
            toRecipients = [conversation.contactEmail]
        }
    }
    
    private func loadGroupEmails() {
        if !conversation.emails.isEmpty {
            emails = conversation.emails.sorted { $0.timestamp < $1.timestamp }
            return
        }
        
        let conversationKey = conversation.contactEmail.lowercased()
        let descriptor = FetchDescriptor<Email>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            let allEmails = try modelContext.fetch(descriptor)
            let groupEmails = allEmails.filter { email in
                let emailParticipants = Set(email.allRecipients + [email.senderEmail.lowercased()])
                let conversationParticipants = Set(conversationKey.split(separator: ",").map { String($0) })
                let commonParticipants = emailParticipants.intersection(conversationParticipants)
                return commonParticipants.count >= min(2, conversationParticipants.count)
            }
            emails = groupEmails
        } catch {
            handleSendError(error)
            emails = []
        }
    }
    
    private func loadSingleConversationEmails() {
        let contactEmail = conversation.contactEmail
        let normalizedContactEmail = contactEmail.lowercased()
        let descriptor = FetchDescriptor<Email>(
            predicate: #Predicate<Email> { email in
                (email.isFromMe && email.recipientEmail == normalizedContactEmail) ||
                (!email.isFromMe && email.senderEmail == normalizedContactEmail)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            let fetchedEmails = try modelContext.fetch(descriptor)
            emails = deduplicateEmails(fetchedEmails)
        } catch {
            handleSendError(error)
            emails = []
        }
    }
    
    private func deduplicateEmails(_ emails: [Email]) -> [Email] {
        var uniqueEmails: [Email] = []
        var seenMessages = Set<String>()
        
        for email in emails {
            let timeKey = Int(email.timestamp.timeIntervalSince1970 / 10)
            let uniqueKey = "\(email.isFromMe)_\(timeKey)_\(email.body.prefix(100))"
            
            if !seenMessages.contains(uniqueKey) {
                seenMessages.insert(uniqueKey)
                uniqueEmails.append(email)
            }
        }
        
        return uniqueEmails
    }
    
    private func validateMessage() -> Bool {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedAttachments.isEmpty else {
            return false
        }
        
        if isNewConversation {
            guard !toRecipients.isEmpty else {
                showErrorMessage("Please add at least one recipient")
                return false
            }
            
            for recipient in toRecipients + ccRecipients + bccRecipients {
                guard EmailValidator.isValid(recipient) else {
                    showErrorMessage("Invalid email address: \(recipient)")
                    return false
                }
            }
        }
        
        return true
    }
    
    private func createAndSendEmail() async throws -> Email {
        let userEmail = try await gmailService.getUserEmail()
        let userName = try await gmailService.getUserDisplayName()
        
        let bodyToSend = buildEmailBody()
        let finalRecipients = getFinalRecipients()
        
        if let replyTo = replyingToEmail {
            try await gmailService.sendEmail(
                to: finalRecipients,
                cc: ccRecipients,
                bcc: bccRecipients,
                body: bodyToSend,
                subject: replyTo.subject,
                inReplyTo: replyTo.messageId,
                attachments: selectedAttachments
            )
        } else {
            try await gmailService.sendEmail(
                to: finalRecipients,
                cc: ccRecipients,
                bcc: bccRecipients,
                body: bodyToSend,
                subject: nil,
                inReplyTo: nil,
                attachments: selectedAttachments
            )
        }
        
        return createLocalEmail(
            body: messageText,
            senderName: userName,
            senderEmail: userEmail,
            attachments: selectedAttachments,
            inReplyTo: replyingToEmail?.id,
            subject: replyingToEmail?.subject,
            recipients: finalRecipients
        )
    }
    
    private func createLocalEmail(body: String,
                                 senderName: String,
                                 senderEmail: String,
                                 attachments: [(filename: String, data: Data, mimeType: String)],
                                 inReplyTo: String? = nil,
                                 subject: String? = nil,
                                 recipients: [String]? = nil) -> Email {
        let actualRecipients = recipients ?? toRecipients
        let primaryRecipient = actualRecipients.first ?? conversation.contactEmail
        let primaryRecipientName = contactsService.getContactName(for: primaryRecipient) ?? extractNameFromEmail(primaryRecipient)
        
        let email = Email(
            id: UUID().uuidString,
            messageId: UUID().uuidString,
            threadId: UUID().uuidString,
            sender: senderName,
            senderEmail: senderEmail,
            recipient: primaryRecipientName,
            recipientEmail: primaryRecipient,
            allRecipients: actualRecipients + ccRecipients + bccRecipients,
            toRecipients: actualRecipients,
            ccRecipients: ccRecipients,
            bccRecipients: bccRecipients,
            body: body,
            snippet: MessageCleaner.createCleanSnippet(body),
            timestamp: Date(),
            isRead: true,
            isFromMe: true,
            conversation: conversation,
            inReplyToMessageId: inReplyTo,
            subject: subject
        )
        
        for attachment in attachments {
            let attachmentModel = Attachment(
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                size: attachment.data.count,
                data: attachment.data
            )
            email.attachments.append(attachmentModel)
        }
        
        return email
    }
    
    private func addEmailToConversation(_ email: Email) async {
        modelContext.insert(email)
        
        for attachment in email.attachments {
            modelContext.insert(attachment)
        }
        
        conversation.addEmail(email)
        conversation.isRead = true
        conversation.lastMessageTimestamp = email.timestamp
        conversation.lastMessageSnippet = email.snippet
        
        if conversation.modelContext == nil {
            modelContext.insert(conversation)
        }
        
        do {
            modelContext.processPendingChanges()
            try modelContext.save()
            
            if !emails.contains(where: { $0.id == email.id }) {
                emails.append(email)
            }
            
            NotificationCenter.default.post(
                name: NSNotification.Name("ConversationUpdated"),
                object: conversation
            )
            
            NotificationCenter.default.post(
                name: NSNotification.Name("MessageSent"),
                object: conversation
            )
        } catch {
            handleSendError(error)
        }
    }
    
    private func clearComposer() {
        messageText = ""
        selectedAttachments = []
        replyingToEmail = nil
    }
    
    private func buildEmailBody() -> String {
        guard let replyTo = replyingToEmail else {
            return messageText
        }
        
        return buildReplyBodyWithHistory(newMessage: messageText, replyingTo: replyTo)
    }
    
    private func buildReplyBodyWithHistory(newMessage: String, replyingTo: Email) -> String {
        var fullBody = newMessage + "\n\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        fullBody += "On \(dateFormatter.string(from: replyingTo.timestamp)), "
        fullBody += replyingTo.isFromMe ? "you wrote:\n" : "\(replyingTo.sender) wrote:\n"
        
        let emailContent = replyingTo.htmlBody?.isEmpty == false ? 
            convertHTMLToPlainText(replyingTo.htmlBody!) : replyingTo.body
        
        let lines = emailContent.components(separatedBy: "\n")
        let quotedBody = lines.map { line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? ">" : "> \(line)"
        }.joined(separator: "\n")
        
        fullBody += quotedBody
        return fullBody
    }
    
    private func convertHTMLToPlainText(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else {
            return html
        }
        
        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            let attributedString = try NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )
            
            return attributedString.string
        } catch {
            return stripBasicHTML(html)
        }
    }
    
    private func stripBasicHTML(_ html: String) -> String {
        var text = html
        
        // Replace common HTML entities
        let replacements = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'")
        ]
        
        for (entity, replacement) in replacements {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Replace line break tags
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        
        // Remove all remaining HTML tags
        let pattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: text.utf16.count)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // Clean up multiple consecutive newlines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func getFinalRecipients() -> [String] {
        if !toRecipients.isEmpty {
            return toRecipients
        }
        
        if conversation.isGroupConversation {
            return conversation.participantEmails
        } else {
            return [conversation.contactEmail]
        }
    }
    
    private func fetchAllContacts() -> [(name: String, email: String)] {
        var allContacts: [(name: String, email: String)] = []
        var seenEmails = Set<String>()
        
        // Add conversation contacts first
        let descriptor = FetchDescriptor<Conversation>()
        if let conversations = try? modelContext.fetch(descriptor) {
            for conversation in conversations {
                let email = conversation.contactEmail.lowercased()
                if !seenEmails.contains(email) && !email.isEmpty {
                    allContacts.append((name: conversation.contactName, email: conversation.contactEmail))
                    seenEmails.insert(email)
                }
            }
        }
        
        // Add address book contacts
        for contact in contactsService.getAllContacts() {
            let email = contact.email.lowercased()
            if !seenEmails.contains(email) && !email.isEmpty {
                allContacts.append(contact)
                seenEmails.insert(email)
            }
        }
        
        return allContacts
    }
    
    private func fetchSubjectIfNeeded(for email: Email) {
        guard email.subject == nil || email.subject?.isEmpty == true else { return }
        
        Task {
            if let fetchedSubject = await fetchSubjectForEmail(email) {
                await MainActor.run {
                    email.subject = fetchedSubject
                    do {
                        try modelContext.save()
                    } catch {
                        print("Failed to save subject: \(error)")
                    }
                }
            }
        }
    }
    
    private func fetchSubjectForEmail(_ email: Email) async -> String? {
        // TODO: This method needs refactoring to work with the protocol
        // For now, return the stored subject if available
        return email.subject
        
        /*
        guard gmailService.isAuthenticated else { return nil }
        
        do {
            let gmailMessage = try await gmailService.fetchMessage(messageId: email.messageId)
            
            if let payload = gmailMessage.payload,
               let headers = payload.headers {
                for header in headers {
                    if header.name.lowercased() == "subject" {
                        return header.value
                    }
                }
            }
        } catch {
            print("Failed to fetch subject for email \(email.messageId): \(error)")
        }
        
        return nil
        */
    }
    
    private func extractNameFromEmail(_ email: String) -> String {
        if let contactName = contactsService.getContactName(for: email) {
            return contactName
        }
        
        if let atIndex = email.firstIndex(of: "@") {
            let username = String(email[..<atIndex])
            let nameFromEmail = username.replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            return nameFromEmail
        }
        return email
    }
    
    private func handleSendError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}