import SwiftUI
import WebKit

// MARK: - HTML Email Viewer
struct HTMLEmailView: UIViewRepresentable {
    let email: Email
    @Binding var isLoading: Bool
    @State private var blockRemoteImages: Bool = false // Allow images by default
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        // Enhanced configuration for email rendering
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent() // Don't store cookies/data
        configuration.suppressesIncrementalRendering = false // Allow progressive rendering
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Set up preferences for better email rendering
        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences = preferences
        
        // Allow JavaScript for our image fixing scripts but not for email content
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Content controller for injecting styles and scripts
        let contentController = WKUserContentController()
        
        // Add viewport meta tag for proper mobile rendering
        let viewportScript = """
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
        document.getElementsByTagName('head')[0].appendChild(meta);
        """
        
        let viewportUserScript = WKUserScript(
            source: viewportScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(viewportUserScript)
        
        // Add content blocking rules for privacy
        if blockRemoteImages {
            // CSS to hide remote images initially
            let hideImagesScript = """
            var style = document.createElement('style');
            style.innerHTML = 'img[src^="http"] { display: none !important; }';
            document.head.appendChild(style);
            """
            
            let userScript = WKUserScript(
                source: hideImagesScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(userScript)
        }
        
        configuration.userContentController = contentController
        
        // Create web view with enhanced configuration
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        
        // Set content mode for better scaling
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        
        // Load the email HTML
        loadEmail(in: webView)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload if needed
    }
    
    private func loadEmail(in webView: WKWebView) {
        Task {
            let html = await prepareHTML()
            _ = await MainActor.run {
                webView.loadHTMLString(html, baseURL: nil)
            }
        }
    }
    
    private func prepareHTML() async -> String {
        // Start with HTML body or convert plain text
        var html = email.htmlBody ?? convertPlainTextToHTML(email.body)
        
        // Sanitize dangerous content
        html = sanitizeHTML(html)
        
        // Inline attachments (CID images)
        html = await inlineAttachments(html)
        
        // Wrap with proper HTML structure
        html = wrapHTML(html)
        
        return html
    }
    
    private func sanitizeHTML(_ html: String) -> String {
        var sanitized = html
        
        // Remove dangerous elements
        let dangerousPatterns = [
            #"<script[^>]*>[\s\S]*?</script>"#,
            #"<iframe[^>]*>[\s\S]*?</iframe>"#,
            #"<object[^>]*>[\s\S]*?</object>"#,
            #"<embed[^>]*>"#,
            #"\son\w+\s*=\s*["'][^"']*["']"#,  // onclick, onload, etc.
            #"javascript:"#
        ]
        
        for pattern in dangerousPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        // Don't remove tracking pixels - let them load
        // Some legitimate images might be small
        // sanitized = sanitized.replacingOccurrences(
        //     of: #"<img[^>]*width\s*=\s*["']?1["']?[^>]*height\s*=\s*["']?1["']?[^>]*>"#,
        //     with: "<!-- tracking pixel removed -->",
        //     options: .regularExpression
        // )
        
        return sanitized
    }
    
    private func inlineAttachments(_ html: String) async -> String {
        var result = html
        
        // Convert CID attachments to data URLs
        for attachment in email.attachments {
            guard let data = attachment.data else { continue }
            
            // Create data URL for the attachment
            let base64 = data.base64EncodedString()
            let dataURL = "data:\(attachment.mimeType);base64,\(base64)"
            
            // Look for various CID reference patterns
            var cidPatterns = [
                "cid:\(attachment.id)",
                "\"cid:\(attachment.id)\"",
                "'cid:\(attachment.id)'",
                "cid:\(attachment.filename)",
                "\"cid:\(attachment.filename)\"",
                "'cid:\(attachment.filename)'",
            ]
            
            // Also check without file extension
            if let nameWithoutExt = attachment.filename.split(separator: ".").first {
                cidPatterns.append("cid:\(nameWithoutExt)")
                cidPatterns.append("\"cid:\(nameWithoutExt)\"")
                cidPatterns.append("'cid:\(nameWithoutExt)'")
            }
            
            // Replace all patterns
            for pattern in cidPatterns {
                result = result.replacingOccurrences(of: pattern, with: dataURL, options: .caseInsensitive)
            }
            
            // Also check for attachments referenced by content-id header
            if attachment.id.contains("@") {
                // Strip angle brackets if present
                let cleanId = attachment.id
                    .replacingOccurrences(of: "<", with: "")
                    .replacingOccurrences(of: ">", with: "")
                
                result = result.replacingOccurrences(of: "cid:\(cleanId)", with: dataURL, options: .caseInsensitive)
                result = result.replacingOccurrences(of: "\"cid:\(cleanId)\"", with: "\"\(dataURL)\"", options: .caseInsensitive)
            }
        }
        
        // Log if we have attachments but no CID replacements were made
        if !email.attachments.isEmpty && result == html {
            print("⚠️ Email has \(email.attachments.count) attachments but no CID references were found/replaced")
        }
        
        return result
    }
    
    private func convertPlainTextToHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        
        // Convert URLs to links
        let linked = escaped.replacingOccurrences(
            of: #"(https?://[^\s]+)"#,
            with: "<a href=\"$1\">$1</a>",
            options: .regularExpression
        )
        
        // Convert newlines to <br>
        let formatted = linked.replacingOccurrences(of: "\n", with: "<br>\n")
        
        return formatted
    }
    
