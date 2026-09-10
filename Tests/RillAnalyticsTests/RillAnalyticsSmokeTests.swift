import XCTest
@testable import RillAnalytics

/// Minimal smoke test confirming the RillAnalytics module links and is
/// reachable from its test target.
final class RillAnalyticsSmokeTests: XCTestCase {
    func testModuleVersionIsExposed() {
        XCTAssertFalse(RillAnalytics.version.isEmpty)
    }
}
