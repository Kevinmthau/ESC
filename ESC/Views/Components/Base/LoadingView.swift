import SwiftUI

// MARK: - Loading View
struct LoadingView: View {
    let message: String
    let style: LoadingStyle
    
    enum LoadingStyle {
        case fullScreen
        case inline
        case overlay
    }
    
    init(message: String = "Loading...", style: LoadingStyle = .inline) {
        self.message = message
        self.style = style
    }
    
    var body: some View {
        switch style {
        case .fullScreen:
            fullScreenLoading
        case .inline:
            inlineLoading
        case .overlay:
            overlayLoading
        }
    }
    
    private var fullScreenLoading: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                
                Text(message)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(40)
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(radius: 10)
        }
    }
    
    private var inlineLoading: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var overlayLoading: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
}

// MARK: - View Extension
extension View {
    func loadingOverlay(isLoading: Bool, message: String = "Loading...") -> some View {
        self.overlay(
            Group {
                if isLoading {
                    LoadingView(message: message, style: .overlay)
                }
            }
        )
    }
    
    func fullScreenLoading(isLoading: Bool, message: String = "Loading...") -> some View {
        self.overlay(
            Group {
                if isLoading {
                    LoadingView(message: message, style: .fullScreen)
                }
            }
        )
    }
}