import Foundation

/// P5-003/P5-005: a real, in-app model-repository integration — distinct
/// from `MakerWorldLinks`' browser delegation. MyMiniFactory publishes an
/// actual documented OpenAPI spec (`github.com/MyMiniFactory/api-
/// documentation/blob/master/myminifactory-api.yaml`, fetched and read
/// directly, not guessed) with two real auth modes:
///
/// - **API key** (`ApiKeyAuth`, `?key=` query param): search + public
///   object/file metadata, no user login required.
/// - **OAuth2 authorization-code** (`auth.myminifactory.com`, documented
///   in `oauth2-instructions.md`): required for `archive_download_url`/
///   `File.download_url` — the spec explicitly states these are "Available
///   ONLY with Oauth connected User. Not with API key."
///
/// Unlike MakerWorld (closed-source bind-ticket SSO, no public API —
/// RESEARCH-P0-011-CONNECTIVITY.md §3.1), this is a real, citable, public
/// API this app can legitimately call directly: search results render in
/// this app's own UI, and downloaded files flow straight into the
/// existing Import pipeline (`ProjectDocument.importModel`), not "open in
/// browser."
enum MyMiniFactory {
    static let apiBase = URL(string: "https://www.myminifactory.com/api/v2")!
    static let authorizeBase = "https://auth.myminifactory.com/web/authorize"
    static let tokenURL = URL(string: "https://auth.myminifactory.com/v1/oauth/tokens")!
    /// Redirect URI this app's own registered app on MyMiniFactory must
    /// use. Real OS-level routing of this custom scheme back to this
    /// process requires the app to be packaged as a `.app` bundle with
    /// `CFBundleURLTypes` declaring `nativeslicera1` (embedded via
    /// `Package.swift`'s `__info_plist` linker section — see
    /// `Resources/Info.plist`) AND registered with Launch Services; see
    /// that file's doc comment for the exact caveat. Same scheme
    /// `MakerWorldAuthPresenter` already uses.
    static let redirectURI = "nativeslicera1://mmf-callback"

    /// Keychain service namespace for every MyMiniFactory credential.
    static let keychainService = "com.nativeslicera1.myminifactory"
}

// MARK: - Models (field names/types match the real `Object`/`File`/`Image` schemas in myminifactory-api.yaml)

struct MMFImage: Decodable {
    struct Variant: Decodable { let url: String? }
    let thumbnail: Variant?
}

struct MMFDesigner: Decodable {
    let username: String?
    let name: String?
}

struct MMFObjectSummary: Decodable, Identifiable {
    let id: Int
    let name: String?
    let url: String?
    let designer: MMFDesigner?
    let images: [MMFImage]?
    let likes: Int?

    var thumbnailURL: URL? {
        images?.first(where: { $0.thumbnail?.url != nil })?.thumbnail?.url.flatMap(URL.init(string:))
    }
}

struct MMFSearchResponse: Decodable {
    let totalCount: Int
    let items: [MMFObjectSummary]
    private enum CodingKeys: String, CodingKey { case totalCount = "total_count", items }
}

struct MMFFile: Decodable, Identifiable {
    let id: Int
    let filename: String?
    /// Only populated by the server when the request carries a valid
    /// OAuth bearer token (spec: "Available ONLY with Oauth connected
    /// User. Not with API key.") — `nil` means this app must sign the
    /// user in before it can download real file bytes.
    let downloadURL: String?
    let size: String?
    private enum CodingKeys: String, CodingKey {
        case id, filename, size
        case downloadURL = "download_url"
    }
}

struct MMFFilesResponse: Decodable {
    let totalCount: Int
    let items: [MMFFile]
    private enum CodingKeys: String, CodingKey { case totalCount = "total_count", items }
}

enum MyMiniFactoryError: Error, LocalizedError {
    case notSignedIn
    case downloadRequiresOAuth
    case httpError(Int, body: String)
    case invalidCallback
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "No MyMiniFactory API key or signed-in account configured."
        case .downloadRequiresOAuth: return "This file's download URL requires signing in with a MyMiniFactory account (API key alone cannot download file bytes, per the official API spec)."
        case .httpError(let code, let body): return "MyMiniFactory API error \(code): \(body)"
        case .invalidCallback: return "OAuth callback URL did not contain an authorization code."
        case .missingCredential: return "Missing client ID/secret for MyMiniFactory OAuth sign-in."
        }
    }
}

/// Minimal seam over `URLSession.data(for:)` so tests can inject a fake
/// transport without touching the network (same async signature as the
/// real `URLSession` method — no adapter needed).
protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
extension URLSession: HTTPTransport {}

