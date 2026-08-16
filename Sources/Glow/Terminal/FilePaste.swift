import Foundation

/// Builds the text inserted into the terminal when files are dropped on a
/// pane or picked with the attach button: each path, shell-escaped, joined
/// with a space. Only whitespace and backslashes are escaped, matching what
/// iTerm2 pastes for a dropped file, so the result stays readable to both
/// shells and Grok's `@path` mentions.
enum FilePaste {
    static func text(for urls: [URL]) -> String {
        urls.map { escaped($0.path) }.joined(separator: " ")
    }

    private static func escaped(_ path: String) -> String {
        var out = ""
        for ch in path {
            switch ch {
            case "\\", " ", "\t":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }
}
