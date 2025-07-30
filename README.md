# ESC - Email Simplified & Clean

ESC is an iOS email app that provides an iMessage-style interface for Gmail conversations. It simplifies email by grouping messages by sender/recipient into threaded conversations, ignoring email subjects to create a clean, chat-like experience.

## Features

- **iMessage-Style Interface**: Clean, white edge-to-edge design with familiar chat bubbles
- **Gmail Integration**: Full OAuth 2.0 authentication and Gmail API integration
- **Smart Threading**: Groups all emails to/from the same contact regardless of subject
- **Real-time Sync**: Live Gmail data with automatic token refresh
- **Message Cleaning**: Intelligent removal of quoted text and email signatures
- **Compose Flow**: iMessage-style compose with contact suggestions and inline sending
- **Persistent Auth**: Remembers authentication state between app launches

## Screenshots

<img src="docs/screenshots/conversation-list.png" width="250"> <img src="docs/screenshots/conversation-detail.png" width="250"> <img src="docs/screenshots/compose.png" width="250">

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Gmail account for full functionality

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/ESC.git
cd ESC
```

2. Open the project in Xcode:
```bash
open ESC.xcodeproj
```

3. Build and run on simulator or device

## Development

### Building

```bash
# Build for iOS Simulator
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build

# Build for device (requires provisioning)
xcodebuild -project ESC.xcodeproj -scheme ESC -configuration Debug -destination 'platform=iOS,name=iPhone' build
```

### Testing

```bash
# Run all tests
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# UI tests only
xcodebuild test -project ESC.xcodeproj -scheme ESC -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:ESCUITests
```

## Architecture

- **SwiftUI**: Modern declarative UI framework
- **SwiftData**: Persistent storage for emails and conversations
- **Native OAuth**: ASWebAuthenticationSession for secure Google sign-in
- **No Dependencies**: Pure Swift implementation without external packages

## Configuration

The app requires Google OAuth credentials configured in `GoogleService-Info.plist`. Contact the repository owner for development credentials or set up your own Google Cloud Console project with Gmail API access.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with SwiftUI and SwiftData
- Gmail API integration for real email functionality
- Inspired by iMessage's clean and intuitive interface