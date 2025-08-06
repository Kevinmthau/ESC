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
    @State private var showingNewConversation = false
    @State private var showingSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var errorMessage: String?
    @State private var refreshTrigger = 0
    @State private var pendingNavigation: Conversation?
    
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
                } else if syncService?.isSyncing == true && conversations.isEmpty {
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
                    // Callback when authentication state changes
                    if gmailService.isAuthenticated {
                        syncService?.startAutoSync()
                    } else {
                        // Clear navigation when logged out
                        navigationPath = NavigationPath()
                        syncService?.stopAutoSync()
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
            .onChange(of: gmailService.isAuthenticated) { _, newValue in
                print("🔑 ConversationListView: Authentication state changed to: \(newValue)")
                if !newValue {
                    // Clear navigation path when logged out
                    navigationPath = NavigationPath()
                    syncService?.stopAutoSync()
                    refreshTrigger += 1
                }
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