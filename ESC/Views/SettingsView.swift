import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var gmailService: GmailService
    let syncService: DataSyncService?
    let onAuthChange: (() -> Void)?
    @State private var showingDeleteConfirmation = false
    @State private var showingSignOutConfirmation = false
    @State private var showingAuth = false
    @State private var userEmail: String = ""
    
    init(gmailService: GmailService, syncService: DataSyncService? = nil, onAuthChange: (() -> Void)? = nil) {
        self.gmailService = gmailService
        self.syncService = syncService
        self.onAuthChange = onAuthChange
    }
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section("Account") {
                    if gmailService.isAuthenticated {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed in as:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(userEmail.isEmpty ? "Loading..." : userEmail)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                        
                        Button(action: {
                            showingSignOutConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.minus")
                                    .foregroundColor(.blue)
                                Text("Switch Account")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: {
                            Task {
                                await syncService?.removeDuplicateEmails()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.merge")
                                    .foregroundColor(.orange)
                                Text("Clean Up Duplicates")
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Button(action: {
                            Task {
                                await syncService?.updateAllConversationPreviews()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.green)
                                Text("Fix Message Previews")
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash.circle.fill")
                                    .foregroundColor(.red)
                                Text("Delete Account Data")
                                    .foregroundColor(.red)
                            }
                        }
                    } else {
                        Button(action: {
                            showingAuth = true
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundColor(.blue)
                                Text("Sign In with Google")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                // App Info Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text("ESC - Email Simplified & Clean")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAuth) {
            AuthenticationView(gmailService: gmailService) {
                showingAuth = false
                loadUserEmail()
                onAuthChange?()
            }
        }
        .alert("Delete Account Data", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAccountData()
            }
        } message: {
            Text("This will permanently delete all your local email data and sign you out. This action cannot be undone.")
        }
        .alert("Switch Account", isPresented: $showingSignOutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOutAndSwitchAccount()
            }
        } message: {
            Text("This will sign you out and allow you to sign in with a different Google account. Your local data will be preserved.")
        }
        .onAppear {
            loadUserEmail()
        }
    }
    
    private func loadUserEmail() {
        if gmailService.isAuthenticated {
            Task {
                do {
                    let email = try await gmailService.getUserEmail()
                    await MainActor.run {
                        userEmail = email
                    }
                } catch {
                    print("❌ SettingsView: Failed to get user email: \(error)")
                }
            }
        }
    }
    
    private func deleteAccountData() {
        Task { @MainActor in
            do {
                // Stop sync service first
                syncService?.stopAutoSync()
                
                // Delete all emails
                let emails = try modelContext.fetch(FetchDescriptor<Email>())
                for email in emails {
                    modelContext.delete(email)
                }
                
                // Delete all conversations
                let conversations = try modelContext.fetch(FetchDescriptor<Conversation>())
                for conversation in conversations {
                    modelContext.delete(conversation)
                }
                
                try modelContext.save()
                
                // Sign out from Gmail
                gmailService.signOut()
                
                print("✅ SettingsView: Successfully deleted all account data")
                
                // Notify parent view of auth change
                onAuthChange?()
                
                dismiss()
                
            } catch {
                print("❌ SettingsView: Failed to delete account data: \(error)")
            }
        }
    }
    
    private func signOutAndSwitchAccount() {
        Task { @MainActor in
            do {
                // Stop sync service first
                syncService?.stopAutoSync()
                
                // Delete all attachments first (to avoid foreign key issues)
                let attachments = try modelContext.fetch(FetchDescriptor<Attachment>())
                print("📧 Deleting \(attachments.count) attachments...")
                for attachment in attachments {
                    modelContext.delete(attachment)
                }
                
                // Delete all emails from previous account
                let emails = try modelContext.fetch(FetchDescriptor<Email>())
                print("📧 Deleting \(emails.count) emails...")
                for email in emails {
                    modelContext.delete(email)
                }
                
                // Delete all conversations from previous account
                let conversations = try modelContext.fetch(FetchDescriptor<Conversation>())
                print("💬 Deleting \(conversations.count) conversations...")
                for conversation in conversations {
                    modelContext.delete(conversation)
                }
                
                // Force save and process pending changes
                modelContext.processPendingChanges()
                try modelContext.save()
                
                print("✅ SettingsView: Cleared all data from previous account")
                
                // Clear any cached data in ContactsService
                ContactsService.shared.clearCache()
                
                // Sign out from Gmail (this should clear auth tokens)
                gmailService.signOut()
                userEmail = ""
                
                // Small delay to ensure everything is cleared
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Notify parent view of auth change
                onAuthChange?()
                
                // Show auth screen for new account
                showingAuth = true
                
            } catch {
                print("❌ SettingsView: Failed to clear account data: \(error)")
            }
        }
    }
}

#Preview {
    SettingsView(gmailService: GmailService(), syncService: nil, onAuthChange: nil)
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}