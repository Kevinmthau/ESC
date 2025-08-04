import Foundation

struct Constants {
    struct Gmail {
        static let baseURL = "https://gmail.googleapis.com/gmail/v1"
        static let scopes = "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.send"
        static let clientId = "999923476073-b4m4r3o96gv30rqmo71qo210oa46au74.apps.googleusercontent.com"
        static let redirectUri = "com.googleusercontent.apps.999923476073-b4m4r3o96gv30rqmo71qo210oa46au74:/oauth"
    }
    
    struct Google {
        static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
        static let tokenURL = "https://oauth2.googleapis.com/token"
    }
    
    struct UserDefaults {
        static let accessTokenKey = "GoogleAuth.AccessToken"
        static let refreshTokenKey = "GoogleAuth.RefreshToken"
        static let isAuthenticatedKey = "GoogleAuth.IsAuthenticated"
    }
    
    struct UI {
        static let contactAvatarSize: CGFloat = 50
        static let messageBubbleCornerRadius: CGFloat = 18
        static let messageInputCornerRadius: CGFloat = 20
        static let minimumMessageInputHeight: CGFloat = 36
    }
    
    struct Sync {
        static let autoSyncInterval: TimeInterval = 10.0
    }
}