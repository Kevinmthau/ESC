import SwiftUI

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(icon: String = "tray",
         title: String,
         message: String,
         actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .padding(.top, 10)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Common Empty States
extension EmptyStateView {
    static var noConversations: EmptyStateView {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "No Conversations",
            message: "Start a new conversation to get started",
            actionTitle: "New Conversation"
        )
    }
    
    static var noMessages: EmptyStateView {
        EmptyStateView(
            icon: "envelope",
            title: "No Messages",
            message: "Your inbox is empty"
        )
    }
    
    static var noSearchResults: EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results",
            message: "Try adjusting your search criteria"
        )
    }
    
    static var notAuthenticated: EmptyStateView {
        EmptyStateView(
            icon: "person.crop.circle.badge.exclamationmark",
            title: "Not Signed In",
            message: "Please sign in to view your conversations",
            actionTitle: "Sign In"
        )
    }
    
    static var networkError: EmptyStateView {
        EmptyStateView(
            icon: "wifi.exclamationmark",
            title: "Connection Error",
            message: "Please check your internet connection and try again",
            actionTitle: "Retry"
        )
    }
}