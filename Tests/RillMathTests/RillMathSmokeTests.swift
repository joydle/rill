import XCTest
@testable import RillMath

/// Minimal smoke test confirming the RillMath module links and is reachable
/// from its test target.
final class RillMathSmokeTests: XCTestCase {
    func testModuleVersionIsExposed() {
        XCTAssertFalse(RillMath.version.isEmpty)
    }
}
