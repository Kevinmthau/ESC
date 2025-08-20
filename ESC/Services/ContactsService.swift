import Foundation
import Contacts
import ContactsUI
import SwiftUI

class ContactsService: ObservableObject, ContactsServiceProtocol {
    static let shared = ContactsService()
    
    private let contactStore = CNContactStore()
    @Published var contacts: [(name: String, email: String)] = []
    @Published var authorizationStatus: CNAuthorizationStatus
    private var contactPhotoCache: [String: UIImage] = [:]
    private var emailToContactMap: [String: CNContact] = [:]
    private let photoCacheDirectory: URL
    private let photoCacheQueue = DispatchQueue(label: "com.esc.photocache", attributes: .concurrent)
    
    init() {
        self.authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        
        // Set up persistent cache directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.photoCacheDirectory = documentsPath.appendingPathComponent("ContactPhotoCache")
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: photoCacheDirectory, withIntermediateDirectories: true)
        
        // Load cached photos on initialization
        loadCachedPhotos()
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            // Defer the update to avoid publishing during view updates
            Task { @MainActor in
                self.authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
            return granted
        } catch {
            print("❌ ContactsService: Error requesting access: \(error)")
            return false
        }
    }
    
    func fetchContacts() async {
        guard authorizationStatus == .authorized else {
            print("❌ ContactsService: Not authorized to access contacts")
            return
        }
        
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey, CNContactImageDataKey, CNContactImageDataAvailableKey, CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        var fetchedContacts: [(name: String, email: String)] = []
        var tempEmailToContactMap: [String: CNContact] = [:]
        var tempPhotoCache: [String: UIImage] = [:]
        
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                let displayName = fullName.isEmpty ? "Unknown" : fullName
                
                for emailAddress in contact.emailAddresses {
                    let email = emailAddress.value as String
                    fetchedContacts.append((name: displayName, email: email))
                    
                    // Store the contact in the email mapping for photo lookup
                    tempEmailToContactMap[email.lowercased()] = contact
                    
                    // Cache photo if available and save to disk
                    if contact.imageDataAvailable {
                        if let imageData = contact.imageData ?? contact.thumbnailImageData,
                           let image = UIImage(data: imageData) {
                            let normalizedEmail = email.lowercased()
                            tempPhotoCache[normalizedEmail] = image
                            // Also save to disk for persistence
                            self.savePhotoToDisk(image, for: normalizedEmail)
                        }
                    }
                }
            }
            
            let sortedContacts = fetchedContacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            // Create copies for use in MainActor context
            let finalEmailMap = tempEmailToContactMap
            let finalPhotoCache = tempPhotoCache
            
            // Defer the update to the next run loop to avoid "Publishing changes from within view updates"
            Task { @MainActor in
                self.contacts = sortedContacts
                self.emailToContactMap = finalEmailMap
                self.contactPhotoCache = finalPhotoCache
                print("✅ ContactsService: Fetched \(self.contacts.count) contacts")
                print("📧 ContactsService: Email mapping has \(self.emailToContactMap.count) entries")
                print("🖼️ ContactsService: Cached \(self.contactPhotoCache.count) contact photos")
            }
            
        } catch {
            print("❌ ContactsService: Error fetching contacts: \(error)")
        }
    }
    
    func searchContacts(query: String) -> [(name: String, email: String)] {
        guard !query.isEmpty else { return Array(contacts.prefix(10)) }
        
        return contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(query) ||
            contact.email.localizedCaseInsensitiveContains(query)
        }
    }
    
    func getAllContacts() -> [(name: String, email: String)] {
        return contacts
    }
    
    // Protocol conformance method - returns Data
    func getContactPhoto(for email: String) async -> Data? {
        if let image = getContactPhotoImage(for: email) {
            return image.pngData()
        }
        return nil
    }
    
    // Original method for UIImage
    func getContactPhotoImage(for email: String) -> UIImage? {
        let normalizedEmail = email.lowercased()
        
        // Check memory cache first
        if let cachedPhoto = contactPhotoCache[normalizedEmail] {
            return cachedPhoto
        }
        
        // Check disk cache
        if let diskPhoto = loadPhotoFromDisk(for: normalizedEmail) {
            // Store in memory cache for faster access
            contactPhotoCache[normalizedEmail] = diskPhoto
            return diskPhoto
        }
        
        // Look up contact and get photo
        guard let contact = emailToContactMap[normalizedEmail] else {
            return nil
        }
        
        // Try to get image data (prefer full image over thumbnail)
        guard let imageData = contact.imageData ?? contact.thumbnailImageData,
              let image = UIImage(data: imageData) else {
            return nil
        }
        
        // Cache the photo in memory and disk
        contactPhotoCache[normalizedEmail] = image
        savePhotoToDisk(image, for: normalizedEmail)
        return image
    }
    
    func getContactName(for email: String) -> String? {
        let normalizedEmail = email.lowercased()
        guard let contact = emailToContactMap[normalizedEmail] else { 
            print("🔍 ContactsService: No contact found for email: \(email)")
            return nil 
        }
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        let result = fullName.isEmpty ? nil : fullName
        print("✅ ContactsService: Found name '\(result ?? "nil")' for email: \(email)")
        return result
    }
    
    // MARK: - Persistent Photo Caching
    
    private func loadCachedPhotos() {
        photoCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(at: self.photoCacheDirectory, includingPropertiesForKeys: nil)
                
                for fileURL in files where fileURL.pathExtension == "png" {
                    let email = fileURL.deletingPathExtension().lastPathComponent
                    if let imageData = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: imageData) {
                        DispatchQueue.main.async {
                            self.contactPhotoCache[email] = image
                        }
                    }
                }
                
                print("📷 ContactsService: Loaded \(files.count) cached photos from disk")
            } catch {
                print("❌ ContactsService: Error loading cached photos: \(error)")
            }
        }
    }
    
    private func savePhotoToDisk(_ image: UIImage, for email: String) {
        photoCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let fileURL = self.photoCacheDirectory.appendingPathComponent("\(email).png")
            
            if let data = image.pngData() {
                do {
                    try data.write(to: fileURL)
                    print("💾 ContactsService: Saved photo to disk for \(email)")
                } catch {
                    print("❌ ContactsService: Error saving photo to disk: \(error)")
                }
            }
        }
    }
    
    private func loadPhotoFromDisk(for email: String) -> UIImage? {
        let fileURL = photoCacheDirectory.appendingPathComponent("\(email).png")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return UIImage(data: data)
        } catch {
            print("❌ ContactsService: Error loading photo from disk: \(error)")
            return nil
        }
    }
    
    func clearPhotoCache() {
        photoCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Clear memory cache
            DispatchQueue.main.async {
                self.contactPhotoCache.removeAll()
            }
            
            // Clear disk cache
            do {
                let files = try FileManager.default.contentsOfDirectory(at: self.photoCacheDirectory, includingPropertiesForKeys: nil)
                for file in files {
                    try FileManager.default.removeItem(at: file)
                }
                print("🗑️ ContactsService: Cleared photo cache")
            } catch {
                print("❌ ContactsService: Error clearing photo cache: \(error)")
            }
        }
    }
    
    /// Clears all cached data when switching accounts
    func clearCache() {
        // Clear photo cache
        clearPhotoCache()
        
        // Clear contacts list
        DispatchQueue.main.async { [weak self] in
            self?.contacts.removeAll()
            self?.emailToContactMap.removeAll()
            print("🗑️ ContactsService: Cleared all cached contact data")
        }
    }
}