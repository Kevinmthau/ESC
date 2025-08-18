# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESC is an iOS email app that provides an iMessage-style interface for Gmail conversations. The app groups emails by sender/recipient into threaded conversations, creating a chat-like experience with full Gmail API integration. Key features include group conversations, reply threading, and real-time sync.

## Development Commands

### Building
```bash
# Build for iOS Simulator
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build

# Quick build check (last 5 lines only)
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build 2>&1 | tail -5

# Clean and rebuild
xcodebuild clean build -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
```

### Testing
```bash
# Run all tests
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# Run specific test
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:ESCTests/EmailTests/testEmailCreation
```

## Core Architecture

### Data Models (SwiftData)
- **Email**: Core model with critical fields:
  - `id`: Gmail's unique message ID
  - `messageId`: RFC2822 Message-ID for reply threading
  - `inReplyToMessageId`: Links replies to original messages
  - Arrays stored as comma-separated strings (e.g., `toRecipientsString`) with computed properties for array access
  - `@Transient` properties excluded from persistence
  
- **Conversation**: Groups related emails:
  - `contactEmail`: Single email or comma-separated list for groups
  - `participantEmails`: Array of participants (excluding self)
  - `isGroupConversation`: Flag for group vs single conversations
  - Group conversations identified by sorted participant list

- **Attachment**: Binary data with MIME type support

### Critical Patterns

#### Group Conversation Management
```swift
// Creating conversation key for groups (DataSyncService)
let participants = Set(email.allRecipients + [email.senderEmail])
participants.remove(userEmail.lowercased())  // Exclude self
let conversationKey = participants.sorted().joined(separator: ",")
```

#### SwiftData Array Storage
```swift
// Arrays must be stored as strings to avoid CoreData errors
var toRecipientsString: String = ""
@Transient var toRecipients: [String] {
    get { toRecipientsString.isEmpty ? [] : toRecipientsString.split(separator: ",").map { String($0) } }
    set { toRecipientsString = newValue.joined(separator: ",") }
}
```

#### Reply Threading
```swift
// Must check both messageId and id for compatibility
let original = allEmails.first { $0.messageId == replyToId } ?? 
              allEmails.first { $0.id == replyToId }
```

### Service Layer

- **GmailService**: 
  - Manages OAuth authentication state
  - `cachedUserEmail` accessible for filtering self from participants
  - Supports multiple recipients with To/CC/BCC arrays

- **DataSyncService**:
  - 10-second polling interval
  - Creates unique conversation keys for group chats
  - Excludes user's email from participant lists
  - Merges duplicate conversations on startup

- **ContactsService**:
  - Singleton pattern with `ContactsService.shared`
  - Caches contact photos in memory and disk
  - Email lookups use lowercase normalization

### UI Architecture

#### Navigation Flow
- ConversationListView → ConversationDetailView (push navigation)
- Forward → ForwardComposeView (modal sheet)
- Reply → Inline in same conversation (no navigation)
- New conversation → Empty Conversation object → ConversationDetailView

#### Group Conversation UI
- MessageBubbleView accepts `isGroupConversation` flag
- Sender names appear below message bubbles with timestamp
- Group icon (`person.2.fill`) in conversation list
- Multiple recipients handled via `MultipleRecipientsField` component

## Common Issues & Solutions

### CoreData Array Errors
**Problem**: "Could not materialize Objective-C class named Array"
**Solution**: Use string storage with computed properties, mark arrays as `@Transient`

### NaN Errors in UI
**Problem**: CoreGraphics NaN errors in console
**Solution**: 
- Avoid `.frame(maxWidth: .infinity, maxHeight: .infinity)`
- Use explicit frame constraints or `fixedSize`
- Add `idealWidth` to TextFields

### Group Reply Invalid Email
**Problem**: Trying to send to comma-separated email string
**Solution**: Parse `conversation.participantEmails` array for individual addresses

### Duplicate Messages
**Problem**: Local and synced messages appear twice
**Solution**: 5-minute window duplicate detection in DataSyncService

## Gmail API Integration

### Authentication
- Scopes: `gmail.modify`, `gmail.send`, `userinfo.profile`
- Token refresh handled automatically by GoogleAuthManager
- Credentials in `GoogleService-Info.plist`

### Message Construction
- EmailMessageBuilder handles RFC2822 format
- Multiple recipients supported via arrays
- Reply headers: `In-Reply-To` and `References`
- From field: "Display Name <email@gmail.com>"

### Sync Behavior
- Initial sync shows spinner only on first load
- Background sync every 10 seconds (silent)
- Empty inbox shows "No messages" (not spinner)
- Duplicate detection within 5-minute window

## Project Structure

- `ESC/Models/`: SwiftData models with persistence logic
- `ESC/Views/`: Main views and navigation
- `ESC/Views/Components/`: Reusable UI components
- `ESC/Services/`: API clients and data sync
- `ESC/Utils/`: Message cleaning, formatting, validation

## Requirements

- iOS 17.0+ (SwiftData requirement)
- Xcode 15.0+
- No external dependencies (pure Swift/SwiftUI)
- Gmail account for functionality