import Foundation
import SwiftData

/// A post-class plan and the lecture it belongs to.
public struct PostclassPlan: Codable, Hashable, Sendable, Identifiable {
    public var lectureID: String
    public var plan: DailyPlan

    public var id: String { lectureID }
    public var courseID: String { PostclassQuiz.courseID(fromLectureID: lectureID) }

    public init(lectureID: String, plan: DailyPlan) {
        self.lectureID = lectureID
        self.plan = plan
    }
}

/// Keeps the post-class plans that have landed, apart from Today's plan, in
/// user defaults (mirrored to other devices like the daily plan).
public final class PostclassPlanStore: @unchecked Sendable {
    public static let shared = PostclassPlanStore()
    public static let defaultsKey = "postclassPlansData"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every stored plan that hasn't expired, oldest lecture first.
    public func plans(at now: Date = .now) -> [PostclassPlan] {
        lock.withLock { load() }
            .filter { !$0.plan.isExpired(at: now) }
            .sorted { $0.plan.header.createdAt < $1.plan.header.createdAt }
    }

    /// Plans with prompts left to answer on this device.
    public func pending(in context: ModelContext, supportsCodeExecution: Bool, at now: Date = .now) -> [PostclassPlan] {
        plans(at: now).filter {
            !((try? PostclassQuiz.items(for: $0.plan, in: context, supportsCodeExecution: supportsCodeExecution)) ?? []).isEmpty
        }
    }

    /// Adds or replaces the plan for its lecture.
    public func upsert(_ entry: PostclassPlan) {
        lock.withLock {
            var all = load().filter { $0.lectureID != entry.lectureID }
            all.append(entry)
            save(all)
        }
    }

    public func remove(lectureID: String) {
        lock.withLock {
            let all = load()
            let kept = all.filter { $0.lectureID != lectureID }
            if kept.count != all.count { save(kept) }
        }
    }

    /// Drops expired plans.
    public func removeExpired(at now: Date = .now) {
        lock.withLock {
            let all = load()
            let kept = all.filter { !$0.plan.isExpired(at: now) }
            if kept.count != all.count { save(kept) }
        }
    }

    public func reset() {
        lock.withLock { defaults.removeObject(forKey: Self.defaultsKey) }
    }

    private func load() -> [PostclassPlan] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([PostclassPlan].self, from: data)) ?? []
    }

    private func save(_ plans: [PostclassPlan]) {
        if plans.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(plans) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
