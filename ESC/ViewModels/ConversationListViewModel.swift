import SwiftUI
import SwiftData
import Combine

@MainActor
class ConversationListViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var conversations: [Conversation] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var isSyncing = false
    @Published var hasInitiallyLoaded = false
    
    // MARK: - Properties
    private let gmailService: GmailService
    private let modelContext: ModelContext
    private let dataSyncService: DataSyncService
    private var cancellables = Set<AnyCancellable>()
    
    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        
        let lowercaseSearch = searchText.lowercased()
        return conversations.filter { conversation in
            conversation.contactName.lowercased().contains(lowercaseSearch) ||
            conversation.contactEmail.lowercased().contains(lowercaseSearch) ||
            conversation.lastMessageSnippet.lowercased().contains(lowercaseSearch)
        }
    }
    
    var isAuthenticated: Bool {
        gmailService.isAuthenticated
    }
    
    // MARK: - Initialization
    init(gmailService: GmailService,
         modelContext: ModelContext,
         dataSyncService: DataSyncService) {
        self.gmailService = gmailService
        self.modelContext = modelContext
        self.dataSyncService = dataSyncService
        
        setupObservers()
    }
    
    // MARK: - Public Methods
    func loadConversations() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.lastMessageTimestamp, order: .reverse)]
        )
        
        do {
            conversations = try modelContext.fetch(descriptor)
            hasInitiallyLoaded = true
        } catch {
            handleError(AppError.fetchFailed(error))
        }
    }
    
    func refreshConversations() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        // Call the sync method directly on DataSyncService
        await dataSyncService.syncData(silent: false)
        loadConversations()
    }
    
    func deleteConversation(_ conversation: Conversation) {
        do {
            // Delete all emails in the conversation
            for email in conversation.emails {
                modelContext.delete(email)
            }
            
            // Delete the conversation
            modelContext.delete(conversation)
            try modelContext.save()
            
            // Remove from local array
            conversations.removeAll { $0.id == conversation.id }
        } catch {
            handleError(AppError.deleteFailed(error))
        }
    }
    
    func markConversationAsRead(_ conversation: Conversation) {
        guard !conversation.isRead else { return }
        
        conversation.isRead = true
        for email in conversation.emails where !email.isRead {
            email.isRead = true
        }
        
        do {
            try modelContext.save()
        } catch {
            handleError(AppError.saveFailed(error))
        }
    }
    
    func createNewConversation() -> Conversation {
        let conversation = Conversation(
            contactName: "",
            contactEmail: "",
            lastMessageTimestamp: Date(),
            lastMessageSnippet: ""
        )
        return conversation
    }
    
    func signOut() async {
        gmailService.signOut()
        clearAllData()
    }
    
    // MARK: - Private Methods
    private func setupObservers() {
        // Observe conversation updates
        NotificationCenter.default.publisher(for: NSNotification.Name("ConversationUpdated"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadConversations()
            }
            .store(in: &cancellables)
        
        // Observe sync status
        NotificationCenter.default.publisher(for: NSNotification.Name("SyncStatusChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isSyncing = notification.object as? Bool {
                    self?.isSyncing = isSyncing
                }
            }
            .store(in: &cancellables)
    }
    
    private func clearAllData() {
        do {
            // Delete all conversations
            let conversationDescriptor = FetchDescriptor<Conversation>()
            let allConversations = try modelContext.fetch(conversationDescriptor)
            for conversation in allConversations {
                modelContext.delete(conversation)
            }
            
            // Delete all emails
            let emailDescriptor = FetchDescriptor<Email>()
            let allEmails = try modelContext.fetch(emailDescriptor)
            for email in allEmails {
                modelContext.delete(email)
            }
            
            // Delete all attachments
            let attachmentDescriptor = FetchDescriptor<Attachment>()
            let allAttachments = try modelContext.fetch(attachmentDescriptor)
            for attachment in allAttachments {
                modelContext.delete(attachment)
            }
            
            try modelContext.save()
            conversations = []
            hasInitiallyLoaded = false
        } catch {
            print("Failed to clear data: \(error)")
        }
    }
    
    private func handleError(_ error: AppError) {
        errorMessage = error.localizedDescription
        showingError = true
        
        if error.requiresReauthentication {
            Task {
                await signOut()
            }
        }
    }
}

// MARK: - Preview Helper
extension ConversationListViewModel {
    static var preview: ConversationListViewModel {
        let container = try! ModelContainer(
            for: Conversation.self, Email.self, Attachment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        return ConversationListViewModel(
            gmailService: GmailService(),
            modelContext: container.mainContext,
            dataSyncService: DataSyncService(
                modelContext: container.mainContext,
                gmailService: GmailService(),
                contactsService: ContactsService.shared
            )
        )
    }
}