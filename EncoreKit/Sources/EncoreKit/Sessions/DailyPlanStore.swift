import Foundation
import OSLog

/// Manages loading, caching, expiration, and syncing of Articulate's daily plan.
public final class DailyPlanStore: @unchecked Sendable {
    public static let shared = DailyPlanStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var _currentPlan: DailyPlan?
    private var _planIdSeen: String?
    private var _planCreatedAt: Date?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFromDefaults()
    }

    /// The active plan for today, or `nil` if missing or expired (`now >= validUntil`).
    public func activePlan(at now: Date = .now) -> DailyPlan? {
        lock.lock()
        defer { lock.unlock() }
        guard let plan = _currentPlan else { return nil }
        if plan.isExpired(at: now) {
            return nil
        }
        return plan
    }

    /// The latest plan id seen (stored for export state).
    public var planIdSeen: String? {
        lock.lock()
        defer { lock.unlock() }
        return _planIdSeen
    }

    /// The header created_at of the latest plan seen (kept for stale-plan banner).
    public var planCreatedAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _planCreatedAt
    }

    /// Applies a newly received or loaded plan.
    public func applyPlan(_ plan: DailyPlan, at now: Date = .now) {
        lock.lock()
        defer { lock.unlock() }
        _currentPlan = plan
        _planIdSeen = plan.header.id
        _planCreatedAt = plan.header.createdAt
        saveToDefaults()
    }

    /// Loads and applies a plan from raw JSON data.
    @discardableResult
    public func loadFromData(_ data: Data, at now: Date = .now) throws -> DailyPlan {
        let plan = try JSONDecoder().decode(DailyPlan.self, from: data)
        applyPlan(plan, at: now)
        return plan
    }

    /// Loads and applies a plan from a JSON file.
    @discardableResult
    public func loadFromFile(at url: URL, at now: Date = .now) throws -> DailyPlan {
        let data = try Data(contentsOf: url)
        return try loadFromData(data, at: now)
    }

    /// Default path to the plan in the hand-off folder on macOS.
    public static var defaultHandoffPlanURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Encore/Handoff/to-encore/plan.json")
            ?? URL(filePath: "/tmp/Encore/Handoff/to-encore/plan.json")
    }

    /// Reads `to-encore/plan.json` from the hand-off folder on macOS if present and valid.
    @discardableResult
    public func loadFromHandoffFolder(handoffURL: URL? = nil, at now: Date = .now) -> DailyPlan? {
        let url = handoffURL ?? Self.defaultHandoffPlanURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let plan = try JSONDecoder().decode(DailyPlan.self, from: data)
            if plan.isExpired(at: now) {
                return nil
            }
            applyPlan(plan, at: now)
            return plan
        } catch {
            return nil
        }
    }

    /// Clears any cached plan (e.g. for testing or reset).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _currentPlan = nil
        _planIdSeen = nil
        _planCreatedAt = nil
        defaults.removeObject(forKey: "dailyPlanData")
        defaults.removeObject(forKey: "planIdSeen")
        defaults.removeObject(forKey: "planCreatedAt")
    }

    private func saveToDefaults() {
        guard let plan = _currentPlan else { return }
        if let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: "dailyPlanData")
        }
        if let id = _planIdSeen {
            defaults.set(id, forKey: "planIdSeen")
        }
        if let createdAt = _planCreatedAt {
            defaults.set(createdAt.timeIntervalSince1970, forKey: "planCreatedAt")
        }
    }

    public func loadFromDefaults() {
        if let data = defaults.data(forKey: "dailyPlanData"),
           let plan = try? JSONDecoder().decode(DailyPlan.self, from: data) {
            _currentPlan = plan
        }
        if let id = defaults.string(forKey: "planIdSeen") {
            _planIdSeen = id
        }
        let timestamp = defaults.double(forKey: "planCreatedAt")
        if timestamp > 0 {
            _planCreatedAt = Date(timeIntervalSince1970: timestamp)
        }
    }
}
