import Foundation
import SwiftUI
import SwiftData

/// Dependency Injection Container for managing app-wide dependencies
@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()
    
    // MARK: - Services
    private(set) lazy var gmailService = GmailService()
    
    private(set) lazy var contactsService = ContactsService.shared
    
    private(set) lazy var dataSyncService = DataSyncService(
        modelContext: modelContext,
        gmailService: gmailService,
        contactsService: contactsService
    )
    
    private(set) lazy var messageParserService = MessageParserService()
    
    private(set) lazy var htmlSanitizerService = HTMLSanitizerService.shared
    
    private(set) lazy var webViewPoolManager = WebViewPoolManager.shared
    
    // MARK: - Repositories
    private(set) lazy var emailRepository = EmailRepository(modelContext: modelContext)
    
    private(set) lazy var conversationRepository = ConversationRepository(modelContext: modelContext)
    
    // MARK: - Coordinators
    private(set) lazy var navigationCoordinator = NavigationCoordinator()
    
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
    
    // MARK: - Service Protocols (for testing)
    // These would need protocol conformance implementations in the actual services
    
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

// MARK: - Container Holder for Environment
/// A holder that provides access to the DependencyContainer without directly referencing the MainActor-isolated shared instance
struct DependencyContainerHolder {
    @MainActor
    var container: DependencyContainer {
        DependencyContainer.shared
    }
}

// MARK: - Environment Key
struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue = DependencyContainerHolder()
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        @MainActor get { 
            self[DependencyContainerKey.self].container
        }
        set { 
            // For setting, we need to wrap in a holder
            // This is only used when explicitly setting via .environment
            // which happens in MainActor context anyway
            self[DependencyContainerKey.self] = DependencyContainerHolder()
        }
    }
}

// MARK: - View Extension
extension View {
    func withDependencies() -> some View {
        self.modifier(DependencyContainerModifier())
    }
    
    func withDependencies(_ container: DependencyContainer) -> some View {
        self.environment(\.dependencies, container)
    }
}

// Helper modifier to access shared instance in MainActor context
struct DependencyContainerModifier: ViewModifier {
    @MainActor
    func body(content: Content) -> some View {
        content.environment(\.dependencies, DependencyContainer.shared)
    }
}