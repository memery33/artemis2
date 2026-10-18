import Foundation

enum DemoPath {
    /// A timeline path must stay inside the bundled DemoData folder.
    static func isContained(_ relative: String) -> Bool {
        guard !relative.isEmpty,
              !relative.hasPrefix("/"),
              !relative.hasPrefix("~"),
              !relative.contains("\\"),
              !relative.contains("\0") else {
            return false
        }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".."
        }
    }
}
