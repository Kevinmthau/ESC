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
- **Email**: Individual email messages with sender, recipient, body, timestamp, read status, subject, and reply tracking (inReplyToMessageId). Email addresses are normalized to lowercase for consistent grouping.
- **Conversation**: Aggregated container grouping emails by contact with metadata (last message preview, read status). Preview always shows the most recent message.
- **Attachment**: File attachments with inline display for images and QuickLook preview for documents
- Threading logic groups all emails to/from the same contact regardless of subject

### UI Layer (SwiftUI)
- **ConversationListView**: Main inbox with white edge-to-edge design, conversations sorted by timestamp showing most recent message preview
- **ConversationDetailView**: iMessage-style chat interface with message bubbles, reply/forward functionality - **IMPORTANT: New message composition happens here, not in ComposeView**
- **ComposeView**: Standalone compose view (currently unused - new messages use ConversationDetailView)
- **AuthenticationView**: Google OAuth authentication interface
- Clean white backgrounds throughout, no gray padding

### Service Layer
- **GmailService**: Complete Gmail API integration for fetching, parsing, and sending emails with reply support. Fetches user display name for proper From headers.
- **GoogleAuthManager**: OAuth 2.0 authentication using ASWebAuthenticationSession
- **DataSyncService**: Background sync service with timer-based polling (10-second intervals), duplicate detection, and conversation merging
- **ContactsService**: iOS Contacts integration with photo caching and name resolution

## Key Files and Responsibilities

### Models (`ESC/Models/`)
- `Email.swift`: Core email data model with SwiftData persistence, includes subject and inReplyToMessageId for threading
- `Conversation.swift`: Container model with email aggregation and sorting logic
- `Attachment.swift`: File attachment model with data storage and MIME type handling

### Views (`ESC/Views/`)
- `ConversationListView.swift`: Main inbox with Gmail integration and compose button
- `ConversationDetailView.swift`: Chat interface with message bubbles, reply/forward actions, and input
- `AuthenticationView.swift`: Google sign-in flow with error handling
- `ForwardComposeView.swift`: Dedicated view for forwarding emails with recipient selection

### Views/Components
- `MessageBubbleView.swift`: Message display with long-press context menu for reply/forward
- `MessageInputView.swift`: Bottom input bar with attachment support and dynamic button states
- `ContactAvatarView.swift`: Contact photo display with fallback to initials
- `EmailReaderView.swift`: Full HTML email viewer for newsletters and formatted content
- `LinkedTextView.swift`: Tappable links in message bubbles

### Services (`ESC/Services/`)
- `GmailService.swift`: Gmail API integration with reply headers (In-Reply-To, References) support
- `GoogleAuthManager.swift`: OAuth 2.0 flow using native iOS AuthenticationServices
- `DataSyncService.swift`: Background sync with duplicate detection, conversation merging, and preview updates
- `ContactsService.swift`: iOS Contacts integration with lowercase email mapping for case-insensitive lookups
- `MessageParserService.swift`: Extracts email content, attachments, and headers including subject
- `GmailAPIClient.swift`: Low-level Gmail API calls with token refresh handling

### Utilities (`ESC/Utils/`)
- `MessageCleaner.swift`: Email content cleaning to remove quoted text and signatures
- `EmailMessageBuilder.swift`: RFC2822 message construction with multipart/MIME and reply headers support
- `Base64Utils.swift`: Gmail's URL-safe base64 encoding/decoding
- `EmailValidator.swift`: Email address validation and parsing with lowercase normalization
- `LinkDetector.swift`: URL detection and extraction from message text
- `Constants.swift`: App-wide configuration including OAuth scopes and UI constants

### Configuration Files
- `GoogleService-Info.plist`: Google API credentials and project configuration
- `Info.plist`: URL schemes for OAuth redirects (`com.googleusercontent.apps.YOUR_CLIENT_ID`)

## Gmail API Integration

### Authentication Flow
1. **GoogleAuthManager** handles OAuth 2.0 using ASWebAuthenticationSession
2. Uses native iOS secure web authentication with proper URL scheme handling
3. Automatic token refresh with error recovery
4. Scopes: `gmail.modify`, `gmail.send`, `userinfo.profile`

### API Operations
- **Fetch Messages**: `GmailService.fetchEmails()` retrieves and parses Gmail messages with attachments
- **Send Messages**: `GmailService.sendEmail()` creates RFC2822 format emails with proper From headers using display name
- **Reply Threading**: Maintains `In-Reply-To` and `References` headers for Gmail conversation threading
- **Attachment Handling**: Downloads attachments on-demand, supports inline images and document previews
- **Subject Preservation**: Fetches missing subjects from Gmail API when replying to maintain threading
- **User Profile**: Fetches user display name from OAuth2 userinfo endpoint for proper sender identification

### Data Flow
1. **Authentication**: User taps settings icon to authenticate or manages accounts
2. **Data Sync**: DataSyncService polls Gmail API every 10 seconds for new messages
3. **Reply Flow**: Long-press message → Reply → Inline preview → Send with preserved subject
4. **Forward Flow**: Long-press message → Forward → Modal compose sheet with original content
5. **Contact Integration**: Names resolved from address book, photos cached for performance

