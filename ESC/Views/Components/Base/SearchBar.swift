import SwiftUI

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    let placeholder: String
    let onSearchButtonClicked: (() -> Void)?
    let onCancelButtonClicked: (() -> Void)?
    
    @State private var isEditing = false
    
    init(text: Binding<String>,
         placeholder: String = "Search",
         onSearchButtonClicked: (() -> Void)? = nil,
         onCancelButtonClicked: (() -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onSearchButtonClicked = onSearchButtonClicked
        self.onCancelButtonClicked = onCancelButtonClicked
    }
    
    var body: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField(placeholder, text: $text, onCommit: {
                    onSearchButtonClicked?()
                })
                .focused($isFocused)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: text) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing = !newValue.isEmpty
                    }
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing = true
                        isFocused = true
                    }
                }
                
                if isEditing {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            text = ""
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            if isEditing {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        text = ""
                        isEditing = false
                        isFocused = false
                        onCancelButtonClicked?()
                    }
                }) {
                    Text("Cancel")
                        .foregroundColor(.accentColor)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}

// MARK: - Search Suggestions View
struct SearchSuggestionsView: View {
    let suggestions: [String]
    let onSuggestionTapped: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button(action: {
                    onSuggestionTapped(suggestion)
                }) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text(suggestion)
                            .foregroundColor(.primary)
                            .font(.subheadline)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                }
                
                Divider()
                    .padding(.leading)
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

// MARK: - Searchable Modifier
struct SearchableModifier: ViewModifier {
    @Binding var searchText: String
    let placeholder: String
    let showSuggestions: Bool
    let suggestions: [String]
    let onSuggestionTapped: ((String) -> Void)?
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: placeholder)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            ZStack(alignment: .top) {
                content
                
                if showSuggestions && !suggestions.isEmpty && searchText.isEmpty {
                    SearchSuggestionsView(
                        suggestions: suggestions,
                        onSuggestionTapped: { suggestion in
                            searchText = suggestion
                            onSuggestionTapped?(suggestion)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .zIndex(1)
                }
            }
        }
    }
}

// MARK: - View Extension
extension View {
    func searchable(text: Binding<String>,
                   placeholder: String = "Search",
                   showSuggestions: Bool = false,
                   suggestions: [String] = [],
                   onSuggestionTapped: ((String) -> Void)? = nil) -> some View {
        self.modifier(SearchableModifier(
            searchText: text,
            placeholder: placeholder,
            showSuggestions: showSuggestions,
            suggestions: suggestions,
            onSuggestionTapped: onSuggestionTapped
        ))
    }
}