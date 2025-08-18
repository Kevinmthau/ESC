import Foundation

struct MessageListResponse: Codable {
    let messages: [MessageItem]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct MessageItem: Codable {
    let id: String
    let threadId: String
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String?
    let snippet: String?
    let internalDate: String?
    let labelIds: [String]?
    let payload: GmailPayload?
}

struct GmailPayload: Codable {
    let headers: [GmailHeader]?
    let parts: [GmailPayload]?
    let body: GmailBody?
    let mimeType: String?
    let filename: String?
    let partId: String?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailBody: Codable {
    let data: String?
    let size: Int?
    let attachmentId: String?
}

struct GmailProfile: Codable {
    let emailAddress: String
    let messagesTotal: Int?
    let threadsTotal: Int?
    let historyId: String?
}

struct SendMessageRequest: Codable {
    let raw: String
}

struct SendMessageResponse: Codable {
    let id: String
    let threadId: String?
    let labelIds: [String]?
}

struct AttachmentResponse: Codable {
    let size: Int
    let data: String?
}

// Google People API models for getting user's name
struct GooglePersonResponse: Codable {
    let names: [GooglePersonName]?
}

struct GooglePersonName: Codable {
    let displayName: String?
    let givenName: String?
    let familyName: String?
}

// Google OAuth2 UserInfo API model
struct GoogleUserInfo: Codable {
    let id: String?
    let email: String?
    let name: String?
    let given_name: String?
    let family_name: String?
    let picture: String?
    let verified_email: Bool?
}