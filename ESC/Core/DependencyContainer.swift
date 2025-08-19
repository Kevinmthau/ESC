import Foundation
import SwiftUI
import SwiftData

/// Dependency Injection Container for managing app-wide dependencies
@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()
    
    // MARK: - Services
    private(set) lazy var gmailService: GmailService = {
        GmailService()
    }()
    
    private(set) lazy var contactsService: ContactsService = {
        ContactsService.shared
    }()
    
    private(set) lazy var dataSyncService: DataSyncService = {
        DataSyncService(
            modelContext: modelContext,
            gmailService: gmailService,
            contactsService: contactsService
        )
    }()
    
    private(set) lazy var messageParserService: MessageParserService = {
        MessageParserService()
    }()
    
    // MARK: - Storage
    private(set) lazy var modelContainer: ModelContainer = {
        do {
            let schema = Schema([
                Email.self,
                Conversation.self,
                Attachment.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var modelContext: ModelContext {
        modelContainer.mainContext
    }
    
    // MARK: - ViewModels Factory
    func makeConversationDetailViewModel(for conversation: Conversation) -> ConversationDetailViewModel {
        ConversationDetailViewModel(
            conversation: conversation,
            gmailService: gmailService,
            modelContext: modelContext,
            contactsService: contactsService
        )
    }
    
    func makeConversationListViewModel() -> ConversationListViewModel {
        ConversationListViewModel(
            gmailService: gmailService,
            modelContext: modelContext,
            dataSyncService: dataSyncService
        )
    }
    
    // MARK: - Configuration
    func configure() {
        setupServices()
        registerNotifications()
    }
    
    private func setupServices() {
        // Configure services with initial settings
        // DataSyncService handles its own polling internally
        
        // Start background sync if authenticated
        if gmailService.isAuthenticated {
            dataSyncService.startAutoSync()
        }
    }
    
    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthenticationChange),
            name: NSNotification.Name("AuthenticationStateChanged"),
            object: nil
        )
    }
    
    @objc private func handleAuthenticationChange(_ notification: Notification) {
        if gmailService.isAuthenticated {
            dataSyncService.startAutoSync()
        } else {
            dataSyncService.stopAutoSync()
        }
    }
    
    private init() {}
}

// MARK: - Environment Key
struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue = DependencyContainer.shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - View Extension
extension View {
    func withDependencies(_ container: DependencyContainer = .shared) -> some View {
        self.environment(\.dependencies, container)
    }
}