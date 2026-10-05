import Foundation

/// Builds the text inserted into the terminal when files are dropped on a
/// pane or picked with the attach button: each path, shell-escaped, joined
/// with a space. Every character outside a conservative safe set is
/// backslash-escaped — a filename containing `;`, `$()`, spaces or quotes
/// must paste as data, never as shell syntax (matching what Terminal.app
/// and iTerm2 insert for a dropped file).
enum FilePaste {
    static func text(for urls: [URL]) -> String {
        urls.map { escaped($0.path) }.joined(separator: " ")
    }

    /// Characters allowed unescaped in a pasted path: alphanumerics plus the
    /// punctuation that's common in filenames and inert to zsh/bash
    /// (`/` `.` `_` `-` `~` `@` `+` `:` `=` `,` `%`).
    private static let safeCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~/@+-:=,%"
    )

    private static func escaped(_ path: String) -> String {
        // Backslash before a control character is not a literal escape — a
        // backslash-newline is a line continuation that silently deletes the
        // newline and pastes a wrong path. ANSI-C quote those paths instead:
        // `$'a\nb'` stays one pasted line and the name survives exactly.
        if path.contains(where: isControl) {
            return ansiQuoted(path)
        }
        var out = ""
        for ch in path {
            if safeCharacters.contains(ch) {
                out.append(ch)
            } else {
                out.append("\\")
                out.append(ch)
            }
        }
        return out
    }

    private static func isControl(_ ch: Character) -> Bool {
        guard let value = ch.asciiValue else { return false }
        return value < 0x20 || value == 0x7F
    }

    /// `$'...'` ANSI-C quoting for paths containing control characters:
    /// everything is literal except `\`, `'`, and the control characters
    /// themselves, which use the standard backslash escapes.
    private static func ansiQuoted(_ path: String) -> String {
        var out = "$'"
        for ch in path {
            switch ch {
            case "\\": out += "\\\\"
            case "'": out += "\\'"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{0B}": out += "\\v"
            case "\u{0C}": out += "\\f"
            case "\u{07}": out += "\\a"
            case "\u{08}": out += "\\b"
            case "\u{1B}": out += "\\e"
            default:
                if isControl(ch), let value = ch.asciiValue {
                    out += String(format: "\\x%02x", value)
                } else {
                    out.append(ch)
                }
            }
        }
        return out + "'"
    }
}
