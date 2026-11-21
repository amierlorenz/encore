import Foundation
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.amierlorenz.Encore", category: "postclass")

/// A local notification to deliver now (`date == nil`) or at `date`.
public struct PostclassNotification: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var date: Date?
}

/// Delivers and cancels local notifications.
public protocol NotificationScheduling: Sendable {
    func schedule(_ notification: PostclassNotification)
    func cancel(ids: [String])
}

/// The two post-class notifications from Articulate's "Daily rhythm": "post-class
/// quiz ready" when the plan lands, and one mid-afternoon reminder if it's still
/// unanswered. Each is scheduled once per lecture.
public struct PostclassNotifications: Sendable {
    /// Local time of the reminder.
    public static let reminderHour = 15
    static let notifiedKey = "postclassNotifiedLectures"

    public var scheduler: any NotificationScheduling
    public var calendar: Calendar
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(
        scheduler: any NotificationScheduling = UserNotificationScheduler(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.calendar = calendar
    }

    public static func readyID(_ lectureID: String) -> String { "postclass.ready.\(lectureID)" }
    public static func reminderID(_ lectureID: String) -> String { "postclass.reminder.\(lectureID)" }

    /// Schedules both notifications the first time a lecture's plan lands; later calls do nothing.
    public func planLanded(_ entry: PostclassPlan, courseName: String, at now: Date = .now) {
        var notified = Set(defaults.stringArray(forKey: Self.notifiedKey) ?? [])
        guard notified.insert(entry.lectureID).inserted else { return }
        defaults.set(notified.sorted(), forKey: Self.notifiedKey)

        let count = entry.plan.new.count
        scheduler.schedule(PostclassNotification(
            id: Self.readyID(entry.lectureID),
            title: "Post-class quiz ready",
            body: "\(courseName): \(count) \(count == 1 ? "question" : "questions") from today's class.",
            date: nil
        ))
        if let reminder = reminderDate(for: entry.plan, after: now) {
            scheduler.schedule(PostclassNotification(
                id: Self.reminderID(entry.lectureID),
                title: "Post-class quiz waiting",
                body: "\(courseName)'s quiz is still open until tonight.",
                date: reminder
            ))
        }
    }

    /// Cancels the reminder once the quiz is answered or has expired.
    public func quizClosed(lectureID: String) {
        scheduler.cancel(ids: [Self.reminderID(lectureID)])
    }

    /// Resets the record of notified lectures (e.g. for testing).
    public func reset() {
        defaults.removeObject(forKey: Self.notifiedKey)
    }

    /// Mid-afternoon on the plan's day, if that's still ahead and before the plan expires.
    func reminderDate(for plan: DailyPlan, after now: Date) -> Date? {
        guard let start = plan.availableAt(calendar: calendar),
              let date = calendar.date(bySettingHour: Self.reminderHour, minute: 0, second: 0, of: start),
              date > now, date < plan.validUntil
        else { return nil }
        return date
    }
}

/// Schedules notifications with `UNUserNotificationCenter`, asking for permission first.
public struct UserNotificationScheduler: NotificationScheduling {
    public init() {}

    public func schedule(_ notification: PostclassNotification) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.body
                content.sound = .default
                let trigger = notification.date.map { date in
                    UNCalendarNotificationTrigger(
                        dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                        repeats: false
                    )
                }
                try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
            } catch {
                logger.error("Scheduling \(notification.id) failed: \(error)")
            }
        }
    }

    public func cancel(ids: [String]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
