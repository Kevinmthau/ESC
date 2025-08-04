import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.lastMessageTimestamp, order: .reverse) 
    private var allConversations: [Conversation]
    @StateObject private var gmailService = GmailService()
    @StateObject private var contactsService = ContactsService()
    @State private var syncService: DataSyncService?
    @State private var showingAuth = false
    @State private var showingCompose = false
    @State private var showingSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var errorMessage: String?
    @State private var refreshTrigger = 0
    
    private var conversations: [Conversation] {
        let sorted = allConversations.sorted { $0.lastMessageTimestamp > $1.lastMessageTimestamp }
        print("📋 ConversationListView: Showing \(sorted.count) conversations, sorted by timestamp")
        return sorted
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Main content
                VStack {
                if syncService?.isSyncing == true && conversations.isEmpty {
                    ProgressView("Loading emails...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                } else {
                    List(conversations) { conversation in
                        NavigationLink(value: conversation) {
                            ConversationRowView(conversation: conversation, contactsService: contactsService)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.white)
                    }
                    .listStyle(PlainListStyle())
                    .background(Color.white)
                    .refreshable {
                        if gmailService.isAuthenticated {
                            await syncService?.syncData()
                        }
                    }
                }
                }
                }
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(.large)
                .background(Color.white)
                .navigationDestination(for: Conversation.self) { conversation in
                    ConversationDetailView(conversation: conversation, gmailService: gmailService)
                }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingCompose = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.title2)
                    }
                }
            }
            .onAppear {
                // Initialize sync service if needed
                if syncService == nil {
                    syncService = DataSyncService(modelContext: modelContext, gmailService: gmailService, contactsService: contactsService)
                }
                
                Task {
                    // Request contacts access if needed, then fetch contacts
                    if contactsService.authorizationStatus == .notDetermined {
                        _ = await contactsService.requestAccess()
                    }
                    if contactsService.authorizationStatus == .authorized {
                        await contactsService.fetchContacts()
                    }
                    
                    // Then start syncing with Gmail
                    if gmailService.isAuthenticated {
                        await MainActor.run {
                            syncService?.startAutoSync()
                        }
                    }
                }
                
                // Listen for conversation updates
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ConversationUpdated"),
                    object: nil,
                    queue: .main
                ) { notification in
                    print("🔄 ConversationListView: Received ConversationUpdated notification")
                    if let conversation = notification.object as? Conversation {
                        print("📅 Updated conversation: \(conversation.contactEmail), timestamp: \(conversation.lastMessageTimestamp)")
                    }
                    
                    // Force a model context refresh and save
                    modelContext.processPendingChanges()
                    do {
                        try modelContext.save()
                        print("✅ ConversationListView: Saved model context after conversation update")
                        
                        // Force UI refresh by updating trigger
                        refreshTrigger += 1
                        print("🔄 ConversationListView: Triggered UI refresh (\(refreshTrigger))")
                    } catch {
                        print("❌ ConversationListView: Failed to save context: \(error)")
                    }
                }
            }
            .onDisappear {
                syncService?.stopAutoSync()
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSNotification.Name("ConversationUpdated"),
                    object: nil
                )
            }
            .sheet(isPresented: $showingAuth) {
                AuthenticationView(gmailService: gmailService) {
                    showingAuth = false
                    syncService?.startAutoSync()
                }
            }
            .sheet(isPresented: $showingCompose) {
                ComposeView(gmailService: gmailService) { conversation in
                    // Navigate to the conversation after compose is dismissed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationPath.append(conversation)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(gmailService: gmailService, syncService: syncService) {
                    // Callback when authentication state changes
                    if gmailService.isAuthenticated {
                        syncService?.startAutoSync()
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: refreshTrigger) { _, _ in
                // This forces SwiftUI to re-evaluate the conversations computed property
                print("🔄 ConversationListView: Processing refresh trigger")
            }
        }
    }
    
}


#Preview {
    ConversationListView()
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}