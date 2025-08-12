import SwiftUI
import WebKit

struct HTMLMessageView: UIViewRepresentable {
    let htmlContent: String
    let isFromMe: Bool
    @Binding var contentHeight: CGFloat
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        
        // Add script message handler for height updates
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "heightUpdate")
        configuration.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        // Load content immediately
        let styledHTML = wrapHTMLWithStyling(htmlContent)
        webView.loadHTMLString(styledHTML, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Don't reload to prevent flickering
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func wrapHTMLWithStyling(_ html: String) -> String {
        let textColor = isFromMe ? "white" : "black"
        let linkColor = isFromMe ? "#ADD8E6" : "#007AFF"
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 12px 16px;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 16px;
                    line-height: 1.4;
                    color: \(textColor);
                    background-color: transparent;
                    word-wrap: break-word;
                    -webkit-text-size-adjust: 100%;
                }
                
                /* Reset margins for common elements */
                p { margin: 0 0 8px 0; }
                p:last-child { margin-bottom: 0; }
                h1, h2, h3, h4, h5, h6 { margin: 12px 0 8px 0; }
                ul, ol { margin: 8px 0; padding-left: 20px; }
                
                /* Style links */
                a {
                    color: \(linkColor);
                    text-decoration: underline;
                }
                
                /* Style images to fit */
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                    margin: 8px 0;
                }
                
                /* Style tables */
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 8px 0;
                }
                
                th, td {
                    border: 1px solid \(isFromMe ? "rgba(255,255,255,0.3)" : "rgba(0,0,0,0.1)");
                    padding: 4px 8px;
                    text-align: left;
                }
                
                /* Style blockquotes */
                blockquote {
                    margin: 8px 0;
                    padding-left: 12px;
                    border-left: 3px solid \(isFromMe ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.3)");
                }
                
                /* Style code blocks */
                code {
                    background-color: \(isFromMe ? "rgba(0,0,0,0.2)" : "rgba(0,0,0,0.05)");
                    padding: 2px 4px;
                    border-radius: 3px;
                    font-family: 'SF Mono', Consolas, monospace;
                    font-size: 14px;
                }
                
                pre {
                    background-color: \(isFromMe ? "rgba(0,0,0,0.2)" : "rgba(0,0,0,0.05)");
                    padding: 8px;
                    border-radius: 4px;
                    overflow-x: auto;
                }
                
                pre code {
                    background-color: transparent;
                    padding: 0;
                }
                
                /* Hide signature blocks that Gmail might include */
                .gmail_signature { display: none; }
                .gmail_quote { display: none; }
            </style>
            <script>
                function updateHeight() {
                    const height = document.body.scrollHeight;
                    window.webkit.messageHandlers.heightUpdate.postMessage(height);
                }
                
                // Update height when content loads
                window.onload = updateHeight;
                
                // Also update on any image loads
                document.addEventListener('DOMContentLoaded', function() {
                    var images = document.getElementsByTagName('img');
                    for (var i = 0; i < images.length; i++) {
                        images[i].onload = updateHeight;
                    }
                });
            </script>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLMessageView
        
        init(_ parent: HTMLMessageView) {
            self.parent = parent
            super.init()
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Get the height of the content
            webView.evaluateJavaScript("document.body.scrollHeight") { result, error in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.contentHeight = height + 24 // Add padding
                    }
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightUpdate", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.parent.contentHeight = height + 24 // Add padding
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
    }
}

struct HTMLMessageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HTMLMessageView(
                htmlContent: "<p>Hello <b>World</b>!</p><p>This is a <a href='https://example.com'>link</a>.</p>",
                isFromMe: false,
                contentHeight: .constant(100)
            )
            .frame(height: 100)
            .background(Color.gray.opacity(0.2))
            
            HTMLMessageView(
                htmlContent: "<h3>Meeting Notes</h3><ul><li>First item</li><li>Second item</li></ul>",
                isFromMe: true,
                contentHeight: .constant(100)
            )
            .frame(height: 100)
            .background(Color.blue)
        }
    }
}