    private func wrapHTML(_ content: String) -> String {
        // Minimal CSS that preserves original email styling
        let styles = """
        <style>
            /* Minimal reset - let email styles take precedence */
            * {
                box-sizing: border-box;
                -webkit-text-size-adjust: 100%;
                -ms-text-size-adjust: 100%;
            }
            
            /* Body - minimal defaults, no forced fonts */
            body {
                padding: 15px;
                word-wrap: break-word;
                -webkit-font-smoothing: antialiased;
                -moz-osx-font-smoothing: grayscale;
                background-color: #ffffff;
            }
            
            /* Don't force paragraph spacing if email has its own */
            p {
                margin: 0 0 10px 0;
            }
            
            /* Images - responsive only, preserve original display */
            img {
                max-width: 100%;
                height: auto;
            }
            
            /* Tables - minimal styling */
            table {
                border-collapse: collapse;
            }
            
            /* Links - preserve original styling */
            a[href^="tel"], a[href^="sms"] {
                color: inherit;
                text-decoration: none;
            }
            
            /* Blockquotes - minimal styling for quoted text */
            blockquote {
                margin: 0 0 10px 0;
                padding: 0 0 0 10px;
                border-left: 1px solid #cccccc;
            }
            
            /* Code blocks - basic styling */
            pre {
                overflow-x: auto;
                white-space: pre-wrap;
                word-wrap: break-word;
            }
            
            /* Gmail-specific classes - minimal interference */
            .gmail_quote {
                margin: 0 0 10px 0;
                padding: 0 0 0 10px;
                border-left: 1px solid #cccccc;
            }
            
            /* Prevent auto-linking in iOS */
            .appleLinks a {
                color: inherit !important;
                text-decoration: none !important;
            }
            
            /* Media query for responsive design */
            @media only screen and (max-width: 600px) {
                body {
                    padding: 10px;
                }
                
                table {
                    max-width: 100%;
                }
            }
            
            /* WebKit-specific enhancements */
            @media screen and (-webkit-min-device-pixel-ratio: 0) {
                body {
                    -webkit-font-smoothing: antialiased;
                }
                
                /* Enable momentum scrolling */
                * {
                    -webkit-overflow-scrolling: touch;
                }
            }
        </style>
        """
        
        // Check if content already has HTML structure
        if content.lowercased().contains("<html") {
            // Insert our clean styles
            if content.contains("</head>") {
                return content.replacingOccurrences(of: "</head>", with: "\(styles)\n</head>")
            } else if content.contains("<html") {
                return content.replacingOccurrences(of: "<html[^>]*>", with: "$0\n<head>\(styles)</head>", options: .regularExpression)
            } else {
                return styles + content
            }
        } else {
            // Create minimal HTML document - let the content speak for itself
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
                <title>\(email.subject ?? "Email")</title>
                \(styles)
            </head>
            <body>
                \(content)
            </body>
            </html>
            """
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLEmailView
        
        init(_ parent: HTMLEmailView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            
            // Minimal JavaScript - only fix critical layout issues
            let js = """
            (function() {
                // Only fix tables that are too wide
                var tables = document.querySelectorAll('table');
                tables.forEach(function(table) {
                    if (table.offsetWidth > window.innerWidth - 30) {
                        table.style.maxWidth = '100%';
                    }
                });
                
                // Only fix images that are too wide
                var images = document.querySelectorAll('img');
                images.forEach(function(img) {
                    if (img.offsetWidth > window.innerWidth - 30) {
                        img.style.maxWidth = '100%';
                        img.style.height = 'auto';
                    }
                });
                
                // Remove any absolute positioning that might break layout
                var positioned = document.querySelectorAll('[style*="position: absolute"], [style*="position:absolute"]');
                positioned.forEach(function(el) {
                    if (el.offsetWidth > window.innerWidth || el.offsetHeight > window.innerHeight) {
                        el.style.position = 'relative';
                    }
                });
                
                // Handle preformatted text overflow
                var preElements = document.querySelectorAll('pre');
                preElements.forEach(function(pre) {
                    pre.style.overflowX = 'auto';
                });
            })();
            """
            
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            print("❌ WebView failed to load: \(error)")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial load, block navigation to external links
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

// MARK: - String Extension for HTML Escaping
private extension String {
    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}