import XCTest
@testable import NativeSlicerA1

/// P5-003/P5-005: MyMiniFactoryClient unit tests. Uses a mock
/// HTTPTransport to avoid the network and validate request shaping,
/// auth header logic, and error handling.
final class MyMiniFactoryClientTests: XCTestCase {
    private var mockTransport: MockTransport!

    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
    }

    private func httpResponse(_ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://mock.example")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    func testSearchWithAPIKey() async throws {
        let response = """
        {"total_count": 2, "items": [{"id": 1, "name": "test"}]}
        """
        mockTransport.data = (Data(response.utf8), httpResponse(200))
        let client = MyMiniFactoryClient(transport: mockTransport, apiKey: "test-key")
        let result = try await client.search(query: "benchy")

        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.items[0].id, 1)
        XCTAssertEqual(result.items[0].name, "test")

        // Verify the request included the API key query param.
        let request = mockTransport.lastRequest!
        XCTAssertTrue(request.url!.absoluteString.contains("key=test-key"))
        XCTAssertFalse(request.value(forHTTPHeaderField: "Authorization") != nil)
    }

    func testSearchWithAccessToken() async throws {
        let response = """
        {"total_count": 1, "items": [{"id": 5, "name": "mini"}]}
        """
        mockTransport.data = (Data(response.utf8), httpResponse(200))
        let client = MyMiniFactoryClient(transport: mockTransport, accessToken: "my-token")
        let result = try await client.search(query: "mini")

        XCTAssertEqual(result.items[0].id, 5)
        // OAuth token should take priority — no ?key= query param.
        let request = mockTransport.lastRequest!
        XCTAssertFalse(request.url!.absoluteString.contains("key="))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
    }

    func testSearchNoCredentialsThrows() async {
        let client = MyMiniFactoryClient(transport: mockTransport)
        do {
            _ = try await client.search(query: "anything")
            XCTFail("Should have thrown")
        } catch let error as MyMiniFactoryError {
            guard case .notSignedIn = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testObjectFilesWithOAuthPopulatesDownloadURL() async throws {
        let response = """
        {"total_count": 1, "items": [{"id": 42, "filename": "model.stl", "download_url": "https://cdn.example/model.stl", "size": "1234"}]}
        """
        mockTransport.data = (Data(response.utf8), httpResponse(200))
        let client = MyMiniFactoryClient(transport: mockTransport, accessToken: "oauth-token")
        let result = try await client.objectFiles(objectID: 999)

        XCTAssertEqual(result.items[0].downloadURL, "https://cdn.example/model.stl")
        XCTAssertEqual(result.items[0].filename, "model.stl")
    }

    func testDownloadFileWithoutOAuthThrows() async {
        let client = MyMiniFactoryClient(transport: mockTransport, apiKey: "key-only")
        let file = MMFFile(id: 1, filename: "model.stl", downloadURL: nil, size: "100")
        do {
            _ = try await client.downloadFile(file)
            XCTFail("Should have thrown")
        } catch let error as MyMiniFactoryError {
            guard case .downloadRequiresOAuth = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDownloadFileUsesOAuthBearerToken() async throws {
        mockTransport.data = (Data([0x01, 0x02, 0x03]), httpResponse(200))
        let client = MyMiniFactoryClient(transport: mockTransport, accessToken: "download-token")
        let file = MMFFile(
            id: 1,
            filename: "model.stl",
            downloadURL: "https://cdn.example/model.stl",
            size: "3"
        )

        let downloaded = try await client.downloadFile(file)
        XCTAssertEqual(downloaded, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(mockTransport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer download-token")
    }

    func testOAuthBuildsAndValidatesCallbackState() throws {
        let authorizeURL = MyMiniFactoryOAuth.authorizeURL(clientID: "client id", state: "expected-state")
        let items = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "client_id" })?.value, "client id")
        XCTAssertEqual(items?.first(where: { $0.name == "redirect_uri" })?.value, MyMiniFactory.redirectURI)
        XCTAssertEqual(try MyMiniFactoryOAuth.authorizationCode(
            from: URL(string: "nativeslicera1://mmf-callback?code=auth-code&state=expected-state")!,
            expectedState: "expected-state"
        ), "auth-code")
        XCTAssertThrowsError(try MyMiniFactoryOAuth.authorizationCode(
            from: URL(string: "nativeslicera1://mmf-callback?code=auth-code&state=attacker-state")!,
            expectedState: "expected-state"
        ))
    }

    func testOAuthTokenExchangeUsesBasicAuthAndDocumentedFormFields() async throws {
        mockTransport.data = (
            Data(#"{"user_id":7,"access_token":"access","expires_in":3600,"token_type":"Bearer","refresh_token":"refresh"}"#.utf8),
            httpResponse(200)
        )

        let tokens = try await MyMiniFactoryOAuth.exchangeCode(
            "authorization-code",
            clientID: "client",
            clientSecret: "secret",
            transport: mockTransport
        )

        XCTAssertEqual(tokens.accessToken, "access")
        XCTAssertEqual(tokens.refreshToken, "refresh")
        let request = mockTransport.lastRequest!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic Y2xpZW50OnNlY3JldA==")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let form = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(form.contains("grant_type=authorization_code"))
        XCTAssertTrue(form.contains("code=authorization-code"))
        XCTAssertTrue(form.contains("redirect_uri=nativeslicera1://mmf-callback"))
    }

    func testHTTPErrorIsPropagated() async {
        mockTransport.data = (Data("Not found".utf8), httpResponse(404))
        let client = MyMiniFactoryClient(transport: mockTransport, apiKey: "key")
        do {
            _ = try await client.search(query: "x")
            XCTFail("Should have thrown")
        } catch let error as MyMiniFactoryError {
            switch error {
            case .httpError(let code, _): XCTAssertEqual(code, 404)
            default: XCTFail("Unexpected error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Mock

private final class MockTransport: HTTPTransport {
    var data: (Data, URLResponse)!
    var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return data
    }
}
