import SwiftUI
import WebKit

struct EmailReaderView: View {
    let email: Email
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var showingShareSheet = false
    @State private var emailContent: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                // Content
                VStack(spacing: 0) {
                    // Email header
                    emailHeader
                        .padding()
                        .background(Color(.secondarySystemBackground))
                    
                    Divider()
                    
                    // Email body
                    if let htmlBody = email.htmlBody, !htmlBody.isEmpty {
                        FullScreenHTMLView(
                            htmlContent: htmlBody,
                            isLoading: $isLoading
                        )
                    } else {
                        ScrollView {
                            Text(email.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    
                    // Attachments bar if present
                    if !email.attachments.isEmpty {
                        Divider()
                        attachmentsBar
                    }
                }
                
                // Loading indicator
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            replyToEmail()
                        }) {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        
                        Button(action: {
                            forwardEmail()
                        }) {
                            Label("Forward", systemImage: "arrowshape.turn.up.right")
                        }
                        
                        Button(action: {
                            shareEmail()
                        }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            markAsUnread()
                        }) {
                            Label(email.isRead ? "Mark as Unread" : "Mark as Read", 
                                  systemImage: email.isRead ? "envelope.badge" : "envelope.open")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if !emailContent.isEmpty {
                ShareSheet(items: [emailContent])
            }
        }
    }
    
