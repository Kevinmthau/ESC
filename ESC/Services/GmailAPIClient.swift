import Foundation

actor GmailAPIClient {
    private let baseURL = Constants.Gmail.baseURL
    private let authManager = GoogleAuthManager.shared
    
    private var accessToken: String? {
        authManager.accessToken
    }
    
    // MARK: - Message Operations
    
    func fetchMessageIds() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/users/me/messages") else {
            throw GmailError.invalidURL
        }
        
        let request = try await createAuthenticatedRequest(url: url)
        let response = try await performRequest(request, responseType: MessageListResponse.self)
        
        return response.messages?.map { $0.id } ?? []
    }
    
    func fetchMessage(messageId: String) async throws -> GmailMessage {
        guard let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)") else {
            throw GmailError.invalidURL
        }
        
        let request = try await createAuthenticatedRequest(url: url)
        return try await performRequest(request, responseType: GmailMessage.self)
    }
    
    func fetchAttachment(messageId: String, attachmentId: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)/attachments/\(attachmentId)") else {
            throw GmailError.invalidURL
        }
        
        let request = try await createAuthenticatedRequest(url: url)
        let response = try await performRequest(request, responseType: AttachmentResponse.self)
        
        // Decode base64url encoded data
        guard let data = response.data else {
            throw GmailError.fetchFailed("No attachment data")
        }
        
        // Gmail uses URL-safe base64, need to convert
        let base64 = data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let paddedBase64 = base64.padding(toLength: ((base64.count + 3) / 4) * 4,
                                          withPad: "=",
                                          startingAt: 0)
        
        guard let decodedData = Data(base64Encoded: paddedBase64) else {
            throw GmailError.decodingFailed("Failed to decode attachment data")
        }
        
        return decodedData
    }
    
    func sendMessage(raw: String) async throws -> SendMessageResponse {
        guard let url = URL(string: "\(baseURL)/users/me/messages/send") else {
            throw GmailError.invalidURL
        }
        
        var request = try await createAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = SendMessageRequest(raw: raw)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        return try await performRequest(request, responseType: SendMessageResponse.self)
    }
    
    func getUserProfile() async throws -> GmailProfile {
        guard let url = URL(string: "\(baseURL)/users/me/profile") else {
            throw GmailError.invalidURL
        }
        
        let request = try await createAuthenticatedRequest(url: url)
        return try await performRequest(request, responseType: GmailProfile.self)
    }
    
    // MARK: - Private Helper Methods
    
    private func createAuthenticatedRequest(url: URL) async throws -> URLRequest {
        guard let token = accessToken else {
            throw GmailError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    private func performRequest<T: Codable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        // Configure URLSession with timeout settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0  // 30 second timeout
        configuration.timeoutIntervalForResource = 60.0  // 60 second resource timeout
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    return try JSONDecoder().decode(T.self, from: data)
                case 401:
                    // Token expired, refresh and retry
                    try await authManager.refreshAccessToken()
                    let retryRequest = try await createAuthenticatedRequest(url: request.url!)
                    let (retryData, retryResponse) = try await session.data(for: retryRequest)
                    
                    if let retryHttpResponse = retryResponse as? HTTPURLResponse,
                       retryHttpResponse.statusCode >= 200 && retryHttpResponse.statusCode < 300 {
                        return try JSONDecoder().decode(T.self, from: retryData)
                    } else {
                        throw GmailError.fetchFailed("Authentication failed after retry")
                    }
                case 400...499:
                    throw GmailError.fetchFailed("Client error: \(httpResponse.statusCode)")
                case 500...599:
                    throw GmailError.fetchFailed("Server error: \(httpResponse.statusCode)")
                default:
                    throw GmailError.fetchFailed("Unexpected status: \(httpResponse.statusCode)")
                }
            } else {
                throw NetworkError.invalidResponse
            }
            
        } catch let error as GmailError {
            throw error
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.unknown(error)
        }
    }
}