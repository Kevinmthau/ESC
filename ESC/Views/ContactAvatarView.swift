import SwiftUI

struct ContactAvatarView: View {
    let email: String
    let name: String
    let size: CGFloat
    
    @EnvironmentObject private var contactsService: ContactsService
    @State private var contactPhoto: UIImage?
    
    var body: some View {
        Group {
            if let photo = contactPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(name.prefix(1).uppercased())
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
        }
        .onAppear {
            loadContactPhoto()
        }
        .onChange(of: contactsService.contacts.count) { _, _ in
            loadContactPhoto()
        }
    }
    
    private func loadContactPhoto() {
        contactPhoto = contactsService.getContactPhotoImage(for: email)
    }
}

#Preview {
    ContactAvatarView(
        email: "test@example.com",
        name: "Test User",
        size: 50
    )
    .environmentObject(ContactsService.shared)
}