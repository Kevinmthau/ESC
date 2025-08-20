import Foundation
import WebKit

/// Manages a pool of reusable WKWebView instances for better performance
class WebViewPoolManager: NSObject, WebViewPoolProtocol {
    static let shared = WebViewPoolManager()
    
    private var availableWebViews: [WKWebView] = []
    private var inUseWebViews: Set<WKWebView> = []
    private let maxPoolSize = 5
    private let queue = DispatchQueue(label: "com.esc.webviewpool", attributes: .concurrent)
    
    // Cache for rendered HTML heights
    private var heightCache = NSCache<NSString, NSNumber>()
    
    private override init() {
        super.init()
        heightCache.countLimit = 100 // Cache up to 100 heights
    }
    
    // MARK: - Configuration
    
    private func createConfiguration(allowJavaScript: Bool = false) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        
        // Security settings - using modern API
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = allowJavaScript
        configuration.defaultWebpagePreferences = preferences
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.suppressesIncrementalRendering = true
        
        // Data detection
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        
        // Content Security Policy
        let contentSecurityPolicy = """
            default-src 'none';
            img-src https: data:;
            style-src 'unsafe-inline';
            base-uri 'none';
            form-action 'none';
            frame-ancestors 'none';
        """
        
        let script = """
            var meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "\(contentSecurityPolicy)";
            document.getElementsByTagName('head')[0].appendChild(meta);
        """
        
        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(userScript)
        
        return configuration
    }
    
    // MARK: - Pool Management
    
    /// Acquires a WebView from the pool or creates a new one
    func acquireWebView(allowJavaScript: Bool = false) -> WKWebView {
        return queue.sync(flags: .barrier) {
            // Try to get from pool
            if let webView = availableWebViews.popLast() {
                inUseWebViews.insert(webView)
                prepareForReuse(webView)
                return webView
            }
            
            // Create new WebView if pool is empty
            let configuration = createConfiguration(allowJavaScript: allowJavaScript)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            configureWebView(webView)
            inUseWebViews.insert(webView)
            return webView
        }
    }
    
    /// Returns a WebView to the pool for reuse
    func releaseWebView(_ webView: WKWebView) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.inUseWebViews.remove(webView)
            
            // Only add back to pool if under limit
            if self.availableWebViews.count < self.maxPoolSize {
                self.cleanWebView(webView)
                self.availableWebViews.append(webView)
            } else {
                // Dispose of excess WebViews
                webView.stopLoading()
                webView.configuration.userContentController.removeAllUserScripts()
            }
        }
    }
    
    private func configureWebView(_ webView: WKWebView) {
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }
    
    private func prepareForReuse(_ webView: WKWebView) {
        // Reset navigation delegate
        webView.navigationDelegate = nil
        
        // Clear any existing content
        webView.loadHTMLString("", baseURL: nil)
    }
    
    private func cleanWebView(_ webView: WKWebView) {
        // Stop any ongoing loads
        webView.stopLoading()
        
        // Clear the web view
        webView.loadHTMLString("", baseURL: nil)
        
        // Clear caches
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: Date(timeIntervalSince1970: 0),
            completionHandler: {}
        )
    }
    
    // MARK: - Height Caching
    
    /// Gets cached height for HTML content
    func getCachedHeight(for htmlHash: String) -> CGFloat? {
        if let value = heightCache.object(forKey: htmlHash as NSString)?.doubleValue {
            return CGFloat(value)
        }
        return nil
    }
    
    /// Caches height for HTML content
    func cacheHeight(_ height: CGFloat, for htmlHash: String) {
        heightCache.setObject(NSNumber(value: height), forKey: htmlHash as NSString)
    }
    
    /// Protocol conformance - alias for cacheHeight
    func setCachedHeight(_ height: CGFloat, for htmlHash: String) {
        cacheHeight(height, for: htmlHash)
    }
    
    /// Generates hash for HTML content
    func hashForHTML(_ html: String) -> String {
        let data = Data(html.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Memory Management
    
    /// Clears the pool and releases all WebViews
    func clearPool() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Clean and clear available WebViews
            for webView in self.availableWebViews {
                self.cleanWebView(webView)
            }
            self.availableWebViews.removeAll()
            
            // Clear height cache
            self.heightCache.removeAllObjects()
        }
    }
    
    /// Called when memory warning is received
    func handleMemoryWarning() {
        clearPool()
    }
}

// MARK: - C imports for SHA256
import CommonCrypto

// MARK: - WebView Height Calculator

extension WebViewPoolManager {
    
    /// Calculates the height of HTML content asynchronously
    func calculateHeight(
        for html: String,
        width: CGFloat,
        completion: @escaping (CGFloat) -> Void
    ) {
        // Check cache first
        let htmlHash = hashForHTML(html)
        if let cachedHeight = getCachedHeight(for: htmlHash) {
            completion(cachedHeight)
            return
        }
        
        // Calculate height using temporary WebView
        let webView = acquireWebView()
        let delegate = HeightCalculatorDelegate { [weak self] height in
            self?.cacheHeight(height, for: htmlHash)
            self?.releaseWebView(webView)
            completion(height)
        }
        
        webView.navigationDelegate = delegate
        
        // Load HTML with width constraint
        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=\(width), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 12px 16px;
                    width: \(width - 32)px;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                * { max-width: 100% !important; }
            </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }
}

// MARK: - Height Calculator Delegate

private class HeightCalculatorDelegate: NSObject, WKNavigationDelegate {
    private let completion: (CGFloat) -> Void
    
    init(completion: @escaping (CGFloat) -> Void) {
        self.completion = completion
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
            if let height = result as? CGFloat {
                self?.completion(height + 24) // Add padding
            } else {
                self?.completion(100) // Default height
            }
        }
    }
}