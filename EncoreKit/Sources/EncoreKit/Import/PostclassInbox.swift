import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.amierlorenz.Encore", category: "handoff")

/// Handles `to-encore/postclass-<lectureId>.json` files.
///
/// - Waits (leaves the file) while the plan's `importBatch` hasn't been applied.
/// - Otherwise stores the plan and schedules its notifications once.
/// - Deletes the file when the quiz is answered or the plan expires (the 02:00 takeover).
/// - Moves an unreadable or non-post-class file to `failed/` with `<lectureId>.error.txt`.
@MainActor
public struct PostclassInbox {
    public enum Outcome: Equatable, Sendable {
        case served, waiting, answered, expired, failed
    }

    public var handoffFolder: HandoffFolder
    public var context: ModelContext
    public var store: PostclassPlanStore
    public var notifications: PostclassNotifications

    public init(
        handoffFolder: HandoffFolder,
        context: ModelContext,
        store: PostclassPlanStore = .shared,
        notifications: PostclassNotifications = PostclassNotifications()
    ) {
        self.handoffFolder = handoffFolder
        self.context = context
        self.store = store
        self.notifications = notifications
    }

    @discardableResult
    public func process(_ url: URL, now: Date = .now) -> Outcome {
        let name = url.lastPathComponent
        let lectureID = PostclassQuiz.lectureID(fromFileName: name) ?? url.deletingPathExtension().lastPathComponent

        let plan: DailyPlan
        do {
            plan = try JSONDecoder().decode(DailyPlan.self, from: Data(contentsOf: url))
            guard plan.kind == "postclass" else {
                throw PostclassError("Expected kind 'postclass', got '\(plan.kind)'")
            }
        } catch {
            moveToFailed(url, lectureID: lectureID, error: error)
            return .failed
        }

        let entry = PostclassPlan(lectureID: lectureID, plan: plan)
        if plan.isExpired(at: now) {
            close(entry, file: url)
            return .expired
        }
        if let batch = plan.importBatch, !isApplied(batch) {
            logger.info("\(name) waits for batch \(batch)")
            return .waiting
        }
        if (try? PostclassQuiz.isAnswered(plan, in: context)) == true {
            close(entry, file: url)
            return .answered
        }
        store.upsert(entry)
        notifications.planLanded(entry, courseName: courseName(for: entry), at: now)
        return .served
    }

    private func close(_ entry: PostclassPlan, file: URL) {
        try? FileManager.default.removeItem(at: file)
        store.remove(lectureID: entry.lectureID)
        notifications.quizClosed(lectureID: entry.lectureID)
    }

    private func isApplied(_ batchID: String) -> Bool {
        let descriptor = FetchDescriptor<AppliedBatch>()
        guard let batches = try? context.fetch(descriptor) else { return false }
        let stripped = batchID.hasPrefix("import-") ? String(batchID.dropFirst(7)) : batchID
        return batches.contains { applied in
            let appliedStripped = applied.batchID.hasPrefix("import-") ? String(applied.batchID.dropFirst(7)) : applied.batchID
            return applied.batchID == batchID || appliedStripped == stripped
        }
    }

    /// Removes answered post-class quizzes from the store, cancels reminder notifications, and deletes their hand-off files.
    public static func cleanupAnswered(
        in context: ModelContext,
        handoffFolder: HandoffFolder = HandoffFolder(),
        store: PostclassPlanStore = .shared,
        notifications: PostclassNotifications = PostclassNotifications()
    ) {
        for entry in store.plans() {
            if (try? PostclassQuiz.isAnswered(entry.plan, in: context)) == true {
                let fileURL = handoffFolder.toEncoreURL.appending(path: "postclass-\(entry.lectureID).json")
                try? FileManager.default.removeItem(at: fileURL)
                store.remove(lectureID: entry.lectureID)
                notifications.quizClosed(lectureID: entry.lectureID)
            }
        }
    }

    private func courseName(for entry: PostclassPlan) -> String {
        let id = entry.courseID
        let course = try? context.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.externalID == id })).first
        return course.map { $0.shortName ?? $0.name } ?? id
    }

    private func moveToFailed(_ url: URL, lectureID: String, error: any Error) {
        logger.error("Post-class plan \(url.lastPathComponent) failed: \(error)")
        let fm = FileManager.default
        let dest = handoffFolder.failedURL.appending(path: url.lastPathComponent)
        try? fm.removeItem(at: dest)
        try? fm.moveItem(at: url, to: dest)
        let message = (error as? PostclassError)?.message ?? String(describing: error)
        try? message.write(to: handoffFolder.failedURL.appending(path: "\(lectureID).error.txt"), atomically: true, encoding: .utf8)
    }

    struct PostclassError: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }
}
