import SwiftUI
import QuickLook

struct MessageBubbleView: View {
    let email: Email
    var allEmails: [Email] = []
    @State private var htmlContentHeight: CGFloat = 100
    @State private var showingEmailReader = false
    var onForward: ((Email) -> Void)?
    var onReply: ((Email) -> Void)?
    
    private var originalEmail: Email? {
        guard let replyToId = email.inReplyToMessageId else { 
            return nil 
        }
        
        // Debug logging
        print("🔍 Message \(email.id) is looking for reply-to ID: \(replyToId)")
        print("   This message snippet: \(email.snippet.prefix(30))...")
        print("   Available messages in conversation (\(allEmails.count) total):")
        for e in allEmails {
            print("     - ID: \(e.id), messageId: \(e.messageId)")
            print("       Snippet: \(e.snippet.prefix(30))...")
        }
        
        // Try to find by messageId first (for RFC2822 IDs), then by Gmail ID (for local messages)
        let original = allEmails.first { $0.messageId == replyToId } ?? 
                      allEmails.first { $0.id == replyToId }
        
        if let original = original {
            print("✅ Found original message!")
            print("   Original snippet: \(original.snippet)")
        } else {
            print("⚠️ Could not find original message with ID: \(replyToId)")
            print("   Searched for messageId=\(replyToId) OR id=\(replyToId)")
        }
        return original
    }
    
    var body: some View {
        HStack {
            if email.isFromMe {
                Spacer(minLength: 50)
                sentMessageBubble
            } else {
                receivedMessageBubble
                Spacer(minLength: 50)
            }
        }
        .contextMenu {
            Button(action: {
                onReply?(email)
            }) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            
            Button(action: {
                onForward?(email)
            }) {
                Label("Forward", systemImage: "arrowshape.turn.up.right")
            }
        }
        .fullScreenCover(isPresented: $showingEmailReader) {
            EmailReaderView(email: email)
        }
    }
    
    private var sentMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Show reply indicator above the message bubble if this is a reply
            if let original = originalEmail {
                ReplyIndicatorView(originalEmail: original, isFromMe: true)
            }
            