## UI Design Patterns

### iMessage-Style Components
- **Clean White Design**: Edge-to-edge white backgrounds, no gray padding
- **Message Bubbles**: Blue bubbles for sent, gray for received
- **Reply Preview**: Blue accent bar with sender info and message snippet above input
- **Context Menu**: Long-press for Reply and Forward options
- **Attachment Display**: Inline images, file bubbles with icons for documents
- **HTML Email Support**: "View full message" button for newsletters with full-screen reader
- **Clickable Links**: URLs in messages are tappable and open in Safari

### Navigation Flow
- **Main List**: Conversations sorted by last message timestamp with NavigationStack
- **New Message**: Tapping compose creates empty Conversation and navigates to ConversationDetailView
- **Reply**: Stays on same conversation page with inline reply preview
- **Forward**: Opens modal ForwardComposeView with original message content
- **Authentication**: Modal sheet for Google sign-in
- **Settings**: Modal sheet with account management and cleanup options

### Modern Navigation Architecture
- Uses `NavigationStack` with `NavigationPath` for iOS 16+ programmatic navigation
- Compose flow navigates directly to conversation after sending message
- Messages appear immediately in chat without requiring refresh
- Reply flow maintains conversation context without navigation

## Development Setup

### OAuth Configuration
- Google credentials configured in `GoogleService-Info.plist`
- URL schemes set up in `Info.plist` for OAuth redirects
- Required scopes include gmail.modify, gmail.send, and userinfo.profile
- No external package dependencies - uses native iOS frameworks only

### iOS Contacts Integration
- Requests permission for address book access on first use
- Caches contact photos for performance
- Falls back to initials in colored circles when photos unavailable
- Name resolution priority: Address book > Gmail headers > formatted email username

## SwiftData Configuration

The app uses a shared ModelContainer configured in `ESCApp.swift` with:
- Schema including Email, Conversation, and Attachment models
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

### Reply and Forward Flow
- **Reply**: Long-press message → Context menu → Reply action → Inline preview with original message
- Reply preview shows sender and snippet with blue accent bar and dismiss button
- Subject automatically preserved with "Re:" prefix for proper threading
- **Forward**: Long-press message → Context menu → Forward → Modal sheet with recipient selection
- Forward includes original message content with "Forwarded message" header

### Background Sync Architecture
- DataSyncService runs on 10-second timer when authenticated
- Silent background sync prevents UI interruption
- Duplicate detection for recently sent messages (5-minute window)
- Conversation timestamps and previews update automatically
- New message notifications available via NotificationCenter
- Automatic conversation merging for duplicate contacts on startup

### Email Normalization
- All email addresses stored lowercase for consistent conversation grouping
- Prevents duplicate conversations from case variations (e.g., John@example.com vs john@example.com)
- ContactsService uses lowercase keys for case-insensitive lookups
- Conversation merging handles existing duplicates on app startup

### Contact Photo System
- ContactAvatarView handles photo loading and caching
- ContactsService stores lowercase email keys for case-insensitive lookups
- Fallback initials use first letter of display name with gradient backgrounds
- Photo cache prevents repeated iOS Contacts API calls
- Circular cropping with consistent sizing throughout app

### Attachment System
- Supports all file types with appropriate icons (PDF, images, documents, archives)
- Inline display for images with pinch-to-zoom viewer
- QuickLook preview for documents
- Base64 encoding for sending attachments via Gmail API
- Multipart MIME message construction for emails with attachments

### Settings and Maintenance
- "Clean Up Duplicates" button removes duplicate messages within conversations
- "Fix Message Previews" updates all conversation previews to show most recent message
- "Switch Account" allows changing Google accounts while preserving local data
- "Delete Account Data" removes all local emails and signs out

## Common Issues & Solutions

### Contact Photos Not Showing
- Verify ContactsService has fetched contacts (check logs for "✅ ContactsService: Fetched X contacts")
- Email addresses are stored lowercase in emailToContactMap for case-insensitive lookups
- Check iOS Settings > Privacy > Contacts for app permissions

### New Message Composition
- New messages use ConversationDetailView, not ComposeView
- The To: field appears when `conversation.contactEmail.isEmpty`
- Contact suggestions require ContactsService to have fetched contacts on view appearance

### Reply Subject Missing
- App fetches missing subjects from Gmail API on-demand when replying
- Subjects are stored in Email model for future use
- Check logs for "📬 Reply to email - Subject:" to debug subject issues

### Duplicate Conversations or Messages
- DataSyncService includes automatic deduplication on startup
- Use Settings → "Clean Up Duplicates" to manually remove duplicate messages
- Email normalization prevents new duplicates from case variations

### Conversation Preview Shows Wrong Message
- Use Settings → "Fix Message Previews" to update all previews
- Previews automatically update during sync to show most recent message
- Check DataSyncService logs for preview update confirmations

### Sender Name Shows Email Instead of Display Name
- Requires userinfo.profile scope in OAuth authentication
- Sign out and sign back in to request new permissions
- Check GmailService.getUserDisplayName() for proper name fetching