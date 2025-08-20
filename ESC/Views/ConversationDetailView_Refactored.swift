import SwiftUI
import SwiftData

struct ConversationDetailView_Refactored: View {
    @Bindable var conversation: Conversation
    @ObservedObject var gmailService: GmailService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contactsService: ContactsService
    
    @StateObject private var viewModel: ConversationDetailViewModel
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isRecipientFocused: Bool
    @State private var scrollToId: String?
    @State private var forwardedEmail: Email?
    
    init(conversation: Conversation, gmailService: GmailService) {
        self.conversation = conversation
        self.gmailService = gmailService
        
        // Initialize ViewModel - this will need to be done in onAppear
        // since we need the modelContext from the environment
        self._viewModel = StateObject(wrappedValue: ConversationDetailViewModel(
            conversation: conversation,
            gmailService: gmailService,
            modelContext: conversation.modelContext!,
            contactsService: ContactsService.shared
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header section
                if viewModel.isNewConversation {
                    recipientSection
                } else {
                    ContactHeaderView(conversation: conversation)
                }
                
                // Messages section
                messageScrollView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(viewModel.isNewConversation ? "New Message" : conversation.contactName)
        .onAppear {
            setupView()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(item: $forwardedEmail) { email in
            ForwardComposeView(
                originalEmail: email,
                gmailService: gmailService,
                modelContext: modelContext
            )
        }
    }
    
    private var recipientSection: some View {
        VStack(spacing: 0) {
            MultipleRecipientsField(
                recipients: $viewModel.toRecipients,
                ccRecipients: $viewModel.ccRecipients,
                bccRecipients: $viewModel.bccRecipients
            )
            
            Divider()
                .background(Color.gray.opacity(0.3))
        }
        .background(Color.white)
    }
    
    private var messageScrollView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.isNewConversation {
                        emptyConversationView
                    } else {
                        messagesListView
                    }
                }
                .background(Color.white)
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.emails.count) { oldCount, newCount in
                    handleEmailCountChange(oldCount: oldCount, newCount: newCount, proxy: proxy)
                }
                .onChange(of: isTextFieldFocused) { _, focused in
                    handleTextFieldFocusChange(focused: focused, proxy: proxy)
                }
                .onChange(of: scrollToId) { _, newValue in
                    handleScrollToId(newValue, proxy: proxy)
                }
            }
            
            // Reply preview
            if let replyEmail = viewModel.replyingToEmail {
                ReplyPreviewView(
                    email: replyEmail,
                    onDismiss: viewModel.cancelReply
                )
            }
            
            // Message input
            MessageInputView(
                messageText: $viewModel.messageText,
                selectedAttachments: $viewModel.selectedAttachments,
                isTextFieldFocused: $isTextFieldFocused,
                onSend: {
                    Task {
                        await viewModel.sendMessage()
                    }
                }
            )
        }
    }
    
    private var emptyConversationView: some View {
        VStack {
            Spacer()
            Text("Start a new conversation with \(conversation.contactName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
    }
    
    private var messagesListView: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.conversationEmails, id: \.id) { email in
                MessageBubbleView(
                    email: email,
                    allEmails: viewModel.conversationEmails,
                    isGroupConversation: conversation.isGroupConversation,
                    onForward: { forwardedEmail = $0 },
                    onReply: { viewModel.handleReply(to: $0) }
                )
            }
            
            // Bottom spacer for better scrolling
            Color.clear
                .frame(height: 50)
                .id("bottom")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Helper Methods
    private func setupView() {
        Task {
            if contactsService.authorizationStatus == .notDetermined {
                _ = await contactsService.requestAccess()
            }
            if contactsService.authorizationStatus == .authorized {
                await contactsService.fetchContacts()
            }
        }
        
        if !viewModel.isNewConversation {
            viewModel.loadEmails()
            viewModel.markAsRead()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isRecipientFocused = true
            }
        }
    }
    
    private func handleEmailCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
        if (oldCount == 0 && newCount > 0) || newCount > oldCount {
            if let lastEmail = viewModel.conversationEmails.last {
                scrollToId = lastEmail.id
            }
        }
    }
    
    private func handleTextFieldFocusChange(focused: Bool, proxy: ScrollViewProxy) {
        // Handled by defaultScrollAnchor
    }
    
    private func handleScrollToId(_ id: String?, proxy: ScrollViewProxy) {
        guard let id = id else { return }
        proxy.scrollTo(id, anchor: .bottom)
        scrollToId = nil
    }
}

// MARK: - Reply Preview View
struct ReplyPreviewView: View {
    let email: Email
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            
            HStack {
                Spacer(minLength: 60)
                
                Text(email.snippet.isEmpty ? MessageCleaner.createCleanSnippet(email.body) : email.snippet)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .lineLimit(2)
                    .opacity(0.8)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}