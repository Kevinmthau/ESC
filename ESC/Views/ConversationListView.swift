import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.lastMessageTimestamp, order: .reverse) 
    private var conversations: [Conversation]
    @StateObject private var gmailService = GmailService()
    @State private var isLoading = false
    @State private var showingAuth = false
    @State private var showingCompose = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading emails...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                } else {
                    List(displayConversations) { conversation in
                        NavigationLink(destination: ConversationDetailView(conversation: conversation)) {
                            ConversationRowView(conversation: conversation)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.white)
                    }
                    .listStyle(PlainListStyle())
                    .background(Color.white)
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.white)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingCompose = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.title2)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if gmailService.isAuthenticated {
                            Task {
                                await loadGmailData()
                            }
                        } else {
                            showingAuth = true
                        }
                    }) {
                        Image(systemName: gmailService.isAuthenticated ? "arrow.clockwise" : "person.crop.circle.badge.plus")
                    }
                }
            }
            .onAppear {
                if gmailService.isAuthenticated {
                    Task {
                        await loadGmailData()
                    }
                } else {
                    loadSampleDataIfNeeded()
                }
            }
            .sheet(isPresented: $showingAuth) {
                AuthenticationView(gmailService: gmailService) {
                    showingAuth = false
                    Task {
                        await loadGmailData()
                    }
                }
            }
            .sheet(isPresented: $showingCompose) {
                ComposeView(gmailService: gmailService)
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
    
    private var displayConversations: [Conversation] {
        conversations.isEmpty ? SampleData.createSampleConversations() : conversations
    }
    
    private func loadSampleDataIfNeeded() {
        if conversations.isEmpty {
            // Insert sample conversations into the database
            let sampleConversations = SampleData.createSampleConversations()
            for conversation in sampleConversations {
                modelContext.insert(conversation)
                for email in conversation.emails {
                    modelContext.insert(email)
                }
            }
            try? modelContext.save()
        }
    }
    
    private func loadGmailData() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let emails = try await gmailService.fetchEmails()
            let gmailConversations = gmailService.createConversations(from: emails)
            
            await MainActor.run {
                // Clear existing data
                for conversation in conversations {
                    modelContext.delete(conversation)
                }
                
                // Insert new Gmail data
                for conversation in gmailConversations {
                    modelContext.insert(conversation)
                    for email in conversation.emails {
                        modelContext.insert(email)
                    }
                }
                
                do {
                    try modelContext.save()
                } catch {
                    errorMessage = "Failed to save Gmail data: \(error.localizedDescription)"
                }
                
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load Gmail data: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Avatar circle
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(conversation.contactName.prefix(1).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
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