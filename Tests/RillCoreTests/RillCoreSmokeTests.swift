import XCTest
@testable import RillCore

/// Minimal smoke test confirming the RillCore module links and is reachable
/// from its test target.
final class RillCoreSmokeTests: XCTestCase {
    func testModuleVersionIsExposed() {
        XCTAssertFalse(RillCore.version.isEmpty)
    }
}
