import SwiftUI
import Combine

// MARK: - Base View Model
@MainActor
class BaseViewModel: ObservableObject {
    
    // MARK: - Common Published Properties
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var errorTitle = "Error"
    
    // MARK: - Cancellables
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error, title: String = "Error") {
        errorTitle = title
        
        if let appError = error as? AppError {
            errorMessage = appError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
        
        showError = true
        isLoading = false
    }
    
    func clearError() {
        showError = false
        errorMessage = ""
        errorTitle = "Error"
    }
    
    // MARK: - Loading State
    
    func startLoading() {
        isLoading = true
        clearError()
    }
    
    func stopLoading() {
        isLoading = false
    }
    
    // MARK: - Async Operations
    
    func performAsyncOperation<T>(_ operation: @escaping () async throws -> T,
                                  onSuccess: @escaping (T) -> Void,
                                  onError: ((Error) -> Void)? = nil) {
        Task {
            startLoading()
            do {
                let result = try await operation()
                await MainActor.run {
                    onSuccess(result)
                    stopLoading()
                }
            } catch {
                await MainActor.run {
                    if let errorHandler = onError {
                        errorHandler(error)
                    } else {
                        handleError(error)
                    }
                    stopLoading()
                }
            }
        }
    }
    
    // MARK: - Validation
    
    func validateEmail(_ email: String) -> Bool {
        EmailValidator.isValid(email)
    }
    
    func validateNotEmpty(_ text: String, fieldName: String) throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AppError.custom("\(fieldName) cannot be empty")
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        cancellables.removeAll()
        clearError()
        stopLoading()
    }
    
    deinit {
        // Cleanup handled automatically by ARC
    }
}

// MARK: - List View Model Base
@MainActor
class BaseListViewModel<T: Identifiable>: BaseViewModel {
    @Published var items: [T] = []
    @Published var searchText = ""
    @Published var isRefreshing = false
    @Published var hasMoreData = true
    @Published var currentPage = 0
    
    // Override in subclasses
    var itemsPerPage: Int { 20 }
    
    // MARK: - Pagination
    
    func loadNextPage() {
        guard !isLoading && hasMoreData else { return }
        currentPage += 1
        loadItems(page: currentPage)
    }
    
    func refresh() {
        currentPage = 0
        hasMoreData = true
        items = []
        loadItems(page: 0)
    }
    
    // Override in subclasses
    func loadItems(page: Int) {
        // Implement in subclass
    }
    
    // MARK: - Search
    
    var filteredItems: [T] {
        if searchText.isEmpty {
            return items
        }
        return filterItems(items, searchText: searchText)
    }
    
    // Override in subclasses for custom filtering
    func filterItems(_ items: [T], searchText: String) -> [T] {
        return items
    }
    
    // MARK: - Item Management
    
    func addItem(_ item: T) {
        items.append(item)
    }
    
    func removeItem(_ item: T) {
        items.removeAll { $0.id == item.id }
    }
    
    func updateItem(_ item: T) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }
}

// MARK: - Detail View Model Base
@MainActor
class BaseDetailViewModel<T>: BaseViewModel {
    @Published var item: T?
    @Published var isEditing = false
    @Published var hasChanges = false
    
    init(item: T? = nil) {
        self.item = item
        super.init()
    }
    
    // MARK: - Editing
    
    func startEditing() {
        isEditing = true
    }
    
    func cancelEditing() {
        isEditing = false
        hasChanges = false
        // Revert changes if needed
    }
    
    func saveChanges() async throws {
        guard hasChanges else { return }
        // Implement save logic in subclass
        isEditing = false
        hasChanges = false
    }
    
    // MARK: - Change Tracking
    
    func markAsChanged() {
        hasChanges = true
    }
}