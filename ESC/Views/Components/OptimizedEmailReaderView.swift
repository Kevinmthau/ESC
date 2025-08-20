import SwiftUI
import WebKit

struct OptimizedEmailReaderView: View {
    let email: Email
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // HTML email viewer
                HTMLEmailView(email: email, isLoading: $isLoading)
                    .edgesIgnoringSafeArea(.bottom)
                
                // Loading overlay
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") {
                    dismiss()
                },
                trailing: Button(action: {
                    showShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
            )
            .sheet(isPresented: $showShareSheet) {
                if let subject = email.subject {
                    let textToShare = """
                    Subject: \(subject)
                    From: \(email.sender) <\(email.senderEmail)>
                    Date: \(email.timestamp)
                    
                    \(email.body)
                    """
                    ShareSheet(items: [textToShare])
                } else {
                    let textToShare = """
                    From: \(email.sender) <\(email.senderEmail)>
                    Date: \(email.timestamp)
                    
                    \(email.body)
                    """
                    ShareSheet(items: [textToShare])
                }
            }
        }
    }
}


#Preview {
    OptimizedEmailReaderView(
        email: Email(
            id: "1",
            messageId: "1",
            sender: "John Doe",
            senderEmail: "john@example.com",
            recipient: "Me",
            recipientEmail: "me@example.com",
            body: """
            This is a test email with multiple lines.
            
            It contains some text and demonstrates how the email reader works.
            
            Best regards,
            John
            """,
            snippet: "This is a test email...",
            timestamp: Date(),
            isFromMe: false,
            conversation: nil,
            subject: "Test Email Subject"
        )
    )
}