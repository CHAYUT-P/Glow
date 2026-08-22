import Darwin
import Foundation

/// Helpers to terminate a shell and its entire process tree.
/// `LocalProcess.terminate()` only `kill(pid, SIGTERM)` the shell itself,
/// so foreground jobs (different pgid) and nested children (e.g. `npm -> node`)
/// are reparented to launchd and survive a tab close. This helper kills the
/// whole tree (foreground pgid + shell pgid + all descendants) with
/// SIGHUP -> SIGTERM -> SIGKILL.
enum KillTree {

    // MARK: - Query

    /// Whether `pid` has a running foreground job.
    /// True when foreground pgid differs from shell pgid, or shell has children.
    static func hasRunningJob(pid: pid_t, fd: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        if fd >= 0 {
            let fg = tcgetpgrp(fd)
            if fg > 1 && fg != pid {
                return true
            }
        }
        return !childPids(of: pid).isEmpty
    }

    /// Direct + indirect children of `pid` (excluding `pid` itself).
    static func childPids(of pid: pid_t) -> [pid_t] {
        collectTree(root: pid).filter { $0 != pid }
    }

    // MARK: - Kill

    /// Best-effort tree kill: SIGHUP -> SIGTERM immediately, SIGKILL after 0.8s
    /// if pids still alive. Safe to call on main thread; SIGKILL fallback is async.
    static func terminate(pid: pid_t, fd: Int32) {
        guard pid > 0 else { return }
        guard kill(pid, 0) == 0 else { return }

        let tree = collectTree(root: pid)
        // tree always contains at least [pid]
        var pgids = Set<pid_t>()
        for p in tree {
            let pg = getpgid(p)
            if pg > 1 { pgids.insert(pg) }
        }
        var fgPGID: pid_t = -1
        if fd >= 0 {
            let fg = tcgetpgrp(fd)
            if fg > 1 {
                fgPGID = fg
                pgids.insert(fg)
            }
        }

        // 1. Hangup - traditional terminal close
        for pg in pgids { kill(-pg, SIGHUP) }
        for p in tree { kill(p, SIGHUP) }
        if fgPGID > 1 {
            kill(-fgPGID, SIGHUP)
            kill(fgPGID, SIGHUP)
        }

        // 2. Terminate - give processes a chance to exit cleanly
        for pg in pgids { kill(-pg, SIGTERM) }
        for p in tree { kill(p, SIGTERM) }
        if fgPGID > 1 {
            kill(-fgPGID, SIGTERM)
            kill(fgPGID, SIGTERM)
        }

        // 3. Second pass shortly after, in case a child spawned between ps and kill
        let pidCopy = pid
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15) {
            let tree2 = collectTree(root: pidCopy)
            for p in tree2 where kill(p, 0) == 0 {
                kill(p, SIGHUP)
                kill(p, SIGTERM)
            }
            for pg in Set(tree2.map { getpgid($0) }.filter { $0 > 1 }) {
                if kill(-pg, 0) == 0 {
                    kill(-pg, SIGHUP)
                    kill(-pg, SIGTERM)
                }
            }
        }

        // 4. Kill fallback async
        let treeCopy = tree
        let pgidsCopy = pgids
        let fgCopy = fgPGID
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) {
            for p in treeCopy.reversed() {
                if kill(p, 0) == 0 {
                    kill(p, SIGKILL)
                }
            }
            for pg in pgidsCopy {
                // kill(-pg,0) checks if any process in group exists
                if kill(-pg, 0) == 0 {
                    kill(-pg, SIGKILL)
                }
            }
            if fgCopy > 1 {
                if kill(-fgCopy, 0) == 0 { kill(-fgCopy, SIGKILL) }
                if kill(fgCopy, 0) == 0 { kill(fgCopy, SIGKILL) }
            }
        }
    }

    // MARK: - Private

    /// Collect `root` + all descendants via `ps -ax -o pid=,ppid=`.
    /// Synchronous but fast (~10ms) and avoids private proc_info APIs.
    static func collectTree(root: pid_t) -> [pid_t] {
        // Fallback: if ps fails, at least return [root]
        guard let map = psPidToPPid() else { return [root] }

        var result: [pid_t] = [root]
        var queue: [pid_t] = [root]
        var visited = Set<pid_t>([root])

        while !queue.isEmpty {
            let cur = queue.removeFirst()
            for (pid, ppid) in map where ppid == cur && !visited.contains(pid) {
                visited.insert(pid)
                result.append(pid)
                queue.append(pid)
            }
        }
        return result
    }

    private static func psPidToPPid() -> [pid_t: pid_t]? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-ax", "-o", "pid=,ppid="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var map: [pid_t: pid_t] = [:]
        for line in text.split(separator: "\n") {
            // "  123   1" -> [123,1]
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2,
                  let pid = pid_t(parts[0]),
                  let ppid = pid_t(parts[1]) else { continue }
            map[pid] = ppid
        }
        return map
    }
}
