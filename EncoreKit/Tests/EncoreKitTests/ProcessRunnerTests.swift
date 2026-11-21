#if os(macOS)
import Foundation
@testable import EncoreKit
import Testing

struct ProcessRunnerTests {
    /// Cancelling the calling task must kill the child and anything it spawned,
    /// not leave them spinning under launchd.
    @Test(.timeLimit(.minutes(1)))
    func cancellationKillsChildAndGrandchild() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "encore-pr-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The shell writes its own PID and a backgrounded busy loop's PID, then spins itself.
        let script = "(while :; do :; done) & echo $$ $! > pids.tmp; mv pids.tmp pids; while :; do :; done"
        let task = Task {
            try await ProcessRunner.run("/bin/sh", ["-c", script], in: directory, timeout: .seconds(60))
        }

        let pidsURL = directory.appending(path: "pids")
        var pids: [pid_t] = []
        for _ in 0..<200 where pids.isEmpty {
            if let text = try? String(contentsOf: pidsURL, encoding: .utf8) {
                pids = text.split(separator: " ").compactMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            if pids.isEmpty { try await Task.sleep(for: .milliseconds(25)) }
        }
        try #require(pids.count == 2)
        #expect(pids.allSatisfy(Self.isAlive))

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        // The grandchild is reaped by launchd, so give it a moment to disappear.
        for _ in 0..<100 where pids.contains(where: Self.isAlive) {
            try await Task.sleep(for: .milliseconds(20))
        }
        for pid in pids {
            #expect(!Self.isAlive(pid), "pid \(pid) still running")
        }
    }

    @Test func cancelledBeforeLaunchDoesNotRun() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "encore-pr-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ProcessRunner.run("/bin/sh", ["-c", "touch ran"], in: directory, timeout: .seconds(5))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "ran").path()))
    }

    @Test func timeoutStillReportsTimedOut() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "encore-pr-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try await ProcessRunner.run("/bin/sh", ["-c", "while :; do :; done"], in: directory, timeout: .milliseconds(200))
        #expect(output.timedOut)
    }

    @Test func timeoutKillsGrandchild() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "encore-pr-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The shell exits on SIGTERM; its background loop ignores SIGTERM.
        let script = "(trap '' TERM; while :; do :; done) & echo $! > pid; while :; do :; done"
        let output = try await ProcessRunner.run("/bin/sh", ["-c", script], in: directory, timeout: .milliseconds(300))
        #expect(output.timedOut)
        let pid = try #require(pid_t(String(contentsOf: directory.appending(path: "pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0..<100 where Self.isAlive(pid) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!Self.isAlive(pid), "grandchild \(pid) still running")
    }

    private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }
}
#endif