/// Real REST client for the documented MyMiniFactory v2 API.
final class MyMiniFactoryClient {
    private let transport: HTTPTransport
    /// API key (`ApiKeyAuth`, used for search/metadata without login).
    var apiKey: String?
    /// OAuth bearer token (required for `download_url`/`archive_download_url`).
    var accessToken: String?

    init(transport: HTTPTransport = URLSession.shared, apiKey: String? = nil, accessToken: String? = nil) {
        self.transport = transport
        self.apiKey = apiKey
        self.accessToken = accessToken
    }

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Appends `?key=` when no OAuth token is present (OAuth takes
    /// priority since it also unlocks `download_url`).
    private func withAPIKeyIfNeeded(_ components: URLComponents) -> URLComponents {
        guard accessToken == nil, let apiKey else { return components }
        var components = components
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey)]
        return components
    }

    private func perform<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let request = authorizedRequest(url)
        let (data, response) = try await transport.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MyMiniFactoryError.httpError(http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// `GET /search` — real text search over MyMiniFactory's public
    /// catalog. Works with just an API key; no sign-in required.
    func search(query: String, page: Int = 1, perPage: Int = 30) async throws -> MMFSearchResponse {
        guard accessToken != nil || apiKey != nil else { throw MyMiniFactoryError.notSignedIn }
        var components = URLComponents(url: MyMiniFactory.apiBase.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        components = withAPIKeyIfNeeded(components)
        return try await perform(components.url!, as: MMFSearchResponse.self)
    }

    /// `GET /objects/{id}/files` — file list for one object. `download_url`
    /// on each file is only populated when `accessToken` is set.
    func objectFiles(objectID: Int) async throws -> MMFFilesResponse {
        guard accessToken != nil || apiKey != nil else { throw MyMiniFactoryError.notSignedIn }
        var components = URLComponents(url: MyMiniFactory.apiBase.appendingPathComponent("objects/\(objectID)/files"), resolvingAgainstBaseURL: false)!
        components = withAPIKeyIfNeeded(components)
        return try await perform(components.url!, as: MMFFilesResponse.self)
    }

    /// Downloads a file's real bytes. Requires `file.downloadURL` to be
    /// present, which per the spec only happens when signed in via OAuth.
    func downloadFile(_ file: MMFFile) async throws -> Data {
        guard let downloadURLString = file.downloadURL, let downloadURL = URL(string: downloadURLString) else {
            throw MyMiniFactoryError.downloadRequiresOAuth
        }
        let request = authorizedRequest(downloadURL)
        let (data, response) = try await transport.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MyMiniFactoryError.httpError(http.statusCode, body: String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }
}

// MARK: - OAuth2 (authorization-code grant, per oauth2-instructions.md)

struct MMFTokens: Decodable {
    let userID: Int
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String?
    private enum CodingKeys: String, CodingKey {
        case userID = "user_id", accessToken = "access_token", expiresIn = "expires_in"
        case tokenType = "token_type", refreshToken = "refresh_token"
    }
}

/// Real OAuth2 authorization-code exchange against MyMiniFactory's
/// documented `auth.myminifactory.com` endpoints — unlike MakerWorld (no
/// public OAuth redirect to exchange), this flow actually completes with
/// a real authorization code this app parses and exchanges for a token.
enum MyMiniFactoryOAuth {
    /// Builds the real authorize URL a user is sent to.
    static func authorizeURL(clientID: String, state: String) -> URL {
        var components = URLComponents(string: MyMiniFactory.authorizeBase)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: MyMiniFactory.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Extracts the `code` query item from the callback URL
    /// `ASWebAuthenticationSession` hands back, verifying `state` matches
    /// to guard against CSRF per the spec's own XSS-prevention note.
    static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value
        else { throw MyMiniFactoryError.invalidCallback }
        return code
    }

    /// Exchanges an authorization code for real tokens via
    /// `POST https://auth.myminifactory.com/v1/oauth/tokens`, HTTP Basic
    /// client auth + form body — exact shape from the official
    /// `oauth2-instructions.md` curl example.
    static func exchangeCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        transport: HTTPTransport = URLSession.shared
    ) async throws -> MMFTokens {
        var request = URLRequest(url: MyMiniFactory.tokenURL)
        request.httpMethod = "POST"
        let credentials = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: MyMiniFactory.redirectURI),
        ]
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await transport.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MyMiniFactoryError.httpError(http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(MMFTokens.self, from: data)
    }
}
