import Foundation
import WebKit
import UIKit
import SwiftUI
import QuickLook

// MARK: - Email PDF Service
@MainActor
class EmailPDFService: NSObject {
    static let shared = EmailPDFService()
    
    // Use actor isolation for thread-safe cache
    private let cacheManager = PDFCacheManager()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Renders an email to PDF, using cache if available
    func renderEmailToPDF(_ email: Email) async throws -> Data {
        // Check cache first
        if let cachedPDF = await cacheManager.getCachedPDF(for: email.id) {
            return cachedPDF
        }
        
        // Prepare HTML with sanitization and inline attachments
        let html = try await prepareHTMLForRendering(email)
        
        // Render to PDF
        let pdfData = try await renderHTMLToPDF(html: html)
        
        // Cache the result
        await cacheManager.cachePDF(pdfData, for: email.id)
        
        return pdfData
    }
    
    /// Creates a preview-ready PDF URL for QuickLook
    func createTemporaryPDFURL(for email: Email) async throws -> URL {
        let pdfData = try await renderEmailToPDF(email)
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "email_\(email.id.replacingOccurrences(of: "/", with: "_")).pdf"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        // Remove old file if exists
        try? FileManager.default.removeItem(at: fileURL)
        
        // Write new PDF
        try pdfData.write(to: fileURL)
        
        return fileURL
    }
    
    // MARK: - HTML Preparation
    
    private func prepareHTMLForRendering(_ email: Email) async throws -> String {
        // Check if we have any content at all
        let hasHTMLBody = email.htmlBody != nil && !email.htmlBody!.isEmpty
        let hasPlainBody = !email.body.isEmpty
        
        guard hasHTMLBody || hasPlainBody else {
            // No content at all - create a minimal message
            let minimalHTML = """
            <div style="padding: 20px;">
                <p style="color: #666;">This email has no content to display.</p>
                <hr style="margin: 20px 0; border: none; border-top: 1px solid #eee;">
                <p style="font-size: 12px; color: #999;">
                    From: \(email.sender)<br>
                    Date: \(email.timestamp)<br>
                    Subject: \(email.subject ?? "(no subject)")
                </p>
            </div>
            """
            return wrapWithEmailStyles(minimalHTML, subject: email.subject)
        }
        
        var html = email.htmlBody ?? convertPlainTextToHTML(email.body)
        
        // 1. Sanitize dangerous elements
        html = sanitizeHTML(html)
        
        // 2. Convert CID attachments to data URLs
        html = await inlineAttachments(html: html, attachments: email.attachments)
        
        // 3. Block tracking pixels and external images
        html = blockTrackingPixels(html)
        
        // 4. Add responsive meta tags and base styles
        html = wrapWithEmailStyles(html, subject: email.subject)
        
        return html
    }
    
