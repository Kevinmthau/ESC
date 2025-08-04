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
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailBody: Codable {
    let data: String?
    let size: Int?
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