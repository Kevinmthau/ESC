import SwiftUI
import QuickLook

struct MessageBubbleView: View {
    let email: Email
    
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
    }
    
    private var sentMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 2) {
            VStack(alignment: .trailing, spacing: 8) {
                // Show attachments if any
                if !email.attachments.isEmpty {
                    attachmentsView(isFromMe: true)
                }
                
                // Show text if not empty
                if !email.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(MessageCleaner.cleanMessageBody(email.body))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            
            timestampView
                .padding(.trailing, 4)
        }
    }
    
    private var receivedMessageBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 8) {
                // Show attachments if any
                if !email.attachments.isEmpty {
                    attachmentsView(isFromMe: false)
                }
                
                // Show text if not empty
                if !email.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(MessageCleaner.cleanMessageBody(email.body))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            
            timestampView
                .padding(.leading, 4)
        }
    }
    
    private var timestampView: some View {
        Text(email.timestamp, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)
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
        MessageBubbleView(email: Email(
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
        ))
        
        MessageBubbleView(email: Email(
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
            conversation: nil
        ))
    }
    .padding()
}