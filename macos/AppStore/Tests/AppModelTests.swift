import XCTest
@testable import OpenVoiceFlowStore

final class AppModelTests: XCTestCase {
    func testNormalizeTranscriptTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(normalizeTranscript("  hello  \n world  "), "hello world")
    }

    func testNormalizeTranscriptPreservesPunctuation() {
        XCTAssertEqual(normalizeTranscript("Hello, world."), "Hello, world.")
    }
}
