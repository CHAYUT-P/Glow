import Foundation

/// Reads the current git branch for a folder straight from `.git/HEAD` —
/// no `git` subprocess, so it is cheap enough to run on every cwd change.
enum GitBranch {
    /// Branch name, short commit hash for a detached HEAD, or nil when
    /// `path` is not inside a git work tree.
    static func current(at path: String) -> String? {
        guard let gitDir = gitDirectory(containing: path),
              let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
        else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: ") {
            let ref = line.dropFirst(5)
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : String(ref)
        }
        return line.isEmpty ? nil : String(line.prefix(7))
    }

    /// Walks up from `path` to the nearest `.git` — a directory for normal
    /// repos, or a `gitdir:` pointer file for worktrees and submodules.
    private static func gitDirectory(containing path: String) -> URL? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                if isDir.boolValue { return dotGit }
                if let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
                   pointer.hasPrefix("gitdir: ") {
                    let target = pointer.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
                    return URL(fileURLWithPath: target, relativeTo: dir).standardizedFileURL
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }
}
