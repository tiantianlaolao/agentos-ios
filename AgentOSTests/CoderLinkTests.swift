import XCTest
@testable import AgentOS

final class CoderLinkTests: XCTestCase {
    func testPublicActionParsing() {
        let request = CoderLinkRequest.parse(URL(string: "https://coder.tybbtech.com/app/open?action=remix&remix=p123")!)
        XCTAssertEqual(request?.action.remix, "p123")
        XCTAssertEqual(request?.action.startNew, false)
        XCTAssertEqual(CoderLinkRequest.parse(URL(string: "https://coder.tybbtech.com/app/open?action=new")!)?.action.startNew, true)
        for link in [
            "https://evil.test/app/open?action=new",
            "https://user@coder.tybbtech.com/app/open?action=new",
            "https://coder.tybbtech.com:3201/app/open?action=new",
            "https://coder.tybbtech.com/app/open/?action=new",
            "https://coder.tybbtech.com/app/open?action=new&token=secret",
            "https://coder.tybbtech.com/app/open?action=new&action=remix",
            "https://coder.tybbtech.com/app/open?action=remix&remix=p1&remix=p2",
            "https://coder.tybbtech.com/app/open?action=remix&remix=p1%0A",
            "https://coder.tybbtech.com/app/open?action=new&remix=p1",
            "https://coder.tybbtech.com/app/open?action=new#token"
        ] { XCTAssertNil(CoderLinkRequest.parse(URL(string: link)!), link) }
    }

    @MainActor func testLoginContinuation() {
        let router = CoderLinkRouter()
        router.receive(URL(string: "https://coder.tybbtech.com/app/open?action=remix&remix=p1")!)
        XCTAssertNil(router.presented)
        XCTAssertEqual(router.pending?.action.remix, "p1")
        router.authenticated = true
        router.presentPending()
        XCTAssertNil(router.pending)
        XCTAssertEqual(router.presented?.action.remix, "p1")
    }

    @MainActor func testExistingWorkbenchIsNotReplacedByIncomingLink() {
        let router = CoderLinkRouter(), workstation = UUID()
        router.authenticated = true
        router.entered(workstation)
        router.receive(URL(string: "https://coder.tybbtech.com/app/open?action=new")!)
        XCTAssertNil(router.presented)
        let pendingID = router.pending!.id
        XCTAssertNil(router.takePending(UUID()))
        XCTAssertEqual(router.takePending(pendingID)?.startNew, true)
        XCTAssertNil(router.pending)
    }

    @MainActor func testClosingWorkbenchContinuesPendingLink() {
        let router = CoderLinkRouter(), workstation = UUID()
        router.authenticated = true
        router.entered(workstation)
        router.receive(URL(string: "https://coder.tybbtech.com/app/open?action=remix&remix=p2")!)
        router.left(workstation)
        router.presentPending()
        XCTAssertEqual(router.presented?.action.remix, "p2")
    }
}
