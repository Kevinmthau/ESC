import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    @Binding var messageText: String
    @Binding var selectedAttachments: [(filename: String, data: Data, mimeType: String)]
    var isTextFieldFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var showingAttachmentMenu = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Show selected attachments if any
            if !selectedAttachments.isEmpty {
                attachmentsList
            }
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            HStack(spacing: 8) {
                // Paperclip button
                attachmentButton
                
                textInputField
                
                if showSendButton {
                    sendButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 10, matching: .images)
        .onChange(of: selectedPhotos) { _, newValue in
            Task {
                await loadSelectedPhotos(newValue)
            }
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [
                .pdf,
                .plainText,
                .commaSeparatedText,
                .tabSeparatedText,
                .utf8PlainText,
                .rtf,
                .data,
                .item,
                .content
            ],
            allowsMultipleSelection: true
        ) { result in
            handleDocumentSelection(result)
        }
    }
    
    private var textInputField: some View {
        TextField("Message", text: $messageText, axis: .vertical)
            .textFieldStyle(PlainTextFieldStyle())
            .font(.body)
            .lineLimit(1...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(20)
            .frame(minHeight: 36)
            .focused(isTextFieldFocused)
    }
    
    private var sendButton: some View {
        Button(action: {
            onSend()
            isTextFieldFocused.wrappedValue = false
        }) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
        }
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    private var showSendButton: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedAttachments.isEmpty
    }
    
    private var attachmentButton: some View {
        Menu {
            Button(action: {
                showingPhotoPicker = true
            }) {
                Label("Photo Library", systemImage: "photo")
            }
            
            Button(action: {
                showingDocumentPicker = true
            }) {
                Label("Files", systemImage: "doc")
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
        }
    }
    
    private var attachmentsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedAttachments.enumerated()), id: \.offset) { index, attachment in
                    AttachmentThumbnailView(
                        attachment: attachment,
                        onRemove: {
                            selectedAttachments.remove(at: index)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.gray.opacity(0.05))
    }
    
    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let filename = "image_\(UUID().uuidString.prefix(8)).jpg"
                selectedAttachments.append((filename: filename, data: data, mimeType: "image/jpeg"))
            }
        }
        selectedPhotos = []
    }
    
    private func handleDocumentSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                // Start accessing a security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    print("❌ Failed to access security-scoped resource: \(url)")
                    continue
                }
                
                defer {
                    // Stop accessing the security-scoped resource
                    url.stopAccessingSecurityScopedResource()
                }
                
                do {
                    let data = try Data(contentsOf: url)
                    let filename = url.lastPathComponent
                    let mimeType = getMimeType(for: url.pathExtension)
                    
                    selectedAttachments.append((filename: filename, data: data, mimeType: mimeType))
                    print("✅ Successfully loaded document: \(filename) (\(data.count) bytes)")
                } catch {
                    print("❌ Error reading document \(url.lastPathComponent): \(error)")
                }
            }
        case .failure(let error):
            print("❌ Error selecting documents: \(error)")
        }
    }
    
    private func getMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        // Documents
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "rtf": return "application/rtf"
        
        // Text
        case "txt": return "text/plain"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        case "xml": return "application/xml"
        
        // Images
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "tiff", "tif": return "image/tiff"
        
        // Archives
        case "zip": return "application/zip"
        case "rar": return "application/vnd.rar"
        case "7z": return "application/x-7z-compressed"
        case "tar": return "application/x-tar"
        case "gz": return "application/gzip"
        
        // Audio
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/m4a"
        case "aac": return "audio/aac"
        case "ogg": return "audio/ogg"
        
        // Video
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        
        default: return "application/octet-stream"
        }
    }
}

struct AttachmentThumbnailView: View {
    let attachment: (filename: String, data: Data, mimeType: String)
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                if attachment.mimeType.hasPrefix("image/"),
                   let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: iconForMimeType(attachment.mimeType))
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Text(attachment.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 60)
            }
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .offset(x: 5, y: -5)
        }
    }
    
    private func iconForMimeType(_ mimeType: String) -> String {
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
}

#Preview {
    struct PreviewWrapper: View {
        @State private var messageText = "Hello"
        @State private var attachments: [(filename: String, data: Data, mimeType: String)] = []
        @FocusState private var isFocused: Bool
        
        var body: some View {
            VStack {
                Spacer()
                MessageInputView(
                    messageText: $messageText,
                    selectedAttachments: $attachments,
                    isTextFieldFocused: $isFocused,
                    onSend: {
                        print("Send tapped with \(attachments.count) attachments")
                    }
                )
            }
        }
    }
    
    return PreviewWrapper()
}