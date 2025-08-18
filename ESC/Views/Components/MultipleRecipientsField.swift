import SwiftUI

struct RecipientChip: View {
    let email: String
    let name: String?
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(name ?? email)
                .font(.footnote)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue)
        .cornerRadius(12)
    }
}

struct MultipleRecipientsField: View {
    @Binding var recipients: [String]
    @Binding var ccRecipients: [String]
    @Binding var bccRecipients: [String]
    @State private var currentInput = ""
    @State private var selectedField: RecipientFieldType = .to
    @State private var showCCBCC = false
    @FocusState private var isFieldFocused: Bool
    @EnvironmentObject private var contactsService: ContactsService
    @State private var filteredContacts: [(name: String, email: String)] = []
    
    enum RecipientFieldType {
        case to, cc, bcc
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // To field
            recipientRow(
                label: "To:",
                recipients: $recipients,
                fieldType: .to
            )
            
            // CC/BCC toggle
            if !showCCBCC && ccRecipients.isEmpty && bccRecipients.isEmpty {
                HStack {
                    Spacer()
                    Button("Add CC/BCC") {
                        showCCBCC = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            
            // CC field
            if showCCBCC || !ccRecipients.isEmpty {
                Divider()
                recipientRow(
                    label: "CC:",
                    recipients: $ccRecipients,
                    fieldType: .cc
                )
            }
            
            // BCC field
            if showCCBCC || !bccRecipients.isEmpty {
                Divider()
                recipientRow(
                    label: "BCC:",
                    recipients: $bccRecipients,
                    fieldType: .bcc
                )
            }
            
            // Contact suggestions
            if isFieldFocused && !filteredContacts.isEmpty {
                contactSuggestions
                    .frame(maxHeight: 200)  // Limit height to prevent unbounded growth
            }
        }
        .fixedSize(horizontal: false, vertical: true)  // Allow proper vertical sizing
    }
    
    private func recipientRow(label: String, recipients: Binding<[String]>, fieldType: RecipientFieldType) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 35, alignment: .leading)
                .padding(.top, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Show recipient chips
                    ForEach(recipients.wrappedValue, id: \.self) { recipient in
                        RecipientChip(
                            email: recipient,
                            name: contactsService.getContactName(for: recipient),
                            onRemove: {
                                recipients.wrappedValue.removeAll { $0 == recipient }
                            }
                        )
                    }
                    
                    // Input field
                    if selectedField == fieldType {
                        TextField("Email address", text: $currentInput, onCommit: {
                            addRecipient(to: recipients, input: currentInput)
                        })
                        .textFieldStyle(PlainTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minWidth: 150, idealWidth: 200, maxWidth: 300)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($isFieldFocused)
                        .onChange(of: currentInput) { _, _ in
                            updateFilteredContacts()
                        }
                    } else {
                        Button(action: {
                            selectedField = fieldType
                            isFieldFocused = true
                        }) {
                            if recipients.wrappedValue.isEmpty {
                                Text("Add recipient")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                    .frame(minWidth: 100)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: 40)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 40)  // Ensure minimum height
        .contentShape(Rectangle())
        .onTapGesture {
            selectedField = fieldType
            isFieldFocused = true
        }
    }
    
    private var contactSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(filteredContacts.prefix(5), id: \.email) { contact in
                Button(action: {
                    switch selectedField {
                    case .to:
                        addRecipient(to: $recipients, input: contact.email)
                    case .cc:
                        addRecipient(to: $ccRecipients, input: contact.email)
                    case .bcc:
                        addRecipient(to: $bccRecipients, input: contact.email)
                    }
                }) {
                    HStack {
                        ContactAvatarView(
                            email: contact.email,
                            name: contact.name,
                            size: 32
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(contact.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                if contact.email != filteredContacts.prefix(5).last?.email {
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func addRecipient(to recipients: Binding<[String]>, input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if EmailValidator.isValid(trimmedInput) && !recipients.wrappedValue.contains(trimmedInput) {
            recipients.wrappedValue.append(trimmedInput)
            currentInput = ""
        }
    }
    
    private func updateFilteredContacts() {
        if currentInput.isEmpty {
            filteredContacts = []
        } else {
            let searchText = currentInput.lowercased()
            filteredContacts = contactsService.getAllContacts()
                .filter { contact in
                    contact.name.lowercased().contains(searchText) ||
                    contact.email.lowercased().contains(searchText)
                }
                .filter { contact in
                    // Exclude already added recipients
                    !recipients.contains(contact.email.lowercased()) &&
                    !ccRecipients.contains(contact.email.lowercased()) &&
                    !bccRecipients.contains(contact.email.lowercased())
                }
                .sorted { $0.name < $1.name }
        }
    }
}