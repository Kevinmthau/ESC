import SwiftUI

// MARK: - View Extensions
extension View {
    
    // MARK: - Conditional Modifiers
    
    @ViewBuilder
    func conditionalModifier<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func ifLet<Value, Transform: View>(_ value: Value?, transform: (Self, Value) -> Transform) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
    
    // MARK: - Layout Helpers
    
    func fillWidth(alignment: Alignment = .center) -> some View {
        self.frame(maxWidth: .infinity, alignment: alignment)
    }
    
    func fillHeight(alignment: Alignment = .center) -> some View {
        self.frame(maxHeight: .infinity, alignment: alignment)
    }
    
    func fill(alignment: Alignment = .center) -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
    
    // MARK: - Styling
    
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(Color(.systemBackground))
            .cornerRadius(cornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    func glassEffect() -> some View {
        self
            .background(.ultraThinMaterial)
            .cornerRadius(12)
    }
    
    // MARK: - Animations
    
    func fadeIn(duration: Double = 0.3) -> some View {
        self
            .transition(.opacity)
            .animation(.easeIn(duration: duration), value: UUID())
    }
    
    func slideIn(edge: Edge = .trailing, duration: Double = 0.3) -> some View {
        self
            .transition(.move(edge: edge))
            .animation(.easeInOut(duration: duration), value: UUID())
    }
    
    // MARK: - Keyboard
    
    func hideKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    func onTapToHideKeyboard() -> some View {
        self.onTapGesture {
            hideKeyboard()
        }
    }
    
    // MARK: - Debug
    
    func debugBorder(_ color: Color = .red, width: CGFloat = 1) -> some View {
        #if DEBUG
        return self.border(color, width: width)
        #else
        return self
        #endif
    }
    
    func debugPrint(_ items: Any...) -> some View {
        #if DEBUG
        print(items)
        #endif
        return self
    }
}

// MARK: - Color Extensions
extension Color {
    static let primaryBackground = Color("PrimaryBackground")
    static let secondaryBackground = Color("SecondaryBackground")
    static let primaryText = Color("PrimaryText")
    static let secondaryText = Color("SecondaryText")
    static let accentBlue = Color("AccentBlue")
    static let successGreen = Color("SuccessGreen")
    static let errorRed = Color("ErrorRed")
    static let warningOrange = Color("WarningOrange")
    
    // Message bubble colors
    static let sentMessageBackground = Color.blue
    static let receivedMessageBackground = Color(.systemGray5)
    static let sentMessageText = Color.white
    static let receivedMessageText = Color.primary
}

// MARK: - Font Extensions
extension Font {
    static func customFont(_ name: String = "System", size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if name == "System" {
            return .system(size: size, weight: weight, design: .default)
        }
        return .custom(name, size: size)
    }
    
    // Semantic fonts
    static let conversationTitle = Font.system(size: 18, weight: .semibold)
    static let conversationSnippet = Font.system(size: 14, weight: .regular)
    static let messageBody = Font.system(size: 16, weight: .regular)
    static let messageTimestamp = Font.system(size: 12, weight: .regular)
    static let sectionHeader = Font.system(size: 20, weight: .bold)
}

// MARK: - Image Extensions
extension Image {
    func circularAvatar(size: CGFloat = 40) -> some View {
        self
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
    
    func thumbnail(maxSize: CGFloat = 100) -> some View {
        self
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxSize, maxHeight: maxSize)
            .cornerRadius(8)
    }
}

// MARK: - Text Extensions
extension Text {
    func primaryStyle() -> Text {
        self
            .foregroundColor(.primaryText)
            .font(.body)
    }
    
    func secondaryStyle() -> Text {
        self
            .foregroundColor(.secondaryText)
            .font(.subheadline)
    }
    
    func errorStyle() -> Text {
        self
            .foregroundColor(.errorRed)
            .font(.caption)
    }
    
    func timestampStyle() -> Text {
        self
            .foregroundColor(.secondaryText)
            .font(.messageTimestamp)
    }
}

// MARK: - Binding Extensions
extension Binding {
    func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                self.wrappedValue = newValue
                handler(newValue)
            }
        )
    }
    
    func map<T>(get: @escaping (Value) -> T, set: @escaping (T) -> Value) -> Binding<T> {
        Binding<T>(
            get: { get(self.wrappedValue) },
            set: { self.wrappedValue = set($0) }
        )
    }
}

// MARK: - Animation Extensions
extension Animation {
    static let messageAppear = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let sheetPresentation = Animation.easeInOut(duration: 0.3)
    static let buttonTap = Animation.easeInOut(duration: 0.1)
}