import Foundation
import SwiftData

@Model
final class Attachment: @unchecked Sendable {
    var id: String
    var filename: String
    var mimeType: String
    var size: Int
    var data: Data?
    var email: Email?
    
    init(
        id: String = UUID().uuidString,
        filename: String,
        mimeType: String,
        size: Int,
        data: Data? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.data = data
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