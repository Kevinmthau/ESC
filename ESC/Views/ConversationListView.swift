import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.lastMessageTimestamp, order: .reverse) 
    private var allConversations: [Conversation]
    @StateObject private var gmailService = GmailService()
    @EnvironmentObject private var contactsService: ContactsService
    @State private var syncService: DataSyncService?
    @State private var showingAuth = false
    @State private var showingNewConversation = false
    @State private var showingSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var errorMessage: String?
    @State private var refreshTrigger = 0
    @State private var pendingNavigation: Conversation?
    @State private var isInitialLoad = false
    @State private var hasCompletedInitialSync = false
    
    private var conversations: [Conversation] {
        // Only show conversations that have messages
        let nonEmpty = allConversations.filter { !$0.lastMessageSnippet.isEmpty }
        let sorted = nonEmpty.sorted { $0.lastMessageTimestamp > $1.lastMessageTimestamp }
        print("📋 ConversationListView: Showing \(sorted.count) conversations, sorted by timestamp")
        return sorted
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Main content
                VStack {
                if !gmailService.isAuthenticated {
                    // Show sign-in prompt when not authenticated
                    VStack(spacing: 20) {
                        Image(systemName: "envelope.circle")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        Text("Sign in to view your emails")
                            .font(.title2)
                            .foregroundColor(.primary)
                        Button(action: {
                            showingAuth = true
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("Sign In with Google")
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                } else if isInitialLoad && !hasCompletedInitialSync && conversations.isEmpty {
                    // Show loading state only during first sync after login
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading emails...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                } else if conversations.isEmpty {
                    // Show empty state when no conversations
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No messages")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Pull down to refresh")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .refreshable {
                        if gmailService.isAuthenticated {
                            await syncService?.syncData()
                        }
                    }
                } else {
                    // Show conversations list
                    List(conversations) { conversation in
                        NavigationLink(value: conversation) {
                            ConversationRowView(conversation: conversation)
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
                        showingNewConversation = true
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
                        // If authenticated but haven't synced yet, show loading state briefly
                        if !hasCompletedInitialSync && conversations.isEmpty {
                            await MainActor.run {
                                isInitialLoad = true
                            }
                            
                            // Do initial sync
                            await syncService?.syncData()
                            
                            await MainActor.run {
                                hasCompletedInitialSync = true
                                isInitialLoad = false
                                syncService?.startAutoSync()
                            }
                        } else {
                            // Already synced before, just start auto-sync
                            await MainActor.run {
                                syncService?.startAutoSync()
                            }
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
                    
                    // Set initial load state
                    isInitialLoad = true
                    
                    // Initialize sync service if needed
                    if syncService == nil {
                        syncService = DataSyncService(modelContext: modelContext, gmailService: gmailService, contactsService: contactsService)
                    }
                    
                    // Start syncing immediately after authentication
                    Task {
                        await syncService?.syncData()
                        syncService?.startAutoSync()
                        
                        // Mark initial sync as completed and clear loading state
                        await MainActor.run {
                            hasCompletedInitialSync = true
                            isInitialLoad = false
                        }
                    }
                }
            }
            .onChange(of: showingNewConversation) { _, newValue in
                if newValue {
                    // Create a new empty conversation and navigate to it
                    let newConversation = Conversation(
                        contactName: "",
                        contactEmail: "",
                        lastMessageTimestamp: Date(),
                        lastMessageSnippet: "",
                        isRead: true
                    )
                    
                    // Don't insert into context yet - let ConversationDetailView handle it
                    navigationPath.append(newConversation)
                    showingNewConversation = false
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(gmailService: gmailService, syncService: syncService) {
                    handleAuthenticationChange()
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
            .onChange(of: gmailService.isAuthenticated) { _, newValue in
                print("🔑 ConversationListView: Authentication state changed to: \(newValue)")
                if !newValue {
                    // Clear navigation path when logged out
                    navigationPath = NavigationPath()
                    syncService?.stopAutoSync()
                    refreshTrigger += 1
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConversation"))) { notification in
                if let conversation = notification.object as? Conversation {
                    // Navigate to the conversation after forwarding
                    navigationPath.append(conversation)
                }
            }
        }
    }
    
    private func handleAuthenticationChange() {
        Task { @MainActor in
            if gmailService.isAuthenticated {
                // User signed in with new account - reload everything
                print("🔄 ConversationListView: Auth state changed - reloading conversations")
                
                // Reset sync state for new account
                hasCompletedInitialSync = false
                isInitialLoad = true
                
                // Force refresh by triggering the query to re-execute
                refreshTrigger += 1
                
                // Start syncing for new account
                if conversations.isEmpty {
                    await syncService?.syncData()
                    hasCompletedInitialSync = true
                }
                isInitialLoad = false
                
                syncService?.startAutoSync()
            } else {
                // User signed out - clear everything
                navigationPath = NavigationPath()
                refreshTrigger += 1  // Force UI refresh to show empty state
                hasCompletedInitialSync = false
                syncService?.stopAutoSync()
            }
        }
    }
    
    private func extractNameFromEmail(_ email: String) -> String {
        // First try to get name from contacts
        if let contactName = contactsService.getContactName(for: email) {
            return contactName
        }
        
        // Otherwise extract name from email
        if let atIndex = email.firstIndex(of: "@") {
            let username = String(email[..<atIndex])
            // Try to make it more human-readable
            let nameFromEmail = username.replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            return nameFromEmail
        }
        return email
    }
}


#Preview {
    ConversationListView()
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}