            VStack(alignment: .trailing, spacing: 8) {
                // For forwarded messages, show attachments separately below
                let isForwarded = isForwardedMessage()
                if !email.attachments.isEmpty && !isForwarded {
                    attachmentsView(isFromMe: true)
                }
                
                // Show text if not empty
                if !email.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Group {
                        if let htmlBody = email.htmlBody, !htmlBody.isEmpty {
                            // Check if this is a reply or marketing email
                            if isLikelyReplyEmail() {
                                // For replies, show the text with link detection
                                let previewText = createPreviewText(from: email.body)
                                if LinkDetector.containsLink(previewText) {
                                    LinkedTextView(text: previewText, isFromMe: true)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                } else {
                                    Text(previewText)
                                        .lineLimit(nil)
                                        .multilineTextAlignment(.leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                            } else {
                                // For marketing/newsletter emails, show preview with tap to expand
                                Button(action: {
                                    showingEmailReader = true
                                }) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(createPreviewText(from: email.body))
                                            .lineLimit(5)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.richtext.fill")
                                                .font(.caption)
                                            Text("View full message")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .opacity(0.9)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: 280, alignment: .leading)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } else {
                            // Render plain text with link detection
                            let cleanedBody = MessageCleaner.cleanMessageBody(email.body)
                            if LinkDetector.containsLink(cleanedBody) {
                                LinkedTextView(text: cleanedBody, isFromMe: true)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            } else {
                                Text(cleanedBody)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                }
            }
            
            timestampView
                .padding(.trailing, 4)
            
            // Show attachments below bubble for forwarded messages
            if !email.attachments.isEmpty && isForwardedMessage() {
                attachmentsView(isFromMe: true)
                    .padding(.top, 4)
            }
        }
    }
    
    private var receivedMessageBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Show reply indicator above the message bubble if this is a reply
            if let original = originalEmail {
                ReplyIndicatorView(originalEmail: original, isFromMe: false)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                // For forwarded messages, show attachments separately below
                let isForwarded = isForwardedMessage()
                if !email.attachments.isEmpty && !isForwarded {
                    attachmentsView(isFromMe: false)
                }
                
                // Show text if not empty
                if !email.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Group {
                        if let htmlBody = email.htmlBody, !htmlBody.isEmpty {
                            // Check if this is a reply or marketing email
                            if isLikelyReplyEmail() {
                                // For replies, show the text with link detection
                                let previewText = createPreviewText(from: email.body)
                                if LinkDetector.containsLink(previewText) {
                                    LinkedTextView(text: previewText, isFromMe: false)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color(.systemGray5))
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                } else {
                                    Text(previewText)
                                        .lineLimit(nil)
                                        .multilineTextAlignment(.leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color(.systemGray5))
                                        .foregroundColor(.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                            } else {
                                // For marketing/newsletter emails, show preview with tap to expand
                                Button(action: {
                                    showingEmailReader = true
                                }) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(createPreviewText(from: email.body))
                                            .lineLimit(5)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.richtext.fill")
                                                .font(.caption)
                                            Text("View full message")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .opacity(0.8)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: 280, alignment: .leading)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } else {
                            // Render plain text with link detection
                            let cleanedBody = MessageCleaner.cleanMessageBody(email.body)
                            if LinkDetector.containsLink(cleanedBody) {
                                LinkedTextView(text: cleanedBody, isFromMe: false)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            } else {
                                Text(cleanedBody)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                }
            }
            
            timestampView
                .padding(.leading, 4)
            
            // Show attachments below bubble for forwarded messages
            if !email.attachments.isEmpty && isForwardedMessage() {
                attachmentsView(isFromMe: false)
                    .padding(.top, 4)
            }
        }
    }
    
    private var timestampView: some View {
        Text(email.timestamp, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)
    }
    
    private func createPreviewText(from body: String) -> String {
        // Check if this is a forwarded message
        let bodyLower = body.lowercased()
        let isForwarded = bodyLower.contains("---------- forwarded message") || 
                         bodyLower.contains("-------- original message") ||
                         bodyLower.contains("begin forwarded message")
        
        if isForwarded {
            // For forwarded messages, show only the header info and user's message
            let lines = body.components(separatedBy: .newlines)
            var headerLines: [String] = []
            var userMessage = ""
            var inForwardedSection = false
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                // Check if we've hit the forwarded message delimiter
                if trimmedLine.contains("---------- Forwarded message") || 
                   trimmedLine.contains("-------- Original message") {
                    inForwardedSection = true
                    headerLines.append("📧 Forwarded message")
                    continue
                }
                
                // If we're in the forwarded section, look for headers
                if inForwardedSection {
                    if trimmedLine.starts(with: "From:") {
                        // Extract just the name from "From: Name <email>"
                        if let nameStart = trimmedLine.firstIndex(of: ":"),
                           let emailStart = trimmedLine.firstIndex(of: "<") {
                            let nameRange = trimmedLine.index(after: nameStart)..<emailStart
                            let name = trimmedLine[nameRange].trimmingCharacters(in: .whitespaces)
                            headerLines.append("From: \(name)")
                        } else {
                            headerLines.append(String(trimmedLine.prefix(50)))
                        }
                    } else if trimmedLine.starts(with: "Date:") {
                        // Shorten the date
                        if let dateStart = trimmedLine.firstIndex(of: ":") {
                            let dateStr = trimmedLine[trimmedLine.index(after: dateStart)...]
                                .trimmingCharacters(in: .whitespaces)
                            // Try to extract just the date part
                            let dateComponents = dateStr.split(separator: " ")
                            if dateComponents.count >= 4 {
                                let shortDate = dateComponents.prefix(4).joined(separator: " ")
                                headerLines.append("Date: \(shortDate)")
                            } else {
                                headerLines.append("Date: \(dateStr.prefix(20))")
                            }
                        }
                    } else if trimmedLine.starts(with: ">") {
                        // We've hit the actual forwarded content, stop here
                        break
                    }
                } else if !trimmedLine.isEmpty && !inForwardedSection {
                    // This is the user's message before the forward
                    userMessage += trimmedLine + " "
                }
            }
            
            // Format the preview for forwarded messages
            var preview = ""
            
            // Add user's message at the top if present
            if !userMessage.trimmingCharacters(in: .whitespaces).isEmpty {
                preview = String(userMessage.prefix(150)).trimmingCharacters(in: .whitespaces)
                if !headerLines.isEmpty {
                    preview += "\n\n"
                }
            }
            
            // Add the forward headers
            if !headerLines.isEmpty {
                preview += headerLines.joined(separator: "\n")
            }
            
            // Note: The "View full message" button is added automatically by the calling code
            // when isLikelyReplyEmail() returns false (which it does for forwarded messages)
            
            return preview.isEmpty ? "Forwarded message" : preview
        } else {
            // Original logic for non-forwarded messages
            let cleaned = MessageCleaner.cleanMessageBody(body)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove excessive whitespace
            let normalized = cleaned
                .replacingOccurrences(of: "\n\n\n", with: "\n\n")
                .replacingOccurrences(of: "  ", with: " ")
            
            // Create preview from first part of text
            let lines = normalized.components(separatedBy: .newlines)
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let preview = nonEmptyLines.prefix(3).joined(separator: " ")
            
            // Limit to reasonable length
            if preview.count > 150 {
                return String(preview.prefix(147)) + "..."
            }
            return preview.isEmpty ? "View message content" : preview
        }
    }
    
    private func isForwardedMessage() -> Bool {
        let bodyLower = email.body.lowercased()
        return bodyLower.contains("---------- forwarded message") || 
               bodyLower.contains("-------- original message") ||
               bodyLower.contains("begin forwarded message") ||
               bodyLower.contains("fwd:") ||
               bodyLower.contains("fw:")
    }
    
    private func isLikelyReplyEmail() -> Bool {
        // Check if this is likely a simple reply email (not forwarded or marketing)
        
        let bodyLower = email.body.lowercased()
        
        // Check if it's a forwarded email - these should show the button
        let forwardIndicators = [
            "---------- forwarded message",
            "-------- original message",
            "begin forwarded message",
            "fwd:",
            "fw:"
        ]
        
        for indicator in forwardIndicators {
            if bodyLower.contains(indicator) {
                return false // Forwarded emails should show the button
            }
        }
        
        // Short emails are likely simple replies
        if email.body.count < 500 {
            return true
        }
        
        // Check for simple reply indicators
        let replyIndicators = [
            "on .* wrote:",
            "sent from my",
            "> on ",
            ">> ",
            "re:"
        ]
        
        for indicator in replyIndicators {
            if bodyLower.contains(indicator) && !bodyLower.contains("forwarded") {
                return true
            }
        }
        
        // Check if HTML is minimal (just formatting, not marketing layout)
        if let htmlBody = email.htmlBody {
            // Marketing emails typically have lots of images, tables, and divs
            let hasMarketingElements = htmlBody.contains("<table") && 
                                       (htmlBody.contains("width=\"600") || 
                                        htmlBody.contains("width:600") ||
                                        htmlBody.contains("<img"))
            
            // Forwarded emails might have complex HTML
            if bodyLower.contains("forward") || bodyLower.contains("fwd:") {
                return false
            }
            
            return !hasMarketingElements
        }
        
        return false
    }
    
    @ViewBuilder
    private func attachmentsView(isFromMe: Bool) -> some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
            ForEach(Array(email.attachments.enumerated()), id: \.offset) { _, attachment in
                if attachment.isImage {
                    // Show image inline like iMessage
                    ImageAttachmentView(attachment: attachment, isFromMe: isFromMe)
                } else {
                    // Show other attachments as file bubbles
                    AttachmentBubbleView(attachment: attachment, isFromMe: isFromMe)
                }
            }
        }
    }
}

