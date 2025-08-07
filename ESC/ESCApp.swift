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
        }
        .modelContainer(sharedModelContainer)
    }
}
