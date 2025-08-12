//
//  ESCApp.swift
//  ESC
//
//  Created by Kevin Thau on 7/21/25.
//

import SwiftUI
import SwiftData

@main
struct ESCApp: App {
    @StateObject private var contactsService = ContactsService.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Email.self,
            Conversation.self,
            Attachment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(contactsService)
        }
        .modelContainer(sharedModelContainer)
    }
}
