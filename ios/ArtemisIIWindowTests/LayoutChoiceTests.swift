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

    func testLandscapePhoneIsSeparateFromTheOpenFold() {
        XCTAssertEqual(
            LayoutChoice.stage(width: 402, height: 874, regularWidth: false, compactHeight: false),
            .phone
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 874, height: 402, regularWidth: false, compactHeight: true),
            .landscape
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 844, height: 390, regularWidth: false, compactHeight: false),
            .landscape
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 844, height: 390, regularWidth: true, compactHeight: true),
            .landscape
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 956, height: 440, regularWidth: false, compactHeight: true),
            .landscape
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 890, height: 626, regularWidth: true, compactHeight: false),
            .fold
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 890, height: 626, regularWidth: false, compactHeight: false),
            .fold
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 890, height: 626, regularWidth: true, compactHeight: true),
            .fold
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 1440, height: 900, regularWidth: true, compactHeight: false),
            .phone
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 0, height: 0, regularWidth: false, compactHeight: true),
            .landscape
        )
        XCTAssertEqual(
            LayoutChoice.stage(width: 0, height: 0, regularWidth: true, compactHeight: false),
            .phone
        )
        XCTAssertTrue(LayoutChoice.readsPhoneFrames(.phone))
        XCTAssertTrue(LayoutChoice.readsPhoneFrames(.landscape))
        XCTAssertFalse(LayoutChoice.readsPhoneFrames(.fold))
        let portrait = LayoutChoice.stage(width: 390, height: 844, regularWidth: false, compactHeight: false)
        let sideways = LayoutChoice.stage(width: 844, height: 390, regularWidth: false, compactHeight: true)
        XCTAssertEqual(
            LayoutChoice.readsPhoneFrames(portrait),
            LayoutChoice.readsPhoneFrames(sideways)
        )
    }
}
