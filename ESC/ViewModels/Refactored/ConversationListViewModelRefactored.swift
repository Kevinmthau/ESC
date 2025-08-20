import SwiftUI
import SwiftData
import Combine

@MainActor
class ConversationListViewModelRefactored: BaseListViewModel<Conversation> {
    
    // MARK: - Dependencies
    private let conversationRepository: ConversationRepositoryProtocol
    private let emailRepository: EmailRepositoryProtocol
    private let gmailService: GmailServiceProtocol
    private let dataSyncService: DataSyncServiceProtocol
    private let navigationCoordinator: NavigationCoordinator
    
    // MARK: - Published Properties
    @Published var hasInitiallyLoaded = false
    @Published var isSyncing = false
    
    // MARK: - Computed Properties
    var isAuthenticated: Bool {
        gmailService.isAuthenticated
    }
    
    var emptyStateMessage: String {
        if !isAuthenticated {
            return "Please sign in to view your conversations"
        } else if isLoading && !hasInitiallyLoaded {
            return "Loading conversations..."
        } else if items.isEmpty {
            return "No conversations yet"
        }
        return ""
    }
    
    // MARK: - Initialization
    init(conversationRepository: ConversationRepositoryProtocol,
         emailRepository: EmailRepositoryProtocol,
         gmailService: GmailServiceProtocol,
         dataSyncService: DataSyncServiceProtocol,
         navigationCoordinator: NavigationCoordinator) {
        self.conversationRepository = conversationRepository
        self.emailRepository = emailRepository
        self.gmailService = gmailService
        self.dataSyncService = dataSyncService
        self.navigationCoordinator = navigationCoordinator
        super.init()
        
        setupObservers()
        loadInitialData()
    }
    
    // MARK: - Setup
    
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
        
        // Observe authentication changes
        NotificationCenter.default.publisher(for: NSNotification.Name("AuthenticationStateChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAuthenticationChange()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    private func loadInitialData() {
        guard isAuthenticated else { return }
        
        performAsyncOperation({
            try await self.loadConversationsAsync()
        }, onSuccess: { conversations in
            self.items = conversations
            self.hasInitiallyLoaded = true
        })
    }
    
    override func loadItems(page: Int) {
        loadConversations()
    }
    
    func loadConversations() {
        do {
            items = try conversationRepository.fetchAll()
            hasInitiallyLoaded = true
        } catch {
            handleError(AppError.fetchFailed(error))
        }
    }
    
    private func loadConversationsAsync() async throws -> [Conversation] {
        try conversationRepository.fetchAll()
    }
    
    // MARK: - Refresh
    
    override func refresh() {
        guard !isSyncing else { return }
        
        Task {
            isSyncing = true
            defer { isSyncing = false }
            
            await dataSyncService.syncData(silent: false)
            loadConversations()
        }
    }
    
    // MARK: - Search
    
    override func filterItems(_ items: [Conversation], searchText: String) -> [Conversation] {
        let query = searchText.lowercased()
        return items.filter { conversation in
            conversation.matches(searchQuery: query)
        }
    }
    
    // MARK: - Conversation Management
    
    func createNewConversation() {
        let conversation = Conversation(
            contactName: "",
            contactEmail: "",
            lastMessageTimestamp: Date(),
            lastMessageSnippet: ""
        )
        navigationCoordinator.navigate(to: .conversationDetail(conversation))
    }
    
    func openConversation(_ conversation: Conversation) {
        markConversationAsRead(conversation)
        navigationCoordinator.navigate(to: .conversationDetail(conversation))
    }
    
    func deleteConversation(_ conversation: Conversation) {
        performAsyncOperation({
            try self.conversationRepository.delete(conversation)
        }, onSuccess: { _ in
            self.removeItem(conversation)
        })
    }
    
    func markConversationAsRead(_ conversation: Conversation) {
        guard !conversation.isRead else { return }
        
        performAsyncOperation({
            try self.conversationRepository.markAsRead(conversation)
        }, onSuccess: { _ in
            self.updateItem(conversation)
        })
    }
    
    // MARK: - Bulk Operations
    
    func markAllAsRead() {
        let unreadConversations = items.filter { !$0.isRead }
        guard !unreadConversations.isEmpty else { return }
        
        performAsyncOperation({
            for conversation in unreadConversations {
                try self.conversationRepository.markAsRead(conversation)
            }
        }, onSuccess: { _ in
            self.loadConversations()
        })
    }
    
    func deleteMultipleConversations(_ conversations: Set<Conversation>) {
        performAsyncOperation({
            for conversation in conversations {
                try self.conversationRepository.delete(conversation)
            }
        }, onSuccess: { _ in
            self.loadConversations()
        })
    }
    
    // MARK: - Authentication
    
    func signOut() async {
        gmailService.signOut()
        await clearAllData()
    }
    
    private func clearAllData() async {
        do {
            try conversationRepository.deleteAll()
            try emailRepository.deleteAll()
            items = []
            hasInitiallyLoaded = false
        } catch {
            handleError(AppError.deleteFailed(error))
        }
    }
    
    private func handleAuthenticationChange() {
        if isAuthenticated {
            loadInitialData()
        } else {
            items = []
            hasInitiallyLoaded = false
        }
    }
    
    // MARK: - Statistics
    
    var totalConversations: Int {
        items.count
    }
    
    var unreadConversations: Int {
        items.filter { !$0.isRead }.count
    }
    
    var conversationsWithAttachments: Int {
        items.filter { $0.hasAttachments }.count
    }
}