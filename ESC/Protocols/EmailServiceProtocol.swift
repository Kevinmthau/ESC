import Foundation
import SwiftData

// MARK: - Email Service Protocol
protocol EmailServiceProtocol: AnyObject {
    var isAuthenticated: Bool { get }
    
    func authenticate() async throws
    func signOut() async throws
    
    func fetchEmails(count: Int) async throws -> [Email]
    func fetchMessage(messageId: String) async throws -> GmailMessage
    
    func sendEmail(to recipients: [String],
                   cc: [String],
                   bcc: [String],
                   body: String,
                   subject: String?,
                   inReplyTo: String?,
                   attachments: [(filename: String, data: Data, mimeType: String)]) async throws
    
    func deleteEmail(messageId: String) async throws
    func markAsRead(messageId: String) async throws
    func markAsUnread(messageId: String) async throws
    
    func getUserEmail() async throws -> String
    func getUserDisplayName() async throws -> String
}

// MARK: - Data Sync Protocol
protocol DataSyncProtocol {
    func startSync()
    func stopSync()
    func syncNow() async throws
    func setPollingInterval(_ interval: TimeInterval)
    var isSyncing: Bool { get }
}


enum ContactsAuthorizationStatus {
    case notDetermined
    case restricted
    case denied
    case authorized
}

// MARK: - Storage Protocol
protocol StorageProtocol {
    associatedtype Entity
    
    func save(_ entity: Entity) throws
    func fetch(predicate: Predicate<Entity>?) throws -> [Entity]
    func delete(_ entity: Entity) throws
    func update(_ entity: Entity) throws
    func count(predicate: Predicate<Entity>?) throws -> Int
}


// MARK: - Authentication Manager Protocol
protocol AuthenticationManagerProtocol {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    
    func signIn() async throws -> User
    func signOut() async throws
    func refreshToken() async throws
    func getAccessToken() async throws -> String
}

// MARK: - User Model
struct User {
    let id: String
    let email: String
    let displayName: String
    let profilePictureURL: URL?
}

// MARK: - Cache Protocol
protocol CacheProtocol {
    associatedtype Key: Hashable
    associatedtype Value
    
    func get(_ key: Key) -> Value?
    func set(_ value: Value, for key: Key)
    func remove(_ key: Key)
    func removeAll()
    func contains(_ key: Key) -> Bool
}

// MARK: - Network Service Protocol
protocol NetworkServiceProtocol {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    func upload(data: Data, to endpoint: Endpoint) async throws
    func download(from endpoint: Endpoint) async throws -> Data
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]?
    let queryItems: [URLQueryItem]?
    let body: Data?
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}