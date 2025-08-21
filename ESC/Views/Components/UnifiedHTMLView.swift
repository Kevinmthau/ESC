import SwiftUI
import WebKit

struct UnifiedHTMLView: UIViewRepresentable {
    let htmlContent: String
    let configuration: Configuration
    @Binding var isLoading: Bool
    
    struct Configuration {
        let enableJavaScript: Bool
        let blockRemoteImages: Bool
        let injectCustomCSS: String?
        let handleCIDAttachments: Bool
        let attachments: [Attachment]
        
        static let basic = Configuration(
            enableJavaScript: false,
            blockRemoteImages: false,
            injectCustomCSS: nil,
            handleCIDAttachments: false,
            attachments: []
        )
        
        static let email = Configuration(
            enableJavaScript: true,
            blockRemoteImages: false,
            injectCustomCSS: EmailStyles.responsive,
            handleCIDAttachments: true,
            attachments: []
        )
        
        static func emailWithAttachments(_ attachments: [Attachment]) -> Configuration {
            Configuration(
                enableJavaScript: true,
                blockRemoteImages: false,
                injectCustomCSS: EmailStyles.responsive,
                handleCIDAttachments: true,
                attachments: attachments
            )
        }
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = configuration.enableJavaScript
        
        if configuration.handleCIDAttachments {
            config.setURLSchemeHandler(
                CIDSchemeHandler(attachments: configuration.attachments),
                forURLScheme: "cid"
            )
        }
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        var processedHTML = htmlContent
        
        // Process CID attachments if enabled
        if configuration.handleCIDAttachments {
            processedHTML = processInlineImages(processedHTML)
        }
        
        // Apply custom CSS if provided
        if let customCSS = configuration.injectCustomCSS {
            processedHTML = wrapWithCSS(processedHTML, css: customCSS)
        }
        
        // Block remote images if needed
        if configuration.blockRemoteImages {
            processedHTML = blockRemoteImages(in: processedHTML)
        }
        
        webView.loadHTMLString(processedHTML, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: UnifiedHTMLView
        
        init(_ parent: UnifiedHTMLView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            
            // Inject JavaScript for responsive behavior if enabled
            if parent.configuration.enableJavaScript {
                let jsCode = """
                    var meta = document.createElement('meta');
                    meta.name = 'viewport';
                    meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0';
                    document.getElementsByTagName('head')[0].appendChild(meta);
                """
                webView.evaluateJavaScript(jsCode)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, 
                    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
    
    private func processInlineImages(_ html: String) -> String {
        var processedHTML = html
        
        for attachment in configuration.attachments {
            if let contentId = attachment.contentId {
                let cidPattern = "src=\"cid:\(contentId)\""
                let mimeType = attachment.mimeType
                if let base64String = attachment.data?.base64EncodedString() {
                    let dataURL = "src=\"data:\(mimeType);base64,\(base64String)\""
                    processedHTML = processedHTML.replacingOccurrences(of: cidPattern, with: dataURL)
                }
            }
        }
        
        return processedHTML
    }
    
    private func wrapWithCSS(_ html: String, css: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>\(css)</style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
    
    private func blockRemoteImages(in html: String) -> String {
        // Simple regex to find and replace image sources
        let pattern = #"<img[^>]*src=["']https?://[^"']*["'][^>]*>"#
        return html.replacingOccurrences(
            of: pattern,
            with: "<img src=\"\" alt=\"[Remote image blocked]\">",
            options: .regularExpression
        )
    }
}

private class CIDSchemeHandler: NSObject, WKURLSchemeHandler {
    let attachments: [Attachment]
    
    init(attachments: [Attachment]) {
        self.attachments = attachments
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let contentId = url.host else {
            urlSchemeTask.didFailWithError(NSError(domain: "CIDSchemeHandler", code: 0))
            return
        }
        
        if let attachment = attachments.first(where: { $0.contentId == contentId }),
           let data = attachment.data {
            
            let response = URLResponse(
                url: url,
                mimeType: attachment.mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } else {
            urlSchemeTask.didFailWithError(NSError(domain: "CIDSchemeHandler", code: 404))
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Task cancelled
    }
}

private enum EmailStyles {
    static let responsive = """
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 100%;
            margin: 0;
            padding: 10px;
            word-wrap: break-word;
            -webkit-text-size-adjust: 100%;
        }
        
        img {
            max-width: 100%;
            height: auto;
            display: block;
            margin: 10px 0;
        }
        
        table {
            max-width: 100%;
            border-collapse: collapse;
            margin: 10px 0;
        }
        
        td, th {
            padding: 8px;
            border: 1px solid #ddd;
        }
        
        blockquote {
            border-left: 3px solid #ccc;
            margin-left: 0;
            padding-left: 15px;
            color: #666;
        }
        
        pre {
            background: #f4f4f4;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
        }
        
        a {
            color: #007AFF;
            text-decoration: none;
        }
        
        @media (prefers-color-scheme: dark) {
            body {
                background-color: #1c1c1e;
                color: #e5e5e7;
            }
            
            blockquote {
                border-left-color: #48484a;
                color: #98989d;
            }
            
            pre {
                background: #2c2c2e;
            }
            
            td, th {
                border-color: #48484a;
            }
        }
        """
}