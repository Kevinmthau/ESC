import SwiftUI

struct ContactAvatarView: View {
    let email: String
    let name: String
    let contactsService: ContactsService
    let size: CGFloat
    
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
        contactPhoto = contactsService.getContactPhoto(for: email)
    }
}

#Preview {
    ContactAvatarView(
        email: "test@example.com",
        name: "Test User",
        contactsService: ContactsService(),
        size: 50
    )
}