import MediaPlayer
import UIKit
import XCTest
@testable import ArtemisIIWindow

final class ArtworkIsolationTests: XCTestCase {
    /// MediaPlayer calls the artwork handler on its access queue. A MainActor
    /// closure traps there with `dispatch_assert_queue_fail`.
    @MainActor
    func testArtworkRequestHandlerRunsOffTheMainThread() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let size = image.size
        nonisolated(unsafe) let artwork = PlaybackModel.makeArtwork(image)
        let done = expectation(description: "background artwork")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            let rendered = artwork.image(at: size)
            XCTAssertNotNil(rendered)
            if let rendered {
                XCTAssertGreaterThan(rendered.size.width, 0)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    /// Remote-command handlers are not pinned to the main thread. Assuming
    /// the main actor from a background queue traps.
    @MainActor
    func testRemoteCommandHandlerRunsOffTheMainThread() {
        let done = expectation(description: "remote command hopped to main")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            PlaybackModel.deliver(15) { value in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(value, 15)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }
}
