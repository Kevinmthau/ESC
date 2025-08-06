import SwiftUI

struct MessageInputView: View {
    @Binding var messageText: String
    var isTextFieldFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.gray.opacity(0.3))
            
            HStack(spacing: 8) {
                textInputField
                
                if showSendButton {
                    sendButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
        }
    }
    
    private var textInputField: some View {
        TextField("Message", text: $messageText, axis: .vertical)
            .textFieldStyle(PlainTextFieldStyle())
            .font(.body)
            .lineLimit(1...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(20)
            .frame(minHeight: 36)
            .focused(isTextFieldFocused)
    }
    
    private var sendButton: some View {
        Button(action: {
            onSend()
            isTextFieldFocused.wrappedValue = false
        }) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
        }
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    private var showSendButton: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var messageText = "Hello"
        @FocusState private var isFocused: Bool
        
        var body: some View {
            VStack {
                Spacer()
                MessageInputView(
                    messageText: $messageText,
                    isTextFieldFocused: $isFocused,
                    onSend: {
                        print("Send tapped")
                    }
                )
            }
        }
    }
    
    return PreviewWrapper()
}