    private func sanitizeHTML(_ html: String) -> String {
        var sanitized = html
        
        // Remove script tags
        sanitized = sanitized.replacingOccurrences(
            of: #"<script[^>]*>[\s\S]*?</script>"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove iframe tags
        sanitized = sanitized.replacingOccurrences(
            of: #"<iframe[^>]*>[\s\S]*?</iframe>"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove object/embed tags
        sanitized = sanitized.replacingOccurrences(
            of: #"<(object|embed)[^>]*>[\s\S]*?</(object|embed)>"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove on* event handlers
        sanitized = sanitized.replacingOccurrences(
            of: #"\s*on\w+\s*=\s*["'][^"']*["']"#,
            with: "",
            options: .regularExpression
        )
        
        // Remove javascript: URLs
        sanitized = sanitized.replacingOccurrences(
            of: #"javascript:"#,
            with: "",
            options: .caseInsensitive
        )
        
        return sanitized
    }
    
    private func inlineAttachments(html: String, attachments: [Attachment]) async -> String {
        var result = html
        
        for attachment in attachments {
            guard let data = attachment.data else { continue }
            
            // Look for CID references
            let cidPatterns = [
                "cid:\(attachment.id)",
                "cid:\(attachment.filename)",
                // Sometimes the CID is just the filename without extension
                "cid:\(attachment.filename.split(separator: ".").first ?? "")"
            ]
            
            // Convert to data URL
            let base64 = data.base64EncodedString()
            let dataURL = "data:\(attachment.mimeType);base64,\(base64)"
            
            for pattern in cidPatterns {
                result = result.replacingOccurrences(of: pattern, with: dataURL)
            }
        }
        
        return result
    }
    
    private func blockTrackingPixels(_ html: String) -> String {
        var result = html
        
        // Block 1x1 images (common tracking pixels)
        result = result.replacingOccurrences(
            of: #"<img[^>]*width\s*=\s*["']?1["']?[^>]*height\s*=\s*["']?1["']?[^>]*>"#,
            with: "<!-- tracking pixel removed -->",
            options: .regularExpression
        )
        
        // Block known tracking domains
        let trackingDomains = [
            "mailtrack.io",
            "emailtracker",
            "bananatag.com",
            "yesware.com",
            "streak.com",
            "getnotify.com",
            "saleshandy.com",
            "pixel.gif",
            "track.gif"
        ]
        
        for domain in trackingDomains {
            result = result.replacingOccurrences(
                of: #"<img[^>]*src=['""][^'"]*\#(domain)[^'"]*['""][^>]*>"#,
                with: "<!-- tracking image removed -->",
                options: .regularExpression
            )
        }
        
        // Replace external images with placeholder (optional - comment out if you want to show external images)
        // result = blockExternalImages(result)
        
        return result
    }
    
    private func blockExternalImages(_ html: String) -> String {
        // Replace external image URLs with a placeholder
        let placeholder = "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgZmlsbD0iI2VlZSIvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjUwIiB5PSI1MCIgZmlsbD0iIzk5OSIgZm9udC1zaXplPSIxNCI+SW1hZ2U8L3RleHQ+PC9zdmc+"
        
        var result = html
        
        // Find all img tags with http/https sources
        let pattern = #"(<img[^>]*src=["'])(https?://[^"']+)(["'][^>]*>)"#
        
        result = result.replacingOccurrences(
            of: pattern,
            with: "$1\(placeholder)$3",
            options: .regularExpression
        )
        
        return result
    }
    
    private func wrapWithEmailStyles(_ html: String, subject: String?) -> String {
        let title = subject ?? "Email"
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title)</title>
            <style>
                /* Reset and base styles */
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: #333;
                    background: white;
                    padding: 20px;
                    word-wrap: break-word;
                    -webkit-text-size-adjust: 100%;
                }
                
                /* Email-specific fixes */
                table {
                    border-collapse: collapse;
                    mso-table-lspace: 0pt;
                    mso-table-rspace: 0pt;
                }
                
                td {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                    border: 0;
                    outline: none;
                    text-decoration: none;
                }
                
                a {
                    color: #007AFF;
                    text-decoration: underline;
                }
                
                /* Responsive tables */
                @media only screen and (max-width: 600px) {
                    table[class="responsive-table"] {
                        width: 100% !important;
                    }
                    
                    td[class="responsive-cell"] {
                        display: block !important;
                        width: 100% !important;
                    }
                }
                
                /* Quote blocks */
                blockquote {
                    border-left: 3px solid #ccc;
                    margin: 10px 0;
                    padding-left: 10px;
                    color: #666;
                }
                
                /* Code blocks */
                pre, code {
                    background: #f4f4f4;
                    border-radius: 3px;
                    padding: 2px 4px;
                    font-family: 'SF Mono', Monaco, Consolas, 'Courier New', monospace;
                    font-size: 0.9em;
                }
                
                pre {
                    padding: 10px;
                    overflow-x: auto;
                }
                
                /* Gmail quote */
                .gmail_quote {
                    margin: 10px 0;
                    padding: 10px;
                    border-left: 2px solid #ccc;
                    color: #666;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
    
    private func convertPlainTextToHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
        
        // Convert URLs to links
        let urlPattern = #"(https?://[^\s]+)"#
        let linked = escaped.replacingOccurrences(
            of: urlPattern,
            with: "<a href=\"$1\">$1</a>",
            options: .regularExpression
        )
        
        // Convert newlines to <br>
        let formatted = linked.replacingOccurrences(of: "\n", with: "<br>\n")
        
        return "<div style=\"white-space: pre-wrap; word-wrap: break-word;\">\(formatted)</div>"
    }
    
    // MARK: - PDF Rendering
    
    private func renderHTMLToPDF(html: String) async throws -> Data {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                // Use UIMarkupTextPrintFormatter for more reliable PDF generation
                let printFormatter = UIMarkupTextPrintFormatter(markupText: html)
                let renderer = UIPrintPageRenderer()
                renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
                
                // US Letter size with margins
                let pageSize = CGSize(width: 612, height: 792) // 8.5 x 11 inches at 72 DPI
                let pageMargins = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36) // 0.5 inch margins
                
                let printableRect = CGRect(
                    x: pageMargins.left,
                    y: pageMargins.top,
                    width: pageSize.width - pageMargins.left - pageMargins.right,
                    height: pageSize.height - pageMargins.top - pageMargins.bottom
                )
                
                let paperRect = CGRect(origin: .zero, size: pageSize)
                
                renderer.setValue(paperRect, forKey: "paperRect")
                renderer.setValue(printableRect, forKey: "printableRect")
                
                // Create PDF data
                let pdfData = NSMutableData()
                UIGraphicsBeginPDFContextToData(pdfData, paperRect, nil)
                
                renderer.prepare(forDrawingPages: NSMakeRange(0, renderer.numberOfPages))
                
                for pageIndex in 0..<renderer.numberOfPages {
                    UIGraphicsBeginPDFPage()
                    renderer.drawPage(at: pageIndex, in: UIGraphicsGetPDFContextBounds())
                }
                
                UIGraphicsEndPDFContext()
                
                print("📄 PDF Generated: \(pdfData.length) bytes, \(renderer.numberOfPages) pages")
                continuation.resume(returning: pdfData as Data)
            }
        }
    }
    
    func clearCache() async {
        await cacheManager.clearCache()
    }
}


// MARK: - PDF Cache Manager
actor PDFCacheManager {
    private var pdfCache: [String: Data] = [:]
    
    func getCachedPDF(for messageId: String) -> Data? {
        return pdfCache[messageId]
    }
    
    func cachePDF(_ data: Data, for messageId: String) {
        pdfCache[messageId] = data
        
        // Limit cache size to 50 PDFs
        if pdfCache.count > 50 {
            // Remove oldest entries (simple FIFO for now)
            let keysToRemove = Array(pdfCache.keys.prefix(10))
            for key in keysToRemove {
                pdfCache.removeValue(forKey: key)
            }
        }
    }
    
    func clearCache() {
        pdfCache.removeAll()
    }
}

// MARK: - SwiftUI Preview Support
struct PDFPreviewView: UIViewControllerRepresentable {
    let pdfURL: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        uiViewController.reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(pdfURL: pdfURL)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let pdfURL: URL
        
        init(pdfURL: URL) {
            self.pdfURL = pdfURL
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return pdfURL as QLPreviewItem
        }
    }
}