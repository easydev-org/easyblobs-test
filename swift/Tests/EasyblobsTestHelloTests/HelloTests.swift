import XCTest
@testable import EasyblobsTestHello

final class HelloTests: XCTestCase {
    func testGreet() {
        XCTAssertEqual(greet("easyblobs"), "hello easyblobs")
    }
}
