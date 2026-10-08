"""Run the actual Foundation link parser/router tests on the existing macOS runner.
No simulator, network calls, signing or application deployment.
"""
from pathlib import Path
import tempfile,subprocess,re
root=Path(__file__).resolve().parents[1]
model=(root/'AgentOS/Models/ChatMessage.swift').read_text()
match=re.search(r'struct CoderAction:[\s\S]*?\n}',model);assert match
tests=(root/'AgentOSTests/CoderLinkTests.swift').read_text().replace('import XCTest','import Foundation').replace('@testable import AgentOS','').replace('final class CoderLinkTests: XCTestCase','final class CoderLinkTests')
helpers='''
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "") { precondition(a == b, message) }
func XCTAssertNil<T>(_ value: T?, _ message: String = "") { precondition(value == nil, message) }
@main struct RunCoderLinkChecks {
    @MainActor static func main() {
        let tests = CoderLinkTests()
        tests.testPublicActionParsing()
        tests.testLoginContinuation()
        tests.testExistingWorkbenchIsNotReplacedByIncomingLink()
        tests.testClosingWorkbenchContinuesPendingLink()
        print("PASS: actual Swift/Foundation URL parsing and all four router test cases")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='aihey-link-tests-') as directory:
 d=Path(directory);(d/'Action.swift').write_text('import Foundation\n'+match.group(0));(d/'Tests.swift').write_text(tests+helpers)
 binary=d/'checks'
 subprocess.run(['xcrun','swiftc','-swift-version','6','-parse-as-library',str(d/'Action.swift'),str(root/'AgentOS/Services/CoderLinkRouter.swift'),str(d/'Tests.swift'),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
