import Foundation
import SwiftData

@Model
final class Attachment: @unchecked Sendable {
    var id: String
    var filename: String
    var mimeType: String
    var size: Int
    var data: Data?
    var contentId: String?
    var email: Email?
    
    init(
        id: String = UUID().uuidString,
        filename: String,
        mimeType: String,
        size: Int,
        data: Data? = nil,
        contentId: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.data = data
        self.contentId = contentId
    }
    
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }
    
    var isPDF: Bool {
        mimeType == "application/pdf"
    }
    
    var fileExtension: String {
        if let ext = filename.split(separator: ".").last {
            return String(ext).lowercased()
        }
        return ""
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}