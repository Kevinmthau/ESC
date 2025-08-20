import SwiftUI
import WebKit

/// Optimized HTML message view with security, performance, and UX improvements
struct OptimizedHTMLMessageView: UIViewRepresentable {
    let htmlContent: String
    let isFromMe: Bool
    @Binding var contentHeight: CGFloat
    @State private var webView: WKWebView?
    @State private var hasCalculatedHeight = false
    
    private let sanitizer = HTMLSanitizerService.shared
    private let poolManager = WebViewPoolManager.shared
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // Sanitize HTML first
        let sanitizedHTML = sanitizer.sanitize(htmlContent)
        
        // Check complexity and render accordingly
        let complexity = sanitizer.analyzeComplexity(sanitizedHTML)
        
        switch complexity {
        case .simple:
            // Use AttributedString for simple HTML
            if let attributedString = sanitizer.htmlToAttributedString(sanitizedHTML, isFromMe: isFromMe) {
                let textView = UITextView()
                textView.attributedText = attributedString
                textView.isEditable = false
                textView.isSelectable = true
                textView.isScrollEnabled = false
                textView.backgroundColor = .clear
                textView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
                textView.linkTextAttributes = [
                    .foregroundColor: isFromMe ? UIColor(red: 0.68, green: 0.85, blue: 0.9, alpha: 1.0) : UIColor.systemBlue
                ]
                
                containerView.addSubview(textView)
                textView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    textView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])
                
                // Calculate height
                let size = textView.sizeThatFits(CGSize(width: UIScreen.main.bounds.width - 100, height: .infinity))
                DispatchQueue.main.async {
                    contentHeight = size.height
                }
                
