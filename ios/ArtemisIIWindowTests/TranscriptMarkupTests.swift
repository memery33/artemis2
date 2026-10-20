import SwiftUI
import XCTest
@testable import ArtemisIIWindow

final class TranscriptMarkupTests: XCTestCase {
    private var timeline: Timeline!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: TranscriptMarkupTests.self).url(forResource: "timeline", withExtension: "json"))
        timeline = try Timeline(data: Data(contentsOf: url))
    }

    func testShippedMarkersBecomeParentheticals() throws {
        let pattern = try NSRegularExpression(pattern: #"\[\[([^\[\]]*)\]\]|\[([^\[\]]+)\]"#)
        var counts: [String: Int] = [:]
        for line in timeline.lines {
            let ns = line.text as NSString
            let range = NSRange(location: 0, length: ns.length)
            for match in pattern.matches(in: line.text, range: range) {
                let token = ns.substring(with: match.range)
                counts[token, default: 0] += 1
                let group = match.range(at: 1).location != NSNotFound ? 1 : 2
                let inner = ns.substring(with: match.range(at: group))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertFalse(inner.isEmpty, token)
                XCTAssertEqual(TranscriptMarkup.plain(token), "(\(inner))")
                XCTAssertTrue(
                    TranscriptMarkup.matchesSearch(text: line.text, speaker: line.speaker, needle: inner),
                    line.text
                )
            }
            let plain = TranscriptMarkup.plain(line.text)
            XCTAssertFalse(plain.contains("["), line.text)
            XCTAssertFalse(plain.contains("]"), line.text)
            XCTAssertEqual(words(plain), words(line.text), line.text)
        }

        XCTAssertEqual(counts, [
            "[[shutter clicks]]": 30,
            "[[background voice]]": 14,
            "[[background voices]]": 8,
            "[[inaudible]]": 8,
            "[[background voices; inaudible; shutter clicks]]": 7,
            "[[background noise]]": 3,
            "[[rapid shutter clicks]]": 2,
            "[[overlapping comms]]": 2,
            "[[breathing]]": 1,
            "[[laughter]]": 1,
            "[[heavy breathing]]": 1,
        ])
    }

    func testHansenAsideStaysStoredAndReadsAsSpeechless() throws {
        let hansen = try XCTUnwrap(timeline.lines.first { $0.utc == "2026-04-06T19:33:39.116Z" })
        XCTAssertEqual(hansen.speaker, "Hansen")
        XCTAssertEqual(hansen.text, "[[background voice]]")
        XCTAssertEqual(TranscriptMarkup.plain(hansen.text), "(background voice)")
        XCTAssertEqual(
            TranscriptMarkup.runs(hansen.text),
            [TranscriptMarkup.Run(kind: .annotation, text: "background voice")]
        )
    }

    func testSpeechAroundAMarkerIsKept() throws {
        let line = try XCTUnwrap(timeline.lines.first { $0.text.contains("really important things") })
        XCTAssertEqual(
            TranscriptMarkup.plain(line.text),
            "These are really important things (shutter clicks) to know."
        )
        XCTAssertEqual(
            TranscriptMarkup.plain("[[shutter clicks]] [[background voices]] [[inaudible]]"),
            "(shutter clicks) (background voices) (inaudible)"
        )
        XCTAssertEqual(
            TranscriptMarkup.plain("Is it like right at the terminator or [[inaudible]]"),
            "Is it like right at the terminator or (inaudible)"
        )
        XCTAssertEqual(TranscriptMarkup.plain("[inaudible]"), "(inaudible)")
        XCTAssertEqual(
            TranscriptMarkup.plain("[[background voices; inaudible; shutter clicks]]"),
            "(background voices; inaudible; shutter clicks)"
        )
    }

    func testSearchMatchesWordsInsideMarkers() throws {
        let aside = "[[background voice]]"
        XCTAssertTrue(TranscriptMarkup.matchesSearch(text: aside, speaker: "Hansen", needle: "background"))
        XCTAssertTrue(TranscriptMarkup.matchesSearch(text: aside, speaker: "Hansen", needle: "voice"))
        XCTAssertTrue(TranscriptMarkup.matchesSearch(text: aside, speaker: "Hansen", needle: "Background Voice"))
        XCTAssertTrue(TranscriptMarkup.matchesSearch(text: aside, speaker: "Hansen", needle: "(background voice)"))
        XCTAssertFalse(TranscriptMarkup.matchesSearch(text: aside, speaker: "Hansen", needle: "shutter"))

        let spoken = try XCTUnwrap(timeline.lines.first { $0.text == "Need to get a memory card out." })
        XCTAssertTrue(TranscriptMarkup.matchesSearch(text: spoken.text, speaker: spoken.speaker, needle: "memory"))

        let mixed = try XCTUnwrap(timeline.lines.first { $0.text.contains("really important things") })
        XCTAssertTrue(TranscriptMarkup.matchesSearch(text: mixed.text, speaker: mixed.speaker, needle: "important"))
        XCTAssertTrue(TranscriptMarkup.matchesSearch(text: mixed.text, speaker: mixed.speaker, needle: "shutter clicks"))
    }

    @MainActor
    func testAnnotationRunIsItalic() {
        let styled = TranscriptMarkup.attributed(
            "Need [[background voice]] out",
            font: .body,
            color: .primary,
            annotationColor: .secondary
        )
        XCTAssertEqual(String(styled.characters), "Need (background voice) out")
        let runs = Array(styled.runs)
        XCTAssertEqual(runs.count, 3)
        let intent = AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self
        let ink = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self
        XCTAssertNil(runs[0][intent])
        XCTAssertEqual(runs[1][intent], InlinePresentationIntent.emphasized)
        XCTAssertEqual(String(runs[1].characters), "(background voice)")
        XCTAssertNotNil(runs[1][ink])
        XCTAssertNil(runs[2][intent])
    }

    private func words(_ text: String) -> [String] {
        var words: [String] = []
        var word = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "'" {
                word.append(character)
            } else if !word.isEmpty {
                words.append(word.lowercased())
                word = ""
            }
        }
        if !word.isEmpty {
            words.append(word.lowercased())
        }
        return words
    }
}
