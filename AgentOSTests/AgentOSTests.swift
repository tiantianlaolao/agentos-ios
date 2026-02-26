import XCTest
@testable import AgentOS

final class AgentOSTests: XCTestCase {
    func testProtocolEnums() {
        XCTAssertEqual(MessageType.connect.rawValue, "connect")
        XCTAssertEqual(ConnectionMode.builtin.rawValue, "builtin")
        XCTAssertEqual(ErrorCode.authFailed.rawValue, "AUTH_FAILED")
    }

    func testChatMessage() {
        let msg = ChatMessage(
            conversationId: "test",
            role: .user,
            content: "Hello"
        )
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Hello")
    }

    func testPhoneValidation() {
        XCTAssertTrue("13812345678".isValidChinesePhone)
        XCTAssertFalse("1234567".isValidChinesePhone)
        XCTAssertFalse("abc".isValidChinesePhone)
    }
}