                return containerView
            }
        case .moderate, .complex:
            // Use WebView but with optimizations
            let webView = createOptimizedWebView(context: context)
            self.webView = webView
            
            containerView.addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: containerView.topAnchor),
                webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
            // Load sanitized content
            let styledHTML = wrapHTMLWithOptimizedStyling(sanitizedHTML)
            webView.loadHTMLString(styledHTML, baseURL: nil)
            
            return containerView
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Don't reload to prevent flickering
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createOptimizedWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Security: Disable JavaScript using modern API
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        
        // Performance: Enable content blocking
        configuration.suppressesIncrementalRendering = false
        
        // Data detection
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        
        // Add Content Security Policy
        let cspScript = """
        var meta = document.createElement('meta');
        meta.httpEquiv = 'Content-Security-Policy';
        meta.content = "default-src 'self' data:; img-src https: data:; style-src 'unsafe-inline';";
        document.getElementsByTagName('head')[0].appendChild(meta);
        """
        
        let userScript = WKUserScript(
            source: cspScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(userScript)
        
        // Add height observer (works without JavaScript enabled for basic height)
        configuration.userContentController.add(context.coordinator, name: "heightObserver")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        // Enable text selection
        webView.allowsLinkPreview = true
        
        return webView
    }
    
    private func wrapHTMLWithOptimizedStyling(_ html: String) -> String {
        let textColor = isFromMe ? "white" : "black"
        let linkColor = isFromMe ? "#ADD8E6" : "#007AFF"
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <meta http-equiv="Content-Security-Policy" content="default-src 'self' data:; img-src https: data:; style-src 'unsafe-inline'; script-src 'none';">
            <style>
                :root {
                    -webkit-text-size-adjust: 100%;
                    text-size-adjust: 100%;
                }
                
                * {
                    max-width: 100% !important;
                    box-sizing: border-box;
                    -webkit-box-sizing: border-box;
                }
                
                body {
                    margin: 0;
                    padding: 12px 16px;
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 16px;
                    line-height: 1.4;
                    color: \(textColor);
                    background-color: transparent;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                    -webkit-font-smoothing: antialiased;
                    -moz-osx-font-smoothing: grayscale;
                }
                
                /* Typography */
                p { margin: 0 0 8px 0; }
                p:last-child { margin-bottom: 0; }
                h1, h2, h3, h4, h5, h6 { 
                    margin: 12px 0 8px 0;
                    font-weight: 600;
                }
                h1 { font-size: 24px; }
                h2 { font-size: 20px; }
                h3 { font-size: 18px; }
                h4, h5, h6 { font-size: 16px; }
                
                /* Lists */
                ul, ol { 
                    margin: 8px 0; 
                    padding-left: 20px;
                }
                li { margin: 4px 0; }
                
                /* Links */
                a {
                    color: \(linkColor);
                    text-decoration: underline;
                    word-break: break-word;
                    -webkit-touch-callout: default;
                }
                
                /* Images */
                img {
                    max-width: 100% !important;
                    height: auto !important;
                    display: block;
                    margin: 8px auto;
                    border-radius: 8px;
                    -webkit-touch-callout: default;
                }
                
                /* Prevent small tracking images */
                img[width="1"], img[height="1"] {
                    display: none !important;
                }
                
                /* Tables */
                table {
                    border-collapse: collapse;
                    width: auto !important;
                    max-width: 100% !important;
                    margin: 8px 0;
                    display: block;
                    overflow-x: auto;
                    -webkit-overflow-scrolling: touch;
                }
                
                th, td {
                    border: 1px solid \(isFromMe ? "rgba(255,255,255,0.3)" : "rgba(0,0,0,0.1)");
                    padding: 6px 10px;
                    text-align: left;
                    min-width: 60px;
                }
                
                th {
                    background-color: \(isFromMe ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.05)");
                    font-weight: 600;
                }
                
                /* Blockquotes */
                blockquote {
                    margin: 8px 0;
                    padding-left: 12px;
                    border-left: 3px solid \(isFromMe ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.3)");
                    color: \(isFromMe ? "rgba(255,255,255,0.8)" : "rgba(0,0,0,0.6)");
                }
                
                /* Code */
                code {
                    background-color: \(isFromMe ? "rgba(0,0,0,0.2)" : "rgba(0,0,0,0.05)");
                    padding: 2px 4px;
                    border-radius: 3px;
                    font-family: 'SF Mono', Consolas, 'Courier New', monospace;
                    font-size: 14px;
                }
                
                pre {
                    background-color: \(isFromMe ? "rgba(0,0,0,0.2)" : "rgba(0,0,0,0.05)");
                    padding: 8px;
                    border-radius: 4px;
                    overflow-x: auto;
                    -webkit-overflow-scrolling: touch;
                }
                
                pre code {
                    background-color: transparent;
                    padding: 0;
                }
                
                /* Horizontal rules */
                hr {
                    border: none;
                    height: 1px;
                    background: \(isFromMe ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.1)");
                    margin: 12px 0;
                }
                
                /* Hide Gmail specific elements */
                .gmail_signature,
                .gmail_quote,
                .gmail_attr,
                .gmail_extra,
                [class*="gmail_"],
                [id*="gmail_"] {
                    display: none !important;
                }
                
                /* Hide email clients signatures */
                .moz-signature,
                .yahoo_quoted,
                .ms-outlook-signature {
                    display: none !important;
                }
                
                /* Responsive adjustments */
                @media (max-width: 600px) {
                    table {
                        font-size: 14px;
                    }
                    th, td {
                        padding: 4px 6px;
                    }
                }
                
                /* Selection */
                ::selection {
                    background-color: \(isFromMe ? "rgba(255,255,255,0.3)" : "rgba(0,122,255,0.2)");
                }
                
                /* Accessibility */
                @media (prefers-reduced-motion: reduce) {
                    * {
                        animation: none !important;
                        transition: none !important;
                    }
                }
            </style>
        </head>
        <body>
            \(html)
            <script type="text/javascript">
                // This won't run due to CSP, but kept for completeness
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightObserver) {
                    function reportHeight() {
                        var height = document.body.scrollHeight;
                        window.webkit.messageHandlers.heightObserver.postMessage(height);
                    }
                    window.onload = reportHeight;
                    
                    // Observe for dynamic content changes
                    if (window.MutationObserver) {
                        var observer = new MutationObserver(reportHeight);
                        observer.observe(document.body, { childList: true, subtree: true });
                    }
                }
            </script>
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: OptimizedHTMLMessageView
        private var hasReportedHeight = false
        
        init(_ parent: OptimizedHTMLMessageView) {
            self.parent = parent
            super.init()
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Use JavaScript evaluation as fallback if message handler doesn't work
            webView.evaluateJavaScript("document.readyState") { [weak self] (result, error) in
                if let readyState = result as? String, readyState == "complete" {
                    self?.calculateHeight(webView)
                }
            }
        }
        
        private func calculateHeight(_ webView: WKWebView) {
            guard !hasReportedHeight else { return }
            
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, error in
                guard let self = self else { return }
                
                if let height = result as? CGFloat {
                    self.hasReportedHeight = true
                    DispatchQueue.main.async {
                        // Animate height change
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.parent.contentHeight = height + 24 // Add padding
                        }
                    }
                }
            }
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
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightObserver", let height = message.body as? CGFloat {
                guard !hasReportedHeight else { return }
                hasReportedHeight = true
                
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.parent.contentHeight = height + 24
                    }
                }
            }
        }
    }
}