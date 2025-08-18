import SwiftUI
import SwiftData

struct ReplyIndicatorView: View {
    let originalEmail: Email?
    let isFromMe: Bool
    
    var body: some View {
        if let original = originalEmail {
            let messageText = original.snippet.isEmpty ? String(original.body.prefix(100)) : original.snippet
            
            // Debug to see what we're trying to display
            let _ = print("📎 ReplyIndicator: Displaying reply to message")
            let _ = print("   Message text: '\(messageText)'")
            let _ = print("   IsFromMe: \(isFromMe)")
            
            // Show a dimmed version of the original message bubble
            HStack {
                if isFromMe {
                    Spacer(minLength: 80)
                }
                
                VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                    // Small "Replying to" label
                    Text("Reply to:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                    
                    // Dimmed message bubble showing the original message
                    Text(messageText)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .lineLimit(2)
                        .opacity(0.6)
                }
                
                if !isFromMe {
                    Spacer(minLength: 80)
                }
            }
            .padding(.bottom, 4)
        }
    }
}