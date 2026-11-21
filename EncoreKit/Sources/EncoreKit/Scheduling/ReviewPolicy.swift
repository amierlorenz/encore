import Foundation

/// Wraps a ``Scheduler`` with the app's study rules.
///
/// - **Practice mode:** passing a concept that isn't due leaves its schedule
///   alone, because early success mostly reflects short-term memory. Failing it
///   still reschedules, pulling the due date in.
/// - **Post-class quiz:** a concept introduced in one is first due at least a
///   day later; re-asking an introduced, not-due concept in the quiz leaves its
///   schedule alone; and its first review after that leaves ease alone.
/// - **Exam cap:** for concepts on an upcoming exam, the interval is at most
///   half the days remaining, so each concept comes up at least twice in the
///   final week and never after the exam.
public struct ReviewPolicy: Sendable {
    public var scheduler: any Scheduler
    public var calendar: Calendar
    /// Course interval caps (courseID -> max days), e.g. 30 days while a course is active.
    public var intervalCaps: [String: Int]

    public init(
        scheduler: any Scheduler = SM2Scheduler(),
        calendar: Calendar = .current,
        intervalCaps: [String: Int] = [:]
    ) {
        self.scheduler = scheduler
        self.calendar = calendar
        self.intervalCaps = intervalCaps
    }

    public struct Context: Sendable {
        public var mode: StudyMode
        public var isNew: Bool
        public var wasDue: Bool
        /// Dates of exams covering the concept; past dates are ignored.
        public var examDates: [Date]
        public var courseID: String?
        public var intervalCap: Double?
        public var postclass: PostclassStep?
        public var now: Date

        public init(
            mode: StudyMode,
            isNew: Bool,
            wasDue: Bool,
            examDates: [Date] = [],
            courseID: String? = nil,
            intervalCap: Double? = nil,
            postclass: PostclassStep? = nil,
            now: Date
        ) {
            self.mode = mode
            self.isNew = isNew
            self.wasDue = wasDue
            self.examDates = examDates
            self.courseID = courseID
            self.intervalCap = intervalCap
            self.postclass = postclass
            self.now = now
        }
    }

    /// Where an answer sits relative to a post-class quiz.
    public enum PostclassStep: Sendable {
        /// Answered in the post-class quiz itself.
        case quiz
        /// The first scheduled review of a concept the quiz introduced.
        case firstReview
    }

    public func next(_ state: ScheduleState, grade: Grade, context: Context) -> ScheduleState {
        if context.mode == .practice, !context.isNew, !context.wasDue, grade.isPass {
            return state
        }
        if context.postclass == .quiz, !context.isNew, !context.wasDue {
            return state
        }
        var next = scheduler.schedule(state, grade: grade, now: context.now, calendar: calendar)
        if context.postclass == .firstReview {
            next.ease = state.ease
        }
        let effectiveCap = context.courseID.flatMap { intervalCaps[$0] }.map(Double.init) ?? context.intervalCap
        next = capped(next, examDates: context.examDates, intervalCap: effectiveCap, now: context.now)
        if context.postclass == .quiz, context.isNew {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: context.now))!
            if (next.dueDate ?? .distantPast) < tomorrow {
                next.dueDate = tomorrow
                next.intervalDays = max(1, next.intervalDays)
            }
        }
        return next
    }

    func capped(_ state: ScheduleState, examDates: [Date], intervalCap: Double? = nil, now: Date) -> ScheduleState {
        let today = calendar.startOfDay(for: now)
        var capped = state

        // Exam cap: interval is at most half the days remaining
        let daysLeft = examDates
            .compactMap { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0)).day }
            .filter { $0 > 0 }
            .min()
        if let daysLeft {
            let examCap = max(1, Double(daysLeft / 2))
            if capped.intervalDays > examCap {
                capped.intervalDays = examCap
                capped.dueDate = calendar.date(byAdding: .day, value: Int(examCap), to: today)
            }
        }

        // Course interval cap: e.g. 30 days while a course is active
        if let intervalCap, capped.intervalDays > intervalCap {
            capped.intervalDays = intervalCap
            capped.dueDate = calendar.date(byAdding: .day, value: Int(intervalCap), to: today)
        }

        return capped
    }
}
