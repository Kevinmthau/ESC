import Foundation
import SwiftUI
import CommonCrypto
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Date Utilities
struct DateUtilities {
    
    static func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    static func formatMessageTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return DateFormatters.displayTime.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        } else {
            return DateFormatters.displayDate.string(from: date)
        }
    }
    
    static func isRecent(_ date: Date, within minutes: Int = 5) -> Bool {
        let interval = Date().timeIntervalSince(date)
        return interval < Double(minutes * 60)
    }
    
    static func groupByDate<T>(_ items: [T], dateKeyPath: KeyPath<T, Date>) -> [(date: Date, items: [T])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item[keyPath: dateKeyPath])
        }
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, items: $0.value) }
    }
}

// MARK: - String Utilities
struct StringUtilities {
    
    static func cleanEmailAddress(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    static func extractName(from email: String) -> String {
        // Try to extract name from "Name <email@example.com>" format
        if let range = email.range(of: "<.*>", options: .regularExpression) {
            let name = email[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }
        
        // Extract username from email
        let components = email.split(separator: "@")
        if let username = components.first {
            return String(username)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        
        return email
    }
    
    static func truncate(_ string: String, maxLength: Int, suffix: String = "...") -> String {
        if string.count <= maxLength {
            return string
        }
        let index = string.index(string.startIndex, offsetBy: maxLength - suffix.count)
        return String(string[..<index]) + suffix
    }
    
    static func removeHTMLTags(from string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
    
    static func isBlank(_ string: String?) -> Bool {
        guard let string = string else { return true }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Collection Utilities
extension Collection {
    
    var isNotEmpty: Bool {
        !isEmpty
    }
    
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
    
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self.dropFirst($0).prefix(size))
        }
    }
}

// MARK: - Number Utilities
struct NumberUtilities {
    
    static func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    static func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
    
    static func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }
}

// MARK: - Device Utilities
struct DeviceUtilities {
    
    static var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    static var isIPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
    
    static var hasNotch: Bool {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return false }
        return window.safeAreaInsets.top > 20
        #else
        return false
        #endif
    }
    
    static var screenWidth: CGFloat {
        #if os(iOS)
        return UIScreen.main.bounds.width
        #else
        return 0
        #endif
    }
    
    static var screenHeight: CGFloat {
        #if os(iOS)
        return UIScreen.main.bounds.height
        #else
        return 0
        #endif
    }
}

// MARK: - Thread Utilities
struct ThreadUtilities {
    
    static func onMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
    
    static func onBackgroundThread(_ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async {
            block()
        }
    }
    
    static func delay(_ seconds: Double, block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            block()
        }
    }
}

// MARK: - Crypto Utilities
struct CryptoUtilities {
    
    static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }
}

// MARK: - User Defaults Utilities
@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    let userDefaults: UserDefaults
    
    init(_ key: String, defaultValue: T, userDefaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.userDefaults = userDefaults
    }
    
    var wrappedValue: T {
        get { userDefaults.object(forKey: key) as? T ?? defaultValue }
        set { userDefaults.set(newValue, forKey: key) }
    }
}

// MARK: - Keychain Utilities
struct KeychainUtilities {
    
    static func save(_ data: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == noErr
    }
    
    static func load(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == noErr else { return nil }
        return item as? Data
    }
    
    static func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        return SecItemDelete(query as CFDictionary) == noErr
    }
}