struct AttachmentBubbleView: View {
    let attachment: Attachment
    let isFromMe: Bool
    @State private var tempFileURL: URL?
    
    var body: some View {
        Button(action: {
            handleAttachmentTap()
        }) {
            HStack(spacing: 8) {
                // Icon
                if attachment.isImage,
                   let data = attachment.data,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: iconForAttachment)
                        .font(.title3)
                        .foregroundColor(isFromMe ? .white : .blue)
                        .frame(width: 40, height: 40)
                        .background(isFromMe ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text(attachment.formattedSize)
                        .font(.caption2)
                        .opacity(0.8)
                }
                .foregroundColor(isFromMe ? .white : .primary)
                
                Spacer(minLength: 0)
                
                // Download/share indicator
                Image(systemName: "square.and.arrow.down")
                    .font(.caption)
                    .foregroundColor(isFromMe ? .white.opacity(0.8) : .blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFromMe ? Color.blue : Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 250)
        }
        .quickLookPreview($tempFileURL)
    }
    
    private var iconForAttachment: String {
        let mimeType = attachment.mimeType
        switch mimeType {
        case "application/pdf":
            return "doc.fill"
        case _ where mimeType.hasPrefix("text/"):
            return "doc.text.fill"
        case _ where mimeType.hasPrefix("application/vnd.ms-excel"),
             _ where mimeType.hasPrefix("application/vnd.openxmlformats-officedocument.spreadsheetml"):
            return "tablecells.fill"
        case _ where mimeType.hasPrefix("application/vnd.ms-powerpoint"),
             _ where mimeType.hasPrefix("application/vnd.openxmlformats-officedocument.presentationml"):
            return "slider.horizontal.below.rectangle"
        case _ where mimeType.hasPrefix("application/msword"),
             _ where mimeType.hasPrefix("application/vnd.openxmlformats-officedocument.wordprocessingml"):
            return "doc.text.fill"
        case _ where mimeType.hasPrefix("application/zip"),
             _ where mimeType.hasPrefix("application/x-"),
             _ where mimeType.contains("compress"):
            return "archivebox.fill"
        case _ where mimeType.hasPrefix("audio/"):
            return "music.note"
        case _ where mimeType.hasPrefix("video/"):
            return "video.fill"
        case _ where mimeType.hasPrefix("image/"):
            return "photo.fill"
        default:
            return "paperclip"
        }
    }
    
    private func handleAttachmentTap() {
        // Save attachment to temp directory for preview
        guard let data = attachment.data else {
            print("❌ No data available for attachment: \(attachment.filename)")
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let cleanedFilename = attachment.filename.replacingOccurrences(of: " ", with: "_")
        let fileURL = tempDir.appendingPathComponent(cleanedFilename)
        
        do {
            // Remove old file if it exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            try data.write(to: fileURL)
            tempFileURL = fileURL
            print("✅ Prepared file for preview: \(fileURL.lastPathComponent)")
        } catch {
            print("❌ Error saving attachment: \(error)")
        }
    }
}

struct ImageAttachmentView: View {
    let attachment: Attachment
    let isFromMe: Bool
    @State private var showingImageViewer = false
    
    var body: some View {
        Group {
            if let data = attachment.data,
               let uiImage = UIImage(data: data) {
                Button(action: {
                    showingImageViewer = true
                }) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 250, maxHeight: 300)
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .fullScreenCover(isPresented: $showingImageViewer) {
                    ImageViewerView(image: uiImage, filename: attachment.filename)
                }
            } else {
                // Placeholder while loading
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 250, height: 200)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading image...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
    }
}

struct ImageViewerView: View {
    let image: UIImage
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showingShareSheet = false
    @State private var tempFileURL: URL?
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1), 4)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    withAnimation(.spring()) {
                                        if scale < 1 {
                                            scale = 1
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1 {
                                    scale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2
                                }
                            }
                        }
                }
            }
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        saveImageToTempAndShare()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.7), for: .navigationBar)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = tempFileURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    private func saveImageToTempAndShare() {
        guard let data = image.jpegData(compressionQuality: 1.0) ?? image.pngData() else { return }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            tempFileURL = fileURL
            showingShareSheet = true
        } catch {
            print("Error saving image: \(error)")
        }
    }
}


struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    VStack(spacing: 8) {
        MessageBubbleView(
            email: Email(
                id: "1",
                messageId: "1",
                sender: "John",
                senderEmail: "john@example.com",
                recipient: "Me",
                recipientEmail: "me@example.com",
                body: "Hello there!",
                snippet: "Hello there!",
                timestamp: Date(),
                isFromMe: false,
                conversation: nil
            ),
            allEmails: []
        )
        
        MessageBubbleView(
            email: Email(
                id: "2",
                messageId: "2",
                sender: "Me",
                senderEmail: "me@example.com",
                recipient: "John",
                recipientEmail: "john@example.com",
                body: "Hi! How are you?",
                snippet: "Hi! How are you?",
                timestamp: Date(),
                isFromMe: true,
                conversation: nil,
                inReplyToMessageId: "1"
            ),
            allEmails: [Email(
                id: "1",
                messageId: "1",
                sender: "John",
                senderEmail: "john@example.com",
                recipient: "Me",
                recipientEmail: "me@example.com",
                body: "Hello there!",
                snippet: "Hello there!",
                timestamp: Date(),
                isFromMe: false,
                conversation: nil
            )]
        )
    }
    .padding()
}