import SwiftUI

extension View {
    /// Applies a conditional modifier based on a boolean condition
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Dismisses the keyboard
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    /// Adds a border with rounded corners
    func roundedBorder(_ color: Color, width: CGFloat = 1, cornerRadius: CGFloat = 8) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color, lineWidth: width)
        )
    }
    
    /// Centers the view horizontally
    func centerHorizontally() -> some View {
        HStack {
            Spacer()
            self
            Spacer()
        }
    }
    
    /// Centers the view vertically
    func centerVertically() -> some View {
        VStack {
            Spacer()
            self
            Spacer()
        }
    }
    
    /// Adds a loading overlay
    func loadingOverlay(_ isLoading: Bool) -> some View {
        self.overlay(
            Group {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            }
        )
    }
    
    /// Adds a shadow with default parameters
    func defaultShadow() -> some View {
        self.shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    /// Makes the view tappable with a content shape
    func tappable() -> some View {
        self.contentShape(Rectangle())
    }
}

// MARK: - Keyboard Responsive Modifier
struct KeyboardResponsive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.25)) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = 0
                }
            }
    }
}

extension View {
    func keyboardResponsive() -> some View {
        self.modifier(KeyboardResponsive())
    }
}