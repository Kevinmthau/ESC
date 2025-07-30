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
# Run unit tests
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# UI tests only
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:ESCUITests
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
- `ConversationDetailView.swift`: Chat interface with message bubbles and input
- `ComposeView.swift`: iMessage-style compose with contact selection and live Gmail sending
- `AuthenticationView.swift`: Google sign-in flow with error handling

### Services (`ESC/Services/`)
- `GmailService.swift`: Complete Gmail API integration with authentication, fetching, and sending
- `GoogleAuthManager.swift`: OAuth 2.0 flow using native iOS AuthenticationServices

### Configuration Files
- `GoogleService-Info.plist`: Google API credentials and project configuration
- `Info.plist`: URL schemes for OAuth redirects
- `SampleData.swift`: Fallback test data when not authenticated

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
1. **Authentication**: User taps + icon to authenticate or refresh data
2. **Data Sync**: Authenticated users get live Gmail data, others see sample data
3. **Compose Flow**: New messages send via Gmail API and update local conversation list
4. **Threading**: All messages to/from same contact appear in single conversation

## UI Design Patterns

### iMessage-Style Components
- **Clean White Design**: Edge-to-edge white backgrounds, no gray padding
- **Message Bubbles**: Blue bubbles for sent, gray for received
- **Compose Input**: Bottom-anchored input bar with rounded text field
- **Dynamic Buttons**: + button, voice/emoji when empty, send button when typing
- **Contact Suggestions**: Dropdown with avatars when typing in To: field

### Navigation Flow
- **Main List**: Conversations sorted by last message timestamp
- **Compose**: Modal sheet with cancel/send, automatically closes on send
- **Chat View**: Full-screen conversation with navigation back button
- **Authentication**: Modal sheet for Google sign-in

## Development Setup

### OAuth Configuration
- Google credentials configured in `GoogleService-Info.plist`
- URL schemes set up in `Info.plist` for OAuth redirects
- No external package dependencies - uses native iOS frameworks only

### Sample Data Fallback
- Automatically loads realistic sample conversations when database is empty
- Provides testing environment when not authenticated with Gmail
- Sample data demonstrates proper conversation threading and message styling

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
- Sample data provides realistic testing scenarios without API dependencies