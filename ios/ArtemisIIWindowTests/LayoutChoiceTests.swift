import XCTest
@testable import ArtemisIIWindow

final class LayoutChoiceTests: XCTestCase {
    func testOpenFoldAndPhoneShapes() {
        XCTAssertTrue(LayoutChoice.isOpenFold(width: 890, height: 626, regularWidth: true))
        XCTAssertTrue(LayoutChoice.isOpenFold(width: 890, height: 626, regularWidth: false))
        XCTAssertFalse(LayoutChoice.isOpenFold(width: 466, height: 678, regularWidth: false))
        XCTAssertFalse(LayoutChoice.isOpenFold(width: 844, height: 390, regularWidth: false))
        XCTAssertFalse(LayoutChoice.isOpenFold(width: 844, height: 390, regularWidth: true))
        XCTAssertFalse(LayoutChoice.isOpenFold(width: 1440, height: 900, regularWidth: true))
        XCTAssertFalse(LayoutChoice.isOpenFold(width: 0, height: 0, regularWidth: true))
    }
}
