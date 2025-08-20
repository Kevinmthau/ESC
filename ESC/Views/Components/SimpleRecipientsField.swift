import SwiftUI

/// Simplified recipients field for new messages - only shows To field
struct SimpleRecipientsField: View {
    @Binding var recipients: [String]
    @State private var currentInput = ""
    @FocusState var isFieldFocused: Bool
    @EnvironmentObject private var contactsService: ContactsService
    @State private var filteredContacts: [(name: String, email: String)] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // To field
            HStack(alignment: .top, spacing: 12) {
                Text("To:")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .trailing)
                    .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Recipient chips
                    if !recipients.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(recipients, id: \.self) { email in
                                RecipientChip(
                                    email: email,
                                    name: contactsService.getContactName(for: email),
                                    onRemove: {
                                        recipients.removeAll { $0 == email }
                                    }
                                )
                            }
                        }
                    }
                    
                    // Input field
                    TextField("Add recipient", text: $currentInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 15))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isFieldFocused)
                        .onSubmit {
                            addRecipient()
                        }
                        .onChange(of: currentInput) { _, newValue in
                            updateFilteredContacts(query: newValue)
                        }
                }
                .padding(.vertical, 8)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                isFieldFocused = true
            }
            
            // Contact suggestions
            if isFieldFocused && !filteredContacts.isEmpty {
                Divider()
                contactSuggestions
                    .frame(maxHeight: 200)
            }
        }
    }
    
    private var contactSuggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredContacts, id: \.email) { contact in
                    Button(action: {
                        recipients.append(contact.email)
                        currentInput = ""
                        updateFilteredContacts(query: "")
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Text(contact.email)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if contact.email != filteredContacts.last?.email {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    private func addRecipient() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Check if it's a valid email
        if EmailValidator.isValid(trimmed) {
            recipients.append(trimmed)
            currentInput = ""
            updateFilteredContacts(query: "")
        }
    }
    
    private func updateFilteredContacts(query: String) {
        guard !query.isEmpty else {
            filteredContacts = []
            return
        }
        
        let lowercaseQuery = query.lowercased()
        
        // Get all contacts
        let allContacts = contactsService.contacts
        
        // Filter contacts
        filteredContacts = allContacts.filter { contact in
            // Don't show already added recipients
            !recipients.contains(contact.email) &&
            (contact.name.lowercased().contains(lowercaseQuery) ||
             contact.email.lowercased().contains(lowercaseQuery))
        }.prefix(5).map { $0 }
    }
}

// Flow layout for recipient chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y), proposal: ProposedViewSize(frame.size))
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var height: CGFloat = 0
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            
            height = y + rowHeight
        }
    }
}