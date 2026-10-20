import SwiftUI

/// A speaker visitors can read. Empty, whitespace, and a token with no letters are no speaker.
/// The stray backtick in the bundled transcript stays stored; it is not a name.
enum SpeakerLabel {
    static func display(_ raw: String) -> String? {
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLetter: Bool = trimmed.contains { (character: Character) -> Bool in
            character.isLetter
        }
        guard hasLetter else { return nil }
        return trimmed
    }

    /// Lines header. The time stands alone when there is no readable speaker.
    static func heading(speaker: String, clock: String) -> String {
        guard let name: String = display(speaker) else { return clock }
        return "\(name) · \(clock)"
    }
}

/// Display reading of a stored transcript line.
/// `[[note]]` and `[note]` are non-speech. The stored line is not rewritten.
enum TranscriptMarkup {
    struct Run: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case speech
            case annotation
        }

        var kind: Kind
        var text: String
    }

    /// Speech stays as stored. Each annotation is the note inside the brackets, trimmed.
    static func runs(_ source: String) -> [Run] {
        var result: [Run] = []
        var speech = ""
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "[", let marker = marker(in: source, at: index) {
                if !speech.isEmpty {
                    result.append(Run(kind: .speech, text: speech))
                    speech = ""
                }
                if !marker.inner.isEmpty {
                    result.append(Run(kind: .annotation, text: marker.inner))
                }
                index = marker.next
            } else {
                speech.append(source[index])
                index = source.index(after: index)
            }
        }
        if !speech.isEmpty {
            result.append(Run(kind: .speech, text: speech))
        }
        return result
    }

    /// Visitor reading. An annotation is `(note)`.
    static func plain(_ source: String) -> String {
        runs(source).map { run in
            switch run.kind {
            case .speech:
                return run.text
            case .annotation:
                return "(\(run.text))"
            }
        }.joined()
    }

    /// Lines search. The stored words match, including words inside a marker, and so does the visible parenthetical.
    static func matchesSearch(text: String, speaker: String, needle: String) -> Bool {
        let query = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return true }
        return text.localizedCaseInsensitiveContains(query)
            || plain(text).localizedCaseInsensitiveContains(query)
            || speaker.localizedCaseInsensitiveContains(query)
    }

    /// Speech uses `font` and `color`. An annotation is italic, in `annotationColor`, wrapped as `(note)`.
    /// Attributes are written out as SwiftUI and Foundation keys. The widget and the app both compile this file,
    /// and a bare `part.font` / `part.foregroundColor` / `.italic` lookup is ambiguous there.
    @MainActor
    static func attributed(
        _ source: String,
        font: SwiftUI.Font,
        color: SwiftUI.Color,
        annotationColor: SwiftUI.Color
    ) -> AttributedString {
        var result = AttributedString()
        for run in runs(source) {
            switch run.kind {
            case .speech:
                result.append(styled(run.text, font: font, color: color, intent: nil))
            case .annotation:
                let face: SwiftUI.Font = font.italic()
                let intent: InlinePresentationIntent = InlinePresentationIntent.emphasized
                result.append(styled("(\(run.text))", font: face, color: annotationColor, intent: intent))
            }
        }
        return result
    }

    @MainActor
    private static func styled(
        _ text: String,
        font: SwiftUI.Font,
        color: SwiftUI.Color,
        intent: InlinePresentationIntent?
    ) -> AttributedString {
        var part = AttributedString(text)
        let face: SwiftUI.Font = font
        let ink: SwiftUI.Color = color
        part[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = face
        part[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = ink
        if let intent {
            let presentation: InlinePresentationIntent = intent
            part[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self] = presentation
        }
        return part
    }

    private struct Marker {
        var inner: String
        var next: String.Index
    }

    /// `[[note]]` or `[note]`. A broken bracket stays speech.
    private static func marker(in source: String, at start: String.Index) -> Marker? {
        guard source[start] == "[" else { return nil }
        let afterFirst = source.index(after: start)
        guard afterFirst < source.endIndex else { return nil }
        let doubled = source[afterFirst] == "["
        let contentStart = doubled ? source.index(after: afterFirst) : afterFirst
        var cursor = contentStart
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "[" { return nil }
            if character == "]" {
                if doubled {
                    let second = source.index(after: cursor)
                    guard second < source.endIndex, source[second] == "]" else { return nil }
                    let inner = String(source[contentStart..<cursor])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return Marker(inner: inner, next: source.index(after: second))
                }
                if cursor == contentStart { return nil }
                let inner = String(source[contentStart..<cursor])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Marker(inner: inner, next: source.index(after: cursor))
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }
}

/// One transcript line. Annotations are italic and use `annotationColor`.
struct TranscriptLineText: View {
    var text: String
    var font: Font
    var color: Color
    var annotationColor: Color
    var lineLimit: Int? = nil
    var minimumScaleFactor: CGFloat = 1

    var body: some View {
        Text(TranscriptMarkup.attributed(text, font: font, color: color, annotationColor: annotationColor))
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
            .multilineTextAlignment(.leading)
            .accessibilityLabel(TranscriptMarkup.plain(text))
    }
}
