//
//  ContentView.swift
//  ESC
//
//  Created by Kevin Thau on 7/21/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        ConversationListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Conversation.self, Email.self], inMemory: true)
}
