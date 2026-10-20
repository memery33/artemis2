import Foundation

/// Shared with the widget. ActivityKit conformance lives next to the system client and in the widget, so this file does not import ActivityKit.
struct FlybyActivityAttributes: Codable, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var progress: Double
        var nextMilestone: String
        var speaker: String
        /// Absolute mission UTC, `at HH:mm:ss UTC`, from the last push. The lock screen shows this string.
        /// VoiceOver reads it. It is not a `Text(timerInterval:)`.
        var clock: String
        var playing: Bool
        /// Elapsed since the span start, from the same push as `clock`. `m:ss into the flyby` or `m:ss into the cab run`.
        /// Missing on an activity written by an older build, so decode supplies an empty string.
        var elapsedText: String

        init(
            progress: Double,
            nextMilestone: String,
            speaker: String,
            clock: String,
            playing: Bool,
            elapsedText: String
        ) {
            self.progress = progress
            self.nextMilestone = nextMilestone
            self.speaker = speaker
            self.clock = clock
            self.playing = playing
            self.elapsedText = elapsedText
        }

        private enum CodingKeys: String, CodingKey {
            case progress, nextMilestone, speaker, clock, playing, elapsedText
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            progress = try container.decode(Double.self, forKey: .progress)
            nextMilestone = try container.decode(String.self, forKey: .nextMilestone)
            speaker = try container.decode(String.self, forKey: .speaker)
            clock = try container.decodeIfPresent(String.self, forKey: .clock) ?? ""
            playing = try container.decodeIfPresent(Bool.self, forKey: .playing) ?? false
            elapsedText = try container.decodeIfPresent(String.self, forKey: .elapsedText) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(progress, forKey: .progress)
            try container.encode(nextMilestone, forKey: .nextMilestone)
            try container.encode(speaker, forKey: .speaker)
            try container.encode(clock, forKey: .clock)
            try container.encode(playing, forKey: .playing)
            try container.encode(elapsedText, forKey: .elapsedText)
        }
    }

    /// Lock Screen and Dynamic Island copy. Nil while the recording is playing.
    static func pausedLabel(playing: Bool) -> String? {
        playing ? nil : "Paused"
    }

    var title: String
}
