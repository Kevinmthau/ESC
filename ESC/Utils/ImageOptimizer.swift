import UIKit
import CoreGraphics

/// Utilities for optimizing images in emails
class ImageOptimizer {
    
    static let shared = ImageOptimizer()
    
    private let imageCache = NSCache<NSString, UIImage>()
    
    private init() {
        imageCache.countLimit = 50
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }
    
    // MARK: - Image Optimization
    
    /// Optimizes an image for display in email
    /// - Parameters:
    ///   - image: Original image
    ///   - maxWidth: Maximum width for the image
    ///   - compressionQuality: JPEG compression quality (0.0 to 1.0)
    /// - Returns: Optimized image data
    func optimizeImage(
        _ image: UIImage,
        maxWidth: CGFloat = 600,
        compressionQuality: CGFloat = 0.8
    ) -> Data? {
        // Check if image needs resizing
        if image.size.width <= maxWidth {
            // Just compress if already small enough
            return image.jpegData(compressionQuality: compressionQuality)
        }
        
        // Calculate new size maintaining aspect ratio
        let scale = maxWidth / image.size.width
        let newHeight = image.size.height * scale
        let newSize = CGSize(width: maxWidth, height: newHeight)
        
        // Resize image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Compress and return
        return resizedImage?.jpegData(compressionQuality: compressionQuality)
    }
    
    /// Creates a thumbnail for an image
    /// - Parameters:
    ///   - image: Original image
    ///   - size: Thumbnail size
    /// - Returns: Thumbnail image
    func createThumbnail(
        from image: UIImage,
        size: CGSize = CGSize(width: 150, height: 150)
    ) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    /// Loads and optimizes image from data
    /// - Parameters:
    ///   - data: Image data
    ///   - cacheKey: Key for caching
    /// - Returns: Optimized UIImage
    func loadOptimizedImage(from data: Data, cacheKey: String? = nil) -> UIImage? {
        // Check cache first
        if let key = cacheKey, let cachedImage = imageCache.object(forKey: key as NSString) {
            return cachedImage
        }
        
        guard let image = UIImage(data: data) else { return nil }
        
        // Check if image is too large
        let maxDimension: CGFloat = 2000
        if image.size.width > maxDimension || image.size.height > maxDimension {
            // Resize if too large
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            // Cache and return
            if let key = cacheKey, let resized = resizedImage {
                imageCache.setObject(resized, forKey: key as NSString, cost: Int(newSize.width * newSize.height * 4))
            }
            
            return resizedImage
        }
        
        // Cache original if not too large
        if let key = cacheKey {
            let cost = Int(image.size.width * image.size.height * 4)
            imageCache.setObject(image, forKey: key as NSString, cost: cost)
        }
        
        return image
    }
    
    /// Processes HTML to optimize embedded images
    /// - Parameter html: HTML content
    /// - Returns: HTML with optimized image references
    func optimizeImagesInHTML(_ html: String) -> String {
        var optimizedHTML = html
        
        // Find all img tags
        let imgPattern = "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return html
        }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: html),
                  Range(match.range(at: 1), in: html) != nil else {
                continue
            }
            
            let imgTag = String(html[fullRange])
            
            // Add lazy loading attribute
            var optimizedTag = imgTag
            if !optimizedTag.contains("loading=") {
                optimizedTag = optimizedTag.replacingOccurrences(
                    of: "<img",
                    with: "<img loading=\"lazy\""
                )
            }
            
            // Add responsive sizing
            if !optimizedTag.contains("style=") {
                optimizedTag = optimizedTag.replacingOccurrences(
                    of: "<img",
                    with: "<img style=\"max-width:100%;height:auto;\""
                )
            }
            
            // Add decoding async for better performance
            if !optimizedTag.contains("decoding=") {
                optimizedTag = optimizedTag.replacingOccurrences(
                    of: "<img",
                    with: "<img decoding=\"async\""
                )
            }
            
            optimizedHTML.replaceSubrange(fullRange, with: optimizedTag)
        }
        
        return optimizedHTML
    }
    
    /// Extracts and processes images from HTML for pre-caching
    /// - Parameter html: HTML content
    /// - Returns: Array of image URLs found in HTML
    func extractImageURLs(from html: String) -> [String] {
        var urls: [String] = []
        
        let imgPattern = "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return urls
        }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        for match in matches {
            if let srcRange = Range(match.range(at: 1), in: html) {
                let src = String(html[srcRange])
                if !src.isEmpty && !urls.contains(src) {
                    urls.append(src)
                }
            }
        }
        
        return urls
    }
    
    /// Clears the image cache
    func clearCache() {
        imageCache.removeAllObjects()
    }
    
    /// Handles memory warning by clearing cache
    func handleMemoryWarning() {
        clearCache()
    }
}

// MARK: - HTML Image Processing Extensions

extension ImageOptimizer {
    
    /// Converts large images in HTML to placeholders with lazy loading
    /// - Parameters:
    ///   - html: Original HTML
    ///   - placeholderColor: Color for placeholder
    /// - Returns: HTML with image placeholders
    func addImagePlaceholders(to html: String, placeholderColor: UIColor = .systemGray5) -> String {
        var processedHTML = html
        
        let imgPattern = "<img[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return html
        }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        for match in matches.reversed() {
            guard let range = Range(match.range, in: html) else { continue }
            let imgTag = String(html[range])
            
            // Extract dimensions if available
            var width = "100%"
            var height = "200"
            
            if let widthMatch = imgTag.range(of: "width\\s*=\\s*[\"']?([0-9]+)", options: .regularExpression) {
                width = String(imgTag[widthMatch])
                    .replacingOccurrences(of: "width=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            
            if let heightMatch = imgTag.range(of: "height\\s*=\\s*[\"']?([0-9]+)", options: .regularExpression) {
                height = String(imgTag[heightMatch])
                    .replacingOccurrences(of: "height=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            
            // Create placeholder div
            let placeholder = """
            <div style="width:\(width);height:\(height)px;background-color:#f0f0f0;display:flex;align-items:center;justify-content:center;border-radius:8px;">
                <span style="color:#999;font-size:14px;">Loading image...</span>
            </div>
            \(imgTag)
            """
            
            processedHTML.replaceSubrange(range, with: placeholder)
        }
        
        return processedHTML
    }
}