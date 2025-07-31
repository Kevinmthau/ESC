import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.lastMessageTimestamp, order: .reverse) 
    private var conversations: [Conversation]
    @StateObject private var gmailService = GmailService()
    @State private var syncService: DataSyncService?
    @State private var showingAuth = false
    @State private var showingCompose = false
    @State private var showingSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var errorMessage: String?
    @StateObject private var contactsService = ContactsService()
    
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
            }
            .onDisappear {
                syncService?.stopAutoSync()
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
        }
    }
    
}

struct ConversationRowView: View {
    let conversation: Conversation
    let contactsService: ContactsService
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Avatar with contact photo
                ContactAvatarView(
                    email: conversation.contactEmail,
                    name: conversation.contactName,
                    contactsService: contactsService,
                    size: 50
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.contactName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer(minLength: 8)
                        
                        Text(conversation.lastMessageTimestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }
                    
                    Text(conversation.lastMessageSnippet)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if !conversation.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .fixedSize()
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 66)
            
            // Separator line
            Divider()
                .background(Color.gray.opacity(0.3))
                .padding(.leading, 62) // Align with text content
        }
        .background(Color.white)
    }
}


#Preview {
    ConversationListView()
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}