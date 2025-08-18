# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESC is an iOS email app that provides an iMessage-style interface for Gmail conversations. The app groups emails by sender/recipient into threaded conversations and ignores email subjects, creating a chat-like experience with full Gmail API integration for reading and sending emails.

## Development Commands

### Building
```bash
# Build for iOS Simulator
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build

# Quick build check (last 5 lines only)
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build 2>&1 | tail -5

# Build for device (requires proper provisioning)
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS,name=iPhone' build

# Clean build folder
xcodebuild clean -project ESC.xcodeproj -scheme ESC

# Clean and build
xcodebuild clean build -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
```

### Testing
```bash
# Run all tests
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# Run unit tests only
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:ESCTests

# Run UI tests only
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:ESCUITests

# Run a specific test
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:ESCTests/EmailTests/testEmailCreation
```

## Core Architecture

### Data Layer (SwiftData)
- **Email**: Core model with `id` (Gmail ID) and `messageId` (RFC2822 Message-ID for reply threading). Includes `inReplyToMessageId` for tracking replies. Email addresses normalized to lowercase.
- **Conversation**: Groups emails by contact email (case-insensitive). Maintains `lastMessageTimestamp` and `lastMessageSnippet` for list display.
- **Attachment**: Binary data storage with MIME type, supports inline images and document previews.

### Critical ID Management
- **Email.id**: Gmail's unique message ID (e.g., "1932e5a9b4c7f8d2")
- **Email.messageId**: RFC2822 Message-ID for threading (e.g., "1932e5a9b4c7f8d2@mail.gmail.com")
- **Reply matching**: Checks both `messageId` and `id` fields to find original messages
- **Local messages**: Use UUID strings for both `id` and `messageId` until synced

### UI Navigation Architecture
- **NavigationStack**: iOS 16+ programmatic navigation with NavigationPath
- **Compose Flow**: ConversationListView creates empty Conversation → navigates to ConversationDetailView
- **New Messages**: Composed in ConversationDetailView (NOT ComposeView which is deprecated)
- **Reply Flow**: Inline preview in same conversation, no navigation
- **Forward Flow**: Modal sheet (ForwardComposeView)

### Service Layer State Management
- **GmailService**: Singleton with `@Published var isAuthenticated`
- **DataSyncService**: 10-second polling timer, manages `isSyncing` state
- **ContactsService**: Caches photos in memory, lowercase email keys for lookups
- **GoogleAuthManager**: Token refresh handling with automatic retry

## Key Implementation Patterns

### Message ID Resolution
```swift
// Finding original message for replies - MUST check both IDs
let original = allEmails.first { $0.messageId == replyToId } ?? 
              allEmails.first { $0.id == replyToId }
```

### Email Address Normalization
```swift
// All emails stored lowercase for consistent grouping
senderEmail = senderEmail.lowercased()
recipientEmail = recipientEmail.lowercased()
```

### Reply Indicator Implementation
- **ReplyIndicatorView**: Shows dimmed gray bubble with original message
- **Placement**: Above message bubble in VStack, outside inner content
- **Styling**: Gray background, 0.6 opacity, same alignment as parent message

### Conversation Deduplication
- Startup: Merges conversations with same contact email (case-insensitive)
- Sync: 5-minute window for detecting local/remote duplicates
- Manual: Settings → "Clean Up Duplicates"

## Gmail API Integration Details

### Authentication Scopes
- `gmail.modify`: Read/write access to messages
- `gmail.send`: Send emails on user's behalf
- `userinfo.profile`: Fetch display name for proper From headers

### Message Construction
- **Reply Headers**: Sets `In-Reply-To` and `References` for threading
- **Subject Handling**: Fetches missing subjects on-demand when replying
- **From Field**: Uses display name from userinfo ("Name <email@gmail.com>")

### Sync Behavior
- **Initial Load**: Shows spinner only on first sync after login
- **Empty Inbox**: Shows "No messages" text, not spinner
- **Background Sync**: Silent updates every 10 seconds
- **Duplicate Detection**: Compares body content within 5-minute window

## Common Development Tasks

### Adding UI Features
1. Check existing patterns in MessageBubbleView for bubble styling
2. Use ContactAvatarView for consistent photo display
3. Follow white background pattern (no gray padding)

### Debugging Reply Chain
```swift
// Console output shows reply tracking
🔗 Creating reply to message:
   Reply to ID: xxx
📎 ReplyIndicator: Displaying reply to message
   Message text: 'actual content'
```

### Fixing CoreGraphics NaN Errors
- Avoid `.frame(maxWidth: .infinity)` with unbounded containers
- Use `.fixedSize(horizontal: false, vertical: true)` for text
- Set explicit dimensions for spacers and bars

## Testing Without Gmail Account
- App shows "Sign in to view your emails" prompt
- No sample data (removed for production)
- OAuth flow can be tested with any Google account

## Known Issues & Solutions

### Reply Indicator Not Showing Text
- Check `Email.snippet` field is populated
- Verify `inReplyToMessageId` is set to original's `id`
- Debug with console logs showing message IDs

### Duplicate Messages on Reply Cancel
- Fixed by clearing `messageText` when dismissing reply
- Cancel button also clears attachments and unfocuses field

### Empty Inbox Shows Spinner
- Check `hasCompletedInitialSync` state
- Only show spinner during `isInitialLoad && !hasCompletedInitialSync`

### Contact Photos Missing
- Verify Contacts permission granted
- Check lowercase email in `emailToContactMap`
- Photos cached after first fetch

## Project Structure

### Key Directories
- `ESC/Models/`: SwiftData models (Email, Conversation, Attachment)
- `ESC/Views/`: Main views (ConversationListView, ConversationDetailView)
- `ESC/Views/Components/`: Reusable UI (MessageBubbleView, ReplyIndicatorView)
- `ESC/Services/`: API and data services (GmailService, DataSyncService)
- `ESC/Utils/`: Helpers (MessageCleaner, EmailMessageBuilder, Base64Utils)

### Configuration Files
- `GoogleService-Info.plist`: OAuth client ID and configuration
- `Info.plist`: URL schemes for OAuth callback
- `ESC.entitlements`: No special entitlements required

### No External Dependencies
Project uses only native iOS frameworks:
- SwiftUI for UI
- SwiftData for persistence
- AuthenticationServices for OAuth
- Contacts for address book
- QuickLook for document preview