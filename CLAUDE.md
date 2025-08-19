# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESC is an iOS email app that provides an iMessage-style interface for Gmail conversations. The app groups emails by sender/recipient into threaded conversations, creating a chat-like experience with full Gmail API integration.

## Development Commands

### Building
```bash
# Build for iOS Simulator
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build

# Quick build check (last 5 lines only)
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build 2>&1 | tail -5

# Clean and rebuild
xcodebuild clean build -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# Clean build cache when encountering disk I/O errors
xcodebuild clean -project ESC.xcodeproj -scheme ESC
```

### Testing
```bash
# Run all tests
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# Run specific test
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:ESCTests/EmailTests/testEmailCreation
```

## Core Architecture

### MVVM + Dependency Injection Pattern
The app uses MVVM architecture with a centralized `DependencyContainer` for service management:
- **ViewModels** (`ConversationDetailViewModel`, `ConversationListViewModel`): Handle business logic
- **DependencyContainer**: Manages service instances and ViewModels creation
- **Protocol-based services**: Enable testing and dependency inversion

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

#### Account Switching & Data Cleanup
```swift
// When switching accounts, must clear:
// 1. All SwiftData entities (attachments first, then emails, then conversations)
// 2. ContactsService cache via clearCache()
// 3. GmailService cached user data
// 4. Force modelContext.processPendingChanges() before save
```

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
  - Must clear cached data on signOut()

- **DataSyncService** (@MainActor):
  - 10-second polling interval via startAutoSync()
  - Creates unique conversation keys for group chats
  - Merges duplicate conversations on startup
  - Must be stopped via stopAutoSync() before account switch

- **ContactsService** (Singleton):
  - `ContactsService.shared` singleton pattern
  - Caches contact photos in memory and disk
  - Must call clearCache() on account switch
  - Email lookups use lowercase normalization

### UI Architecture

#### Navigation Flow
- ConversationListView → ConversationDetailView (push navigation)
- Forward → ForwardComposeView (modal sheet)
- Reply → Inline in same conversation (no navigation)
- New conversation → Empty Conversation object → ConversationDetailView

#### Compose UI Changes
- **New Messages**: Use `SimpleRecipientsField` (To field only, no CC/BCC)
- **Replies**: Use `MultipleRecipientsField` (includes CC/BCC options)
- Auto-focus To field when composing (0.3s delay for animation)

#### Keyboard & Scrolling (ConversationDetailView)
- Uses `GeometryReader` wrapper for proper layout calculation
- `ScrollViewReader` with `defaultScrollAnchor(.bottom)` for chat-style scrolling
- Automatic iOS keyboard avoidance (no manual keyboard height tracking)
- Hidden scroll indicators for cleaner appearance
- 50-point bottom spacer for better scroll behavior

## Common Issues & Solutions

### CoreData Array Errors
**Problem**: "Could not materialize Objective-C class named Array"  
**Solution**: Use string storage with computed properties, mark arrays as `@Transient`

### Account Data Persistence
**Problem**: Old account data shows after switching accounts  
**Solution**: Clear all data in order: attachments → emails → conversations → contacts cache

### Keyboard Scrolling Issues
**Problem**: Flickering or jarring animations when keyboard appears  
**Solution**: 
- Use `defaultScrollAnchor(.bottom)` on ScrollView
- Avoid manual keyboard height tracking
- Remove conflicting scroll animations on focus changes

### Build Cache Errors
**Problem**: "disk I/O error" or "cannot open constant extraction protocol list"  
**Solution**: Run `xcodebuild clean -project ESC.xcodeproj -scheme ESC`

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
- New messages: To field only (no CC/BCC in UI)
- Replies: Support full To/CC/BCC
- Reply headers: `In-Reply-To` and `References`

### Sync Behavior
- Initial sync shows spinner only on first load
- Background sync every 10 seconds (silent)
- Empty inbox shows "No messages" (not spinner)
- Duplicate detection within 5-minute window

## Error Handling
- `AppError` enum provides comprehensive error types
- Categories: Authentication, Network, Gmail API, Data, Validation, UI
- Includes recovery suggestions and retry logic

## Requirements

- iOS 17.0+ (SwiftData requirement)
- Xcode 15.0+
- No external dependencies (pure Swift/SwiftUI)
- Gmail account for functionality