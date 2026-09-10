import XCTest
@testable import RillUI

/// Minimal smoke test confirming the RillUI module links and is reachable
/// from its test target.
final class RillUISmokeTests: XCTestCase {
    func testModuleVersionIsExposed() {
        XCTAssertFalse(RillUI.version.isEmpty)
    }
}
