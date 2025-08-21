import SwiftUI

struct UnifiedRecipientsField: View {
    @Binding var toRecipients: [String]
    @Binding var ccRecipients: [String]?
    @Binding var bccRecipients: [String]?
    @FocusState.Binding var focusedField: RecipientFieldType?
    
    let configuration: Configuration
    @EnvironmentObject private var contactsService: ContactsService
    @State private var toInput = ""
    @State private var ccInput = ""
    @State private var bccInput = ""
    @State private var showCCBCC = false
    @State private var toSuggestions: [String] = []
    @State private var ccSuggestions: [String] = []
    @State private var bccSuggestions: [String] = []
    
    enum RecipientFieldType: Hashable {
        case to, cc, bcc
    }
    
    struct Configuration {
        let showCCBCC: Bool
        let autoFocus: Bool
        let placeholder: String
        
        static let simple = Configuration(
            showCCBCC: false,
            autoFocus: true,
            placeholder: "To"
        )
        
        static let full = Configuration(
            showCCBCC: true,
            autoFocus: false,
            placeholder: "Recipients"
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // To Field
            recipientField(
                label: "To:",
                input: $toInput,
                recipients: $toRecipients,
                suggestions: $toSuggestions,
                fieldType: .to
            )
            
            // CC/BCC Fields (if enabled)
            if configuration.showCCBCC && showCCBCC {
                Divider()
                if ccRecipients != nil {
                    recipientField(
                        label: "Cc:",
                        input: $ccInput,
                        recipients: Binding(
                            get: { ccRecipients ?? [] },
                            set: { ccRecipients = $0 }
                        ),
                        suggestions: $ccSuggestions,
                        fieldType: .cc
                    )
                }
                
                Divider()
                if bccRecipients != nil {
                    recipientField(
                        label: "Bcc:",
                        input: $bccInput,
                        recipients: Binding(
                            get: { bccRecipients ?? [] },
                            set: { bccRecipients = $0 }
                        ),
                        suggestions: $bccSuggestions,
                        fieldType: .bcc
                    )
                }
            }
            
            // Add CC/BCC button (if enabled and not showing)
            if configuration.showCCBCC && !showCCBCC {
                Button(action: { showCCBCC = true }) {
                    Text("Add Cc/Bcc")
                        .font(.footnote)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            if configuration.autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    focusedField = .to
                }
            }
        }
    }
    
    @ViewBuilder
    private func recipientField(
        label: String,
        input: Binding<String>,
        recipients: Binding<[String]>,
        suggestions: Binding<[String]>,
        fieldType: RecipientFieldType
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.gray)
                .frame(width: 35, alignment: .trailing)
                .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Recipient chips
                UnifiedFlowLayout(spacing: 4) {
                    ForEach(recipients.wrappedValue, id: \.self) { email in
                        UnifiedRecipientChip(
                            email: email,
                            onRemove: {
                                recipients.wrappedValue.removeAll { $0 == email }
                            }
                        )
                    }
                    
                    // Input field
                    TextField(configuration.placeholder, text: input)
                        .textFieldStyle(PlainTextFieldStyle())
                        .focused($focusedField, equals: fieldType)
                        .onSubmit {
                            addRecipient(input.wrappedValue, to: recipients, inputBinding: input)
                        }
                        .onChange(of: input.wrappedValue) { oldValue, newValue in
                            updateSuggestions(for: newValue, suggestions: suggestions)
                        }
                        .frame(minWidth: 100)
                }
                
                // Suggestions
                if !suggestions.wrappedValue.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions.wrappedValue, id: \.self) { suggestion in
                                Button(action: {
                                    addRecipient(suggestion, to: recipients, inputBinding: input)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.circle.fill")
                                            .font(.caption)
                                        Text(suggestion)
                                            .font(.footnote)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal)
    }
    
    private func addRecipient(_ email: String, to recipients: Binding<[String]>, inputBinding: Binding<String>) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty,
              !recipients.wrappedValue.contains(trimmedEmail) else { return }
        
        recipients.wrappedValue.append(trimmedEmail)
        inputBinding.wrappedValue = ""
    }
    
    private func updateSuggestions(for query: String, suggestions: Binding<[String]>) {
        guard !query.isEmpty else {
            suggestions.wrappedValue = []
            return
        }
        
        // Get suggestions from contacts service
        // For now, just return empty array as ContactsService doesn't have getSuggestions method
        suggestions.wrappedValue = []
    }
}

private struct UnifiedRecipientChip: View {
    let email: String
    let onRemove: () -> Void
    @EnvironmentObject private var contactsService: ContactsService
    
    var displayName: String {
        contactsService.getContactName(for: email) ?? email
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(displayName)
                .font(.footnote)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

private struct UnifiedFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangement(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(proposal: proposal, subviews: subviews)
        for (index, (subview, position)) in zip(subviews, result.positions).enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                         proposal: ProposedViewSize(result.sizes[index]))
        }
    }
    
    private struct ArrangementResult {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
    
    private func arrangement(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth - currentX, height: nil))
            sizes.append(size)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        return ArrangementResult(
            size: CGSize(width: maxWidth, height: currentY + lineHeight),
            positions: positions,
            sizes: sizes
        )
    }
    
}

