import XCTest
@testable import NativeSlicerA1

/// P5-003/P5-005: KeychainStore is a small wrapper around the Security
/// framework; tests here exercise the actual Keychain API (not mocked)
/// to confirm it round-trips strings correctly for the service/account
/// namespace used by MyMiniFactoryAccount.
final class KeychainStoreTests: XCTestCase {
    private static let testService = "com.nativeslicera1.test.keychain"
    private static let testAccount = "roundtrip"

    override class func setUp() {
        // Clean slate before each test class run.
        KeychainStore.delete(service: Self.testService, account: Self.testAccount)
    }

    override class func tearDown() {
        KeychainStore.delete(service: Self.testService, account: Self.testAccount)
    }

    func testSetAndGetRoundTrip() {
        XCTAssertTrue(KeychainStore.set("secret-value", service: Self.testService, account: Self.testAccount))
        XCTAssertEqual(KeychainStore.get(service: Self.testService, account: Self.testAccount), "secret-value")
    }

    func testGetReturnsNilWhenNothingStored() {
        XCTAssertNil(KeychainStore.get(service: Self.testService, account: "nonexistent"))
    }

    func testOverwriteReplacesOldValue() {
        XCTAssertTrue(KeychainStore.set("old", service: Self.testService, account: Self.testAccount))
        XCTAssertTrue(KeychainStore.set("new", service: Self.testService, account: Self.testAccount))
        XCTAssertEqual(KeychainStore.get(service: Self.testService, account: Self.testAccount), "new")
    }

    func testDeleteRemovesStoredValue() {
        XCTAssertTrue(KeychainStore.set("to-delete", service: Self.testService, account: Self.testAccount))
        XCTAssertTrue(KeychainStore.delete(service: Self.testService, account: Self.testAccount))
        XCTAssertNil(KeychainStore.get(service: Self.testService, account: Self.testAccount))
    }

    func testDeleteNonexistentReturnsTrueQuietly() {
        XCTAssertTrue(KeychainStore.delete(service: Self.testService, account: "no-such-account"))
    }
}
