import Foundation
import AppKit
import AuthenticationServices

/// Keychain-backed storage for the real MyMiniFactory credentials a user
/// configures: an API key (search/metadata only) and/or their own
/// self-registered OAuth app's client ID/secret + the resulting tokens
/// (required for real file downloads — see `MyMiniFactoryClient.swift`).
/// Never UserDefaults/plaintext — AGENTS.md §10.
enum MyMiniFactoryAccount {
    private static func account(_ key: String) -> String { key }

    static var apiKey: String? {
        get { KeychainStore.get(service: MyMiniFactory.keychainService, account: "apiKey") }
        set {
            if let newValue {
                KeychainStore.set(newValue, service: MyMiniFactory.keychainService, account: "apiKey")
            } else {
                KeychainStore.delete(service: MyMiniFactory.keychainService, account: "apiKey")
            }
        }
    }

    static var clientID: String? {
        get { KeychainStore.get(service: MyMiniFactory.keychainService, account: "clientID") }
        set {
            if let newValue { KeychainStore.set(newValue, service: MyMiniFactory.keychainService, account: "clientID") }
            else { KeychainStore.delete(service: MyMiniFactory.keychainService, account: "clientID") }
        }
    }

    static var clientSecret: String? {
        get { KeychainStore.get(service: MyMiniFactory.keychainService, account: "clientSecret") }
        set {
            if let newValue { KeychainStore.set(newValue, service: MyMiniFactory.keychainService, account: "clientSecret") }
            else { KeychainStore.delete(service: MyMiniFactory.keychainService, account: "clientSecret") }
        }
    }

    static var accessToken: String? {
        get { KeychainStore.get(service: MyMiniFactory.keychainService, account: "accessToken") }
        set {
            if let newValue { KeychainStore.set(newValue, service: MyMiniFactory.keychainService, account: "accessToken") }
            else { KeychainStore.delete(service: MyMiniFactory.keychainService, account: "accessToken") }
        }
    }

    static var refreshToken: String? {
        get { KeychainStore.get(service: MyMiniFactory.keychainService, account: "refreshToken") }
        set {
            if let newValue { KeychainStore.set(newValue, service: MyMiniFactory.keychainService, account: "refreshToken") }
            else { KeychainStore.delete(service: MyMiniFactory.keychainService, account: "refreshToken") }
        }
    }

    static func store(_ tokens: MMFTokens) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
    }

    static func signOut() {
        accessToken = nil
        refreshToken = nil
    }

    static var isSignedIn: Bool { accessToken != nil }
    static var hasAnyCredential: Bool { apiKey != nil || accessToken != nil }
}

/// Real OAuth2 sign-in flow via `ASWebAuthenticationSession` — unlike
/// `MakerWorldAuthPresenter`, this one actually parses a real callback
/// (MyMiniFactory implements a documented OAuth redirect; MakerWorld does
/// not). See `MyMiniFactory.redirectURI`'s doc comment for the
/// `CFBundleURLTypes`/Launch-Services packaging caveat that governs
/// whether the OS can route the redirect back to this process at all.
@MainActor
final class MyMiniFactoryAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var anchorWindow: NSWindow?

    /// Starts the real authorization-code flow, exchanges the resulting
    /// code for tokens, and stores them in the Keychain on success.
    func signIn(clientID: String, clientSecret: String, anchor window: NSWindow) async throws {
        anchorWindow = window
        let state = UUID().uuidString
        let authorizeURL = MyMiniFactoryOAuth.authorizeURL(clientID: clientID, state: state)

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: "nativeslicera1"
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? MyMiniFactoryError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        let code = try MyMiniFactoryOAuth.authorizationCode(from: callbackURL, expectedState: state)
        let tokens = try await MyMiniFactoryOAuth.exchangeCode(code, clientID: clientID, clientSecret: clientSecret)
        MyMiniFactoryAccount.clientID = clientID
        MyMiniFactoryAccount.clientSecret = clientSecret
        MyMiniFactoryAccount.store(tokens)
    }

    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}
