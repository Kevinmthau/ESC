import Foundation
import SwiftData

// MARK: - Email Repository Protocol
@MainActor
protocol EmailRepositoryProtocol {
    func fetchAll() throws -> [Email]
    func fetch(by id: String) throws -> Email?
    func fetchByConversation(_ conversationId: UUID) throws -> [Email]
    func save(_ email: Email) throws
    func delete(_ email: Email) throws
    func deleteAll() throws
    func markAsRead(_ email: Email) throws
    func search(query: String) throws -> [Email]
}

// MARK: - Email Repository Implementation
@MainActor
class EmailRepository: EmailRepositoryProtocol {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchAll() throws -> [Email] {
        let descriptor = FetchDescriptor<Email>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetch(by id: String) throws -> Email? {
        let descriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    func fetchByConversation(_ conversationId: UUID) throws -> [Email] {
        // Fetch all emails and filter by conversation
        let descriptor = FetchDescriptor<Email>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let allEmails = try modelContext.fetch(descriptor)
        return allEmails.filter { email in
            email.conversation?.id.hashValue == conversationId.hashValue
        }
    }
    
    func save(_ email: Email) throws {
        modelContext.insert(email)
        try modelContext.save()
    }
    
    func delete(_ email: Email) throws {
        modelContext.delete(email)
        try modelContext.save()
    }
    
    func deleteAll() throws {
        let descriptor = FetchDescriptor<Email>()
        let emails = try modelContext.fetch(descriptor)
        for email in emails {
            modelContext.delete(email)
        }
        try modelContext.save()
    }
    
    func markAsRead(_ email: Email) throws {
        email.isRead = true
        try modelContext.save()
    }
    
    func search(query: String) throws -> [Email] {
        let lowercased = query.lowercased()
        // Fetch all emails and filter
        let descriptor = FetchDescriptor<Email>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allEmails = try modelContext.fetch(descriptor)
        return allEmails.filter { email in
            (email.subject ?? "").lowercased().contains(lowercased) ||
            email.snippet.lowercased().contains(lowercased) ||
            email.sender.lowercased().contains(lowercased)
        }
    }
}

// MARK: - Conversation Repository Protocol
@MainActor
protocol ConversationRepositoryProtocol {
    func fetchAll() throws -> [Conversation]
    func fetch(by id: UUID) throws -> Conversation?
    func fetchByContactEmail(_ email: String) throws -> Conversation?
    func save(_ conversation: Conversation) throws
    func delete(_ conversation: Conversation) throws
    func deleteAll() throws
    func markAsRead(_ conversation: Conversation) throws
    func search(query: String) throws -> [Conversation]
}

// MARK: - Conversation Repository Implementation
@MainActor
class ConversationRepository: ConversationRepositoryProtocol {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchAll() throws -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.lastMessageTimestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetch(by id: UUID) throws -> Conversation? {
        // Fetch all conversations and filter
        let descriptor = FetchDescriptor<Conversation>()
        let allConversations = try modelContext.fetch(descriptor)
        return allConversations.first { $0.id.hashValue == id.hashValue }
    }
    
    func fetchByContactEmail(_ email: String) throws -> Conversation? {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.contactEmail == email }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    func save(_ conversation: Conversation) throws {
        modelContext.insert(conversation)
        try modelContext.save()
    }
    
    func delete(_ conversation: Conversation) throws {
        // Delete all emails in the conversation first
        for email in conversation.emails {
            modelContext.delete(email)
        }
        modelContext.delete(conversation)
        try modelContext.save()
    }
    
    func deleteAll() throws {
        let descriptor = FetchDescriptor<Conversation>()
        let conversations = try modelContext.fetch(descriptor)
        for conversation in conversations {
            for email in conversation.emails {
                modelContext.delete(email)
            }
            modelContext.delete(conversation)
        }
        try modelContext.save()
    }
    
    func markAsRead(_ conversation: Conversation) throws {
        conversation.isRead = true
        for email in conversation.emails {
            email.isRead = true
        }
        try modelContext.save()
    }
    
    func search(query: String) throws -> [Conversation] {
        let lowercased = query.lowercased()
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.contactName.localizedStandardContains(lowercased) ||
                conversation.contactEmail.localizedStandardContains(lowercased) ||
                conversation.lastMessageSnippet.localizedStandardContains(lowercased)
            },
            sortBy: [SortDescriptor(\.lastMessageTimestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}