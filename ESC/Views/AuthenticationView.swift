import SwiftUI

struct AuthenticationView: View {
    let gmailService: GmailService
    let onSuccess: () -> Void
    
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 12) {
                    Text("Connect to Gmail")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Sign in with your Google account to access your Gmail conversations in an iMessage-style interface.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button(action: {
                    authenticateWithGmail()
                }) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "globe")
                        }
                        
                        Text(isAuthenticating ? "Signing In..." : "Sign in with Google")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Gmail Authentication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Authentication Error", isPresented: .constant(errorMessage != nil)) {
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
    
    private func authenticateWithGmail() {
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            do {
                try await gmailService.authenticate()
                await MainActor.run {
                    isAuthenticating = false
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    AuthenticationView(gmailService: GmailService()) {
        print("Authentication successful")
    }
}