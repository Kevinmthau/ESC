import Foundation
import SwiftData
import WebKit

// MARK: - Gmail Service Protocol
@MainActor
protocol GmailServiceProtocol {
    var isAuthenticated: Bool { get }
    var cachedUserEmail: String? { get }
    
    func authenticate() async throws
    func signOut()
    func fetchEmails() async throws -> [Email]
    func sendEmail(to recipients: [String], cc: [String], bcc: [String], body: String, subject: String?, inReplyTo: String?, attachments: [(filename: String, data: Data, mimeType: String)]) async throws
    func getUserEmail() async throws -> String
    func getUserDisplayName() async throws -> String
}

// MARK: - Data Sync Service Protocol
@MainActor
protocol DataSyncServiceProtocol {
    func startAutoSync()
    func stopAutoSync()
    func syncData(silent: Bool) async
    func mergeEmails(_ emails: [Email]) async
}

// MARK: - Contacts Service Protocol
protocol ContactsServiceProtocol {
    func getContactPhoto(for email: String) async -> Data?
    func getContactName(for email: String) -> String?
    func getAllContacts() -> [(name: String, email: String)]
    func clearCache()
}

// MARK: - Message Parser Protocol
protocol MessageParserProtocol {
    static func parseGmailMessage(_ gmailMessage: GmailMessage) -> Email?
}

// MARK: - HTML Sanitizer Protocol
protocol HTMLSanitizerProtocol {
    func sanitize(_ html: String) -> String
    func htmlToAttributedString(_ html: String, isFromMe: Bool) -> NSAttributedString?
    func analyzeComplexity(_ html: String) -> HTMLSanitizerService.HTMLComplexity
}

// MARK: - WebView Pool Protocol
protocol WebViewPoolProtocol {
    func acquireWebView(allowJavaScript: Bool) -> WKWebView
    func releaseWebView(_ webView: WKWebView)
    func getCachedHeight(for htmlHash: String) -> CGFloat?
    func setCachedHeight(_ height: CGFloat, for htmlHash: String)
}