    private var emailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // From
            HStack {
                Text("From:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.sender)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                    Text(email.senderEmail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // To
            HStack {
                Text("To:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.recipient)
                        .font(.system(.body, design: .default))
                    Text(email.recipientEmail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Date
            HStack {
                Text("Date:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
                
                Text(email.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.body, design: .default))
                
                Spacer()
            }
        }
    }
    
    private var attachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(email.attachments.enumerated()), id: \.offset) { _, attachment in
                    AttachmentChipView(attachment: attachment)
                }
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Actions
    
    private func replyToEmail() {
        // TODO: Implement reply functionality
        print("Reply to email")
    }
    
    private func forwardEmail() {
        // TODO: Implement forward functionality
        print("Forward email")
    }
    
    private func shareEmail() {
        // Prepare email content for sharing
        var content = "From: \(email.sender) <\(email.senderEmail)>\n"
        content += "To: \(email.recipient) <\(email.recipientEmail)>\n"
        content += "Date: \(email.timestamp.formatted())\n\n"
        content += email.body
        
        emailContent = content
        showingShareSheet = true
    }
    
    private func markAsUnread() {
        // TODO: Implement mark as unread
        email.isRead.toggle()
    }
}

// Full screen HTML renderer
struct FullScreenHTMLView: UIViewRepresentable {
    let htmlContent: String
    @Binding var isLoading: Bool
    @State private var hasLoaded = false
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        configuration.allowsInlineMediaPlayback = true
        
        // Configure preferences
        configuration.preferences = WKPreferences()
        
        // Add user script to properly scale content
        let source = """
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
            document.getElementsByTagName('head')[0].appendChild(meta);
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        
        // Enable zooming
        webView.scrollView.minimumZoomScale = 0.5
        webView.scrollView.maximumZoomScale = 3.0
        
        // Load content immediately
        let styledHTML = wrapHTMLForFullScreen(htmlContent)
        webView.loadHTMLString(styledHTML, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only load once to prevent flickering
        // The content is already loaded in makeUIView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func wrapHTMLForFullScreen(_ html: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=0.8, shrink-to-fit=yes">
            <style>
                * {
                    box-sizing: border-box;
                    max-width: 100% !important;
                }
                
                body {
                    margin: 0;
                    padding: 16px;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.5;
                    color: #000;
                    background-color: #fff;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                    -webkit-text-size-adjust: none;
                    width: 100%;
                    overflow-x: hidden;
                }
                
                @media (prefers-color-scheme: dark) {
                    body {
                        color: #fff;
                        background-color: #000;
                    }
                    
                    a { color: #5AC8FA; }
                    
                    img {
                        opacity: 0.9;
                    }
                    
                    table, th, td {
                        border-color: rgba(255,255,255,0.2) !important;
                    }
                    
                    blockquote {
                        border-left-color: rgba(255,255,255,0.4) !important;
                    }
                    
                    code, pre {
                        background-color: rgba(255,255,255,0.1) !important;
                    }
                }
                
                /* Content styling */
                p { margin: 0 0 12px 0; }
                h1, h2, h3, h4, h5, h6 { margin: 16px 0 12px 0; }
                ul, ol { margin: 12px 0; padding-left: 24px; }
                
                /* Links */
                a {
                    color: #007AFF;
                    text-decoration: underline;
                }
                
                /* Images */
                img {
                    max-width: 100% !important;
                    width: auto !important;
                    height: auto !important;
                    display: block;
                    margin: 12px auto;
                }
                
                /* Tables */
                table {
                    border-collapse: collapse;
                    max-width: 100% !important;
                    width: auto !important;
                    margin: 12px 0;
                    overflow-x: auto;
                    display: block;
                    font-size: 12px;
                }
                
                /* Ensure all table cells don't overflow */
                td, th {
                    max-width: 300px !important;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                
                th, td {
                    border: 1px solid rgba(0,0,0,0.1);
                    padding: 8px 12px;
                    text-align: left;
                }
                
                th {
                    background-color: rgba(0,0,0,0.05);
                    font-weight: 600;
                }
                
                /* Blockquotes */
                blockquote {
                    margin: 12px 0;
                    padding-left: 16px;
                    border-left: 4px solid rgba(0,0,0,0.2);
                    color: rgba(0,0,0,0.7);
                }
                
                /* Code */
                code {
                    background-color: rgba(0,0,0,0.05);
                    padding: 2px 6px;
                    border-radius: 4px;
                    font-family: 'SF Mono', Consolas, monospace;
                    font-size: 14px;
                }
                
                pre {
                    background-color: rgba(0,0,0,0.05);
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                }
                
                pre code {
                    background-color: transparent;
                    padding: 0;
                }
                
                /* Gmail specific */
                .gmail_signature { 
                    margin-top: 24px;
                    padding-top: 12px;
                    border-top: 1px solid rgba(0,0,0,0.1);
                }
                
                .gmail_quote {
                    margin-top: 24px;
                    padding: 12px;
                    background-color: rgba(0,0,0,0.02);
                    border-left: 2px solid rgba(0,0,0,0.2);
                }
                
                /* Handle marketing email layouts */
                div[style*="width: 600px"],
                div[style*="width:600px"],
                table[width="600"],
                table[width="650"] {
                    max-width: 100% !important;
                    width: 100% !important;
                }
                
                /* Remove fixed widths from any element */
                *[style*="width"] {
                    max-width: 100% !important;
                }
                
                /* Ensure wrapper divs don't cause overflow */
                div {
                    max-width: 100% !important;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: FullScreenHTMLView
        
        init(_ parent: FullScreenHTMLView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            
            // Inject JavaScript to ensure proper scaling
            let js = """
                // Find all images and scale them properly
                var images = document.getElementsByTagName('img');
                for (var i = 0; i < images.length; i++) {
                    var img = images[i];
                    if (img.naturalWidth > window.innerWidth - 32) {
                        img.style.width = '100%';
                        img.style.height = 'auto';
                    }
                }
                
                // Find tables and make them scrollable if too wide
                var tables = document.getElementsByTagName('table');
                for (var i = 0; i < tables.length; i++) {
                    var table = tables[i];
                    if (table.offsetWidth > window.innerWidth - 32) {
                        table.style.display = 'block';
                        table.style.overflowX = 'auto';
                        table.style.maxWidth = '100%';
                    }
                }
                
                // Adjust body width
                document.body.style.maxWidth = '100%';
                document.documentElement.style.maxWidth = '100%';
            """
            
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

// Attachment chip view for the attachments bar
struct AttachmentChipView: View {
    let attachment: Attachment
    @State private var tempFileURL: URL?
    
    var body: some View {
        Button(action: {
            handleAttachmentTap()
        }) {
            HStack(spacing: 6) {
                Image(systemName: iconForMimeType(attachment.mimeType))
                    .font(.system(size: 14))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename)
                        .font(.caption)
                        .lineLimit(1)
                    Text(attachment.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PlainButtonStyle())
        .quickLookPreview($tempFileURL)
    }
    
    private func iconForMimeType(_ mimeType: String) -> String {
        switch mimeType {
        case _ where mimeType.hasPrefix("image/"):
            return "photo"
        case "application/pdf":
            return "doc.richtext"
        case _ where mimeType.hasPrefix("video/"):
            return "video"
        case _ where mimeType.hasPrefix("audio/"):
            return "music.note"
        default:
            return "paperclip"
        }
    }
    
    private func handleAttachmentTap() {
        guard let data = attachment.data else { return }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(attachment.filename)
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try data.write(to: fileURL)
            tempFileURL = fileURL
        } catch {
            print("Error preparing attachment: \(error)")
        }
    }
}

#Preview {
    EmailReaderView(
        email: Email(
            id: "1",
            messageId: "1",
            sender: "John Doe",
            senderEmail: "john@example.com",
            recipient: "Jane Smith",
            recipientEmail: "jane@example.com",
            body: "This is a test email with some content.",
            htmlBody: "<h1>Test Email</h1><p>This is a <b>test email</b> with <i>HTML content</i>.</p>",
            snippet: "This is a test email...",
            timestamp: Date(),
            isRead: true,
            isFromMe: false
        )
    )
}