import SwiftUI

// MARK: - Navigation Destination
enum NavigationDestination: Hashable {
    case conversationDetail(Conversation)
    case forwardCompose(Email)
    case newConversation
    case settings
}

// MARK: - Navigation Sheet
enum NavigationSheet: Identifiable {
    case compose(Conversation?)
    case forward(Email)
    case settings
    
    var id: String {
        switch self {
        case .compose: return "compose"
        case .forward: return "forward"
        case .settings: return "settings"
        }
    }
}

// MARK: - Navigation Coordinator
@MainActor
class NavigationCoordinator: ObservableObject {
    @Published var navigationPath = NavigationPath()
    @Published var presentedSheet: NavigationSheet?
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var alertTitle = "Error"
    
    // MARK: - Navigation Methods
    
    func navigate(to destination: NavigationDestination) {
        navigationPath.append(destination)
    }
    
    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    func navigateToRoot() {
        navigationPath = NavigationPath()
    }
    
    // MARK: - Sheet Presentation
    
    func presentSheet(_ sheet: NavigationSheet) {
        presentedSheet = sheet
    }
    
    func dismissSheet() {
        presentedSheet = nil
    }
    
    // MARK: - Alert Presentation
    
    func showError(_ error: Error, title: String = "Error") {
        alertTitle = title
        if let appError = error as? AppError {
            alertMessage = appError.localizedDescription
        } else {
            alertMessage = error.localizedDescription
        }
        showAlert = true
    }
    
    func showMessage(_ message: String, title: String = "Info") {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
    
    // MARK: - Deep Linking Support
    
    func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        
        switch components.path {
        case "/conversation":
            if components.queryItems?.first(where: { $0.name == "id" })?.value != nil {
                // TODO: Handle navigation to specific conversation
                // This would need to fetch the conversation from the database
            }
        case "/compose":
            presentSheet(.compose(nil))
        case "/settings":
            presentSheet(.settings)
        default:
            break
        }
    }
}

// MARK: - Navigation Coordinator Holder
struct NavigationCoordinatorHolder {
    @MainActor
    let coordinator = NavigationCoordinator()
}

// MARK: - Environment Key
struct NavigationCoordinatorKey: EnvironmentKey {
    static let defaultValue = NavigationCoordinatorHolder()
}

extension EnvironmentValues {
    var navigationCoordinator: NavigationCoordinator {
        @MainActor get { self[NavigationCoordinatorKey.self].coordinator }
        set { 
            // Setting is not supported for this pattern
        }
    }
}

// MARK: - View Extension
extension View {
    func withNavigationCoordinator(_ coordinator: NavigationCoordinator) -> some View {
        self.environment(\.navigationCoordinator, coordinator)
    }
}