import Foundation
import Contacts
import ContactsUI
import SwiftUI

class ContactsService: ObservableObject {
    private let contactStore = CNContactStore()
    @Published var contacts: [(name: String, email: String)] = []
    @Published var authorizationStatus: CNAuthorizationStatus
    private var contactPhotoCache: [String: UIImage] = [:]
    private var emailToContactMap: [String: CNContact] = [:]
    
    init() {
        self.authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            await MainActor.run {
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
                    
                    // Cache photo if available
                    if contact.imageDataAvailable {
                        if let imageData = contact.imageData ?? contact.thumbnailImageData,
                           let image = UIImage(data: imageData) {
                            tempPhotoCache[email.lowercased()] = image
                        }
                    }
                }
            }
            
            let sortedContacts = fetchedContacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            // Create copies for use in MainActor context
            let finalEmailMap = tempEmailToContactMap
            let finalPhotoCache = tempPhotoCache
            
            await MainActor.run {
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
    
    func getContactPhoto(for email: String) -> UIImage? {
        let normalizedEmail = email.lowercased()
        
        // Check cache first
        if let cachedPhoto = contactPhotoCache[normalizedEmail] {
            return cachedPhoto
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
        
        // Cache the photo
        contactPhotoCache[normalizedEmail] = image
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
}