import SwiftUI
import LinkPresentation

struct LinkedTextView: View {
    let text: String
    let isFromMe: Bool
    @State private var linkMetadata: [URL: LPLinkMetadata] = [:]
    @State private var isLoadingMetadata: Set<URL> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text with tappable links
            textWithLinks
            
            // Link previews
            linkPreviews
        }
    }
    
    @ViewBuilder
    private var textWithLinks: some View {
        let links = LinkDetector.detectLinks(in: text)
        
        if links.isEmpty {
            // No links, show plain text
            Text(text)
                .foregroundColor(isFromMe ? .white : .primary)
        } else {
            // Create attributed text with links
            let attributedString = createAttributedString(text: text, links: links)
            Text(attributedString)
                .foregroundColor(isFromMe ? .white : .primary)
                .tint(isFromMe ? Color.white.opacity(0.9) : Color.blue)
        }
    }
    
    @ViewBuilder
    private var linkPreviews: some View {
        let links = LinkDetector.detectLinks(in: text)
        
        ForEach(links.prefix(1), id: \.url) { link in
            if let metadata = linkMetadata[link.url] {
                LinkPreviewView(metadata: metadata, isFromMe: isFromMe, url: link.url)
                    .padding(.top, 4)
            } else if isLoadingMetadata.contains(link.url) {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading preview...")
                        .font(.caption)
                        .foregroundColor(isFromMe ? .white.opacity(0.7) : .secondary)
                }
                .padding(.vertical, 8)
            } else {
                EmptyView()
                    .onAppear {
                        loadMetadata(for: link.url)
                    }
            }
        }
    }
    
    private func createAttributedString(text: String, links: [(url: URL, range: NSRange)]) -> AttributedString {
        var attributedString = AttributedString(text)
        
        for link in links {
            if let range = Range<AttributedString.Index>(link.range, in: attributedString) {
                attributedString[range].link = link.url
                attributedString[range].underlineStyle = .single
            }
        }
        
        return attributedString
    }
    
    private func loadMetadata(for url: URL) {
        isLoadingMetadata.insert(url)
        
        Task {
            do {
                let provider = LPMetadataProvider()
                provider.timeout = 5 // Reduce timeout to 5 seconds
                let metadata = try await provider.startFetchingMetadata(for: url)
                
                await MainActor.run {
                    linkMetadata[url] = metadata
                    isLoadingMetadata.remove(url)
                }
            } catch {
                // Silently fail for link preview errors to reduce console noise
                await MainActor.run {
                    _ = isLoadingMetadata.remove(url)
                }
            }
        }
    }
}

struct LinkPreviewView: View {
    let metadata: LPLinkMetadata
    let isFromMe: Bool
    let url: URL
    @State private var image: UIImage?
    
    var body: some View {
        Button(action: {
            UIApplication.shared.open(url)
        }) {
            HStack(spacing: 12) {
                // Thumbnail
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFromMe ? Color.white.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "link")
                                .foregroundColor(isFromMe ? .white.opacity(0.5) : .gray)
                        )
                }
                
                // Title and URL
                VStack(alignment: .leading, spacing: 2) {
                    if let title = metadata.title {
                        Text(title)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .foregroundColor(isFromMe ? .white : .primary)
                    }
                    
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(isFromMe ? .white.opacity(0.7) : .secondary)
                }
                
                Spacer(minLength: 0)
                
                // Arrow icon
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(isFromMe ? .white.opacity(0.7) : .blue)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFromMe ? Color.white.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFromMe ? Color.white.opacity(0.2) : Color.gray.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let imageProvider = metadata.imageProvider else { return }
        
        imageProvider.loadObject(ofClass: UIImage.self) { object, error in
            if let image = object as? UIImage {
                DispatchQueue.main.async {
                    self.image = image
                }
            } else if let error = error {
                print("Failed to load image: \(error)")
            }
        }
    }
}