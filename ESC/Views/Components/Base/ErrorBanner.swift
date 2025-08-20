import SwiftUI

// MARK: - Error Banner
struct ErrorBanner: View {
    @Binding var isShowing: Bool
    let message: String
    let type: BannerType
    let duration: Double
    let action: (() -> Void)?
    
    enum BannerType {
        case error
        case warning
        case success
        case info
        
        var backgroundColor: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .success: return .green
            case .info: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .error: return "exclamationmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    init(isShowing: Binding<Bool>,
         message: String,
         type: BannerType = .error,
         duration: Double = 3.0,
         action: (() -> Void)? = nil) {
        self._isShowing = isShowing
        self.message = message
        self.type = type
        self.duration = duration
        self.action = action
    }
    
    var body: some View {
        VStack {
            if isShowing {
                HStack(spacing: 12) {
                    Image(systemName: type.icon)
                        .foregroundColor(.white)
                        .font(.title3)
                    
                    Text(message)
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if action != nil {
                        Button(action: action!) {
                            Text("Retry")
                                .foregroundColor(.white)
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                    
                    Button(action: { isShowing = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(4)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(type.backgroundColor)
                .cornerRadius(10)
                .shadow(radius: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    if duration > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation {
                                isShowing = false
                            }
                        }
                    }
                }
            }
        }
        .animation(.spring(), value: isShowing)
    }
}

// MARK: - View Modifier
struct BannerModifier: ViewModifier {
    @Binding var showError: Bool
    @Binding var showSuccess: Bool
    let errorMessage: String
    let successMessage: String
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            VStack {
                ErrorBanner(
                    isShowing: $showError,
                    message: errorMessage,
                    type: .error
                )
                
                ErrorBanner(
                    isShowing: $showSuccess,
                    message: successMessage,
                    type: .success
                )
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - View Extension
extension View {
    func banner(showError: Binding<Bool>,
                errorMessage: String,
                showSuccess: Binding<Bool> = .constant(false),
                successMessage: String = "") -> some View {
        self.modifier(BannerModifier(
            showError: showError,
            showSuccess: showSuccess,
            errorMessage: errorMessage,
            successMessage: successMessage
        ))
    }
}