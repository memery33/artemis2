import XCTest
@testable import ArtemisIIWindow

final class DemoPathTests: XCTestCase {
    func testShippedPathsStayInsideDemoData() {
        XCTAssertTrue(DemoPath.isContained("images/art002e016184.webp"))
        XCTAssertTrue(DemoPath.isContained("images/art002e016184.720.webp"))
        XCTAssertTrue(DemoPath.isContained("timeline.json"))
    }

    func testParentAndAbsolutePathsAreRefused() {
        XCTAssertFalse(DemoPath.isContained("../Info.plist"))
        XCTAssertFalse(DemoPath.isContained("images/../../Info.plist"))
        XCTAssertFalse(DemoPath.isContained("images/.."))
        XCTAssertFalse(DemoPath.isContained(".."))
        XCTAssertFalse(DemoPath.isContained("/etc/passwd"))
        XCTAssertFalse(DemoPath.isContained("~/Documents/a.webp"))
        XCTAssertFalse(DemoPath.isContained("images//a.webp"))
        XCTAssertFalse(DemoPath.isContained("./images/a.webp"))
        XCTAssertFalse(DemoPath.isContained("images\\..\\a.webp"))
        XCTAssertFalse(DemoPath.isContained(""))
    }

    func testEveryTimelinePathIsContained() throws {
        let url = try XCTUnwrap(Bundle(for: DemoPathTests.self).url(forResource: "timeline", withExtension: "json"))
        let timeline = try Timeline(data: Data(contentsOf: url))
        for segment in timeline.segments {
            XCTAssertTrue(DemoPath.isContained(segment.file), segment.file)
        }
        for frame in timeline.frames {
            XCTAssertTrue(DemoPath.isContained(frame.file), frame.file)
        }
    }
}
