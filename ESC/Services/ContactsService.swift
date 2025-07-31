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
        
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey, CNContactImageDataKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        var fetchedContacts: [(name: String, email: String)] = []
        
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                let displayName = fullName.isEmpty ? "Unknown" : fullName
                
                for emailAddress in contact.emailAddresses {
                    let email = emailAddress.value as String
                    fetchedContacts.append((name: displayName, email: email))
                    
                    // Store the contact in the email mapping for photo lookup
                    emailToContactMap[email] = contact
                }
            }
            
            let sortedContacts = fetchedContacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            await MainActor.run {
                self.contacts = sortedContacts
                print("✅ ContactsService: Fetched \(self.contacts.count) contacts")
                print("📧 ContactsService: Email mapping has \(self.emailToContactMap.count) entries")
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
        // Check cache first
        if let cachedPhoto = contactPhotoCache[email] {
            return cachedPhoto
        }
        
        // Look up contact and get photo
        guard let contact = emailToContactMap[email],
              let imageData = contact.imageData,
              let image = UIImage(data: imageData) else {
            return nil
        }
        
        // Cache the photo
        contactPhotoCache[email] = image
        return image
    }
    
    func getContactName(for email: String) -> String? {
        guard let contact = emailToContactMap[email] else { 
            print("🔍 ContactsService: No contact found for email: \(email)")
            return nil 
        }
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        let result = fullName.isEmpty ? nil : fullName
        print("✅ ContactsService: Found name '\(result ?? "nil")' for email: \(email)")
        return result
    }
}