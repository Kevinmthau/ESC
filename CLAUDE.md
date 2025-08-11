# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESC is an iOS email app that provides an iMessage-style interface for Gmail conversations. The app groups emails by sender/recipient into threaded conversations and ignores email subjects, creating a chat-like experience with full Gmail API integration for reading and sending emails.

## Development Commands

### Building
```bash
# Build for iOS Simulator
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build

# Build for device (requires proper provisioning)
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS,name=iPhone' build
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

### Cleaning & Rebuilding
```bash
# Clean build folder
xcodebuild clean -project ESC.xcodeproj -scheme ESC

# Clean and build
xcodebuild clean build -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
```

## Core Architecture

### Data Layer (SwiftData)
- **Email**: Individual email messages with sender, recipient, body, timestamp, and read status
- **Conversation**: Aggregated container grouping emails by contact with metadata (last message, read status)
- Threading logic groups all emails to/from the same contact regardless of subject

### UI Layer (SwiftUI)
- **ConversationListView**: Main inbox with white edge-to-edge design, conversations sorted by timestamp
- **ConversationDetailView**: iMessage-style chat interface with message bubbles
- **ComposeView**: Full iMessage-style compose flow with contact suggestions and bottom input bar
- **AuthenticationView**: Google OAuth authentication interface
- Clean white backgrounds throughout, no gray padding

### Service Layer
- **GmailService**: Complete Gmail API integration for fetching, parsing, and sending emails
- **GoogleAuthManager**: OAuth 2.0 authentication using ASWebAuthenticationSession
- Full token management with automatic refresh handling

## Key Files and Responsibilities

### Models (`ESC/Models/`)
- `Email.swift`: Core email data model with SwiftData persistence
- `Conversation.swift`: Container model with email aggregation and sorting logic

### Views (`ESC/Views/`)
- `ConversationListView.swift`: Main inbox with Gmail integration and compose button
- `ConversationDetailView.swift`: Chat interface with message bubbles and input - **IMPORTANT: New message composition happens here, not in ComposeView**
- `ComposeView.swift`: Standalone compose view (currently unused - new messages use ConversationDetailView)
- `AuthenticationView.swift`: Google sign-in flow with error handling

### Services (`ESC/Services/`)
- `GmailService.swift`: Complete Gmail API integration with authentication, fetching, and sending
- `GoogleAuthManager.swift`: OAuth 2.0 flow using native iOS AuthenticationServices
- `DataSyncService.swift`: Background sync service with timer-based polling (10-second intervals)
- `ContactsService.swift`: iOS Contacts integration with photo caching and name resolution

### Utilities (`ESC/Utils/`)
- `MessageCleaner.swift`: Email content cleaning to remove quoted text and signatures

### Additional Views
- `ContactAvatarView.swift`: Contact photo display with fallback to initials
- `SettingsView.swift`: Account management with sign-out and data deletion

### Configuration Files
- `GoogleService-Info.plist`: Google API credentials and project configuration
- `Info.plist`: URL schemes for OAuth redirects

## Gmail API Integration

### Authentication Flow
1. **GoogleAuthManager** handles OAuth 2.0 using ASWebAuthenticationSession
2. Uses native iOS secure web authentication with proper URL scheme handling
3. Automatic token refresh with error recovery
4. Scopes: `gmail.readonly` and `gmail.send`

### API Operations
- **Fetch Messages**: `GmailService.fetchEmails()` retrieves and parses Gmail messages
- **Send Messages**: `GmailService.sendEmail()` creates RFC2822 format emails and sends via Gmail API
- **Message Threading**: Groups messages by contact email, ignoring subjects
- **Base64 Decoding**: Handles Gmail's URL-safe base64 encoding for message content

### Data Flow
1. **Authentication**: User taps settings icon to authenticate or manages accounts
2. **Data Sync**: DataSyncService polls Gmail API every 10 seconds for new messages
3. **Compose Flow**: New messages send via Gmail API and immediately navigate to chat view
4. **Threading**: All messages to/from same contact appear in single conversation
5. **Contact Integration**: Names resolved from address book, photos cached for performance

## UI Design Patterns

### iMessage-Style Components
- **Clean White Design**: Edge-to-edge white backgrounds, no gray padding
- **Message Bubbles**: Blue bubbles for sent, gray for received
- **Compose Input**: Bottom-anchored input bar with rounded text field
- **Dynamic Buttons**: + button, voice/emoji when empty, send button when typing
- **Contact Suggestions**: Dropdown with avatars when typing in To: field

### Navigation Flow
- **Main List**: Conversations sorted by last message timestamp with NavigationStack
- **New Message**: Tapping compose creates empty Conversation and navigates to ConversationDetailView
- **Chat View**: Full-screen conversation with navigation back button
- **Authentication**: Modal sheet for Google sign-in
- **Settings**: Modal sheet with account management options

### Modern Navigation Architecture
- Uses `NavigationStack` with `NavigationPath` for iOS 16+ programmatic navigation
- Compose flow navigates directly to conversation after sending message
- Messages appear immediately in chat without requiring refresh

## Development Setup

### OAuth Configuration
- Google credentials configured in `GoogleService-Info.plist`
- URL schemes set up in `Info.plist` for OAuth redirects
- No external package dependencies - uses native iOS frameworks only

### iOS Contacts Integration
- Requests permission for address book access on first use
- Caches contact photos for performance
- Falls back to initials in colored circles when photos unavailable
- Name resolution priority: Address book > Gmail headers > formatted email username

## SwiftData Configuration

The app uses a shared ModelContainer configured in `ESCApp.swift` with:
- Schema including Email and Conversation models
- Persistent storage with conversation sorting by timestamp
- Automatic relationship management between models
- New conversations automatically appear at top of list after sending

## Testing Approach

- Unit tests use new Swift Testing framework
- UI tests include launch performance testing
- Preview providers use in-memory data containers
- Testing without authentication falls back to empty state (sample data removed)

## Key Implementation Details

### Message Composition Flow
- New messages: ConversationListView creates empty Conversation and navigates to ConversationDetailView
- ConversationDetailView shows To: field with contact suggestions for new conversations (when contactEmail is empty)
- Contact suggestions pull from both iOS Contacts and existing conversations
- After sending, message appears immediately in local storage before Gmail API confirmation
- Uses modern NavigationStack pattern for programmatic navigation

### Background Sync Architecture
- DataSyncService runs on 10-second timer when authenticated
- Silent background sync prevents UI interruption
- Conversation timestamps drive automatic sorting
- New message notifications available via NotificationCenter

### Contact Photo System
- ContactAvatarView handles photo loading and caching
- ContactsService stores lowercase email keys for case-insensitive lookups
- Fallback initials use first letter of display name with gradient backgrounds
- Photo cache prevents repeated iOS Contacts API calls
- Circular cropping with consistent sizing throughout app

## Common Issues & Solutions

### Contact Photos Not Showing
- Verify ContactsService has fetched contacts (check logs for "✅ ContactsService: Fetched X contacts")
- Email addresses are stored lowercase in emailToContactMap for case-insensitive lookups
- Check iOS Settings > Privacy > Contacts for app permissions

### New Message Composition
- New messages use ConversationDetailView, not ComposeView
- The To: field appears when `conversation.contactEmail.isEmpty`
- Contact suggestions require ContactsService to have fetched contacts on view appearance