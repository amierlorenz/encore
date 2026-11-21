import Foundation
import Observation
import SwiftData

/// Runs a study session: serves prompts in order, records answers, and
/// re-asks failed concepts once later in the session.
@MainActor
@Observable
public final class SessionEngine {
    /// How many items later a failed concept comes back.
    public static let requeueGap = 4

    public let sessionID = UUID()
    public let config: SessionConfig
    public let startedAt: Date
    public let sessionKind: String
    public private(set) var queue: [SessionItem]
    public private(set) var position = 0
    public private(set) var summary = SessionSummary()
    public private(set) var isFinished = false

    public var isCalibrated: Bool {
        sessionKind == "plan"
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let recorder: ReviewRecorder
    @ObservationIgnored private let builder: SessionBuilder
    @ObservationIgnored private let record: StudySession
    @ObservationIgnored private var concepts: [String: Concept]
    @ObservationIgnored private var prompts: [String: Prompt]
    @ObservationIgnored private var requeued: Set<String> = []
    @ObservationIgnored private var undoStack: [AnswerSnapshot] = []

    /// Everything an answer changes, captured just before it, so the answer
    /// can be taken back.
    private struct AnswerSnapshot {
        let log: ReviewLog
        let concept: Concept
        let schedule: ScheduleState
        let introducedAt: Date?
        let prompt: Prompt
        let promptLastShownAt: Date?
        let queue: [SessionItem]
        let position: Int
        let summary: SessionSummary
        let requeued: Set<String>
        let wasFinished: Bool
        let endedAt: Date?
    }

    /// Whether there's an answer to take back.
    public var canUndo: Bool { !undoStack.isEmpty }

    /// Builds the queue from the store and starts a session.
    public init(
        config: SessionConfig,
        context: ModelContext,
        dailyNewLimit: Int,
        supportsCodeExecution: Bool,
        policy: ReviewPolicy = ReviewPolicy(),
        now: Date = .now
    ) throws {
        var rng = SystemRandomNumberGenerator()
        let allConcepts = try context.fetch(FetchDescriptor<Concept>())
        let newRemaining = try NewConceptBudget.remaining(limit: dailyNewLimit, in: context, now: now, calendar: policy.calendar)
        let builder = SessionBuilder(config: config, newRemaining: newRemaining, supportsCodeExecution: supportsCodeExecution)

        self.config = config
        self.context = context
        self.startedAt = now
        self.sessionKind = "practice"
        self.builder = builder
        self.recorder = ReviewRecorder(context: context, policy: policy)
        self.concepts = Dictionary(allConcepts.map { ($0.externalID, $0) }, uniquingKeysWith: { first, _ in first })
        self.prompts = Dictionary(allConcepts.flatMap { $0.prompts ?? [] }.map { ($0.externalID, $0) }, uniquingKeysWith: { first, _ in first })
        self.queue = builder.build(from: allConcepts.map(ConceptSnapshot.init), now: now, using: &rng)
        self.record = StudySession(sessionID: sessionID, startedAt: now, configData: config.encoded())
        context.insert(record)
        try context.save()
        isFinished = queue.isEmpty
    }

    /// Starts a session directly with a pre-built queue.
    public init(
        queue: [SessionItem],
        config: SessionConfig,
        context: ModelContext,
        supportsCodeExecution: Bool,
        policy: ReviewPolicy = ReviewPolicy(),
        sessionKind: String = "practice",
        now: Date = .now
    ) throws {
        let allConcepts = try context.fetch(FetchDescriptor<Concept>())
        let builder = SessionBuilder(config: config, newRemaining: 0, supportsCodeExecution: supportsCodeExecution)

        self.config = config
        self.context = context
        self.startedAt = now
        self.sessionKind = sessionKind
        self.builder = builder
        self.recorder = ReviewRecorder(context: context, policy: policy)
        self.concepts = Dictionary(allConcepts.map { ($0.externalID, $0) }, uniquingKeysWith: { first, _ in first })
        self.prompts = Dictionary(allConcepts.flatMap { $0.prompts ?? [] }.map { ($0.externalID, $0) }, uniquingKeysWith: { first, _ in first })
        self.queue = queue
        self.record = StudySession(sessionID: sessionID, startedAt: now, configData: config.encoded())
        context.insert(record)
        try context.save()
        isFinished = queue.isEmpty
    }

    /// Starts a session from a DailyPlan, optionally taking a specific ~5-minute chunk.
    public convenience init(
        plan: DailyPlan,
        chunkIndex: Int? = nil,
        context: ModelContext,
        supportsCodeExecution: Bool,
        policy: ReviewPolicy? = nil,
        now: Date = .now
    ) throws {
        var rng = SystemRandomNumberGenerator()
        let allConcepts = try context.fetch(FetchDescriptor<Concept>())
        let snapshots = allConcepts.map(ConceptSnapshot.init)
        let fullQueue: [SessionItem]
        if plan.kind == "postclass" {
            fullQueue = try PostclassQuiz.items(for: plan, in: context, supportsCodeExecution: supportsCodeExecution)
        } else {
            let builder = DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: supportsCodeExecution)
            fullQueue = builder.build(from: snapshots, now: now, using: &rng)
        }

        let queue: [SessionItem]
        if let chunkIndex {
            let chunks = DailyPlanSessionBuilder.chunkQueue(fullQueue)
            queue = chunks[safe: chunkIndex] ?? []
        } else {
            queue = fullQueue
        }

        let intervalCapsMap = Dictionary(plan.intervalCaps.map { ($0.courseId, $0.maxDays) }, uniquingKeysWith: { first, _ in first })
        let effectivePolicy = policy ?? ReviewPolicy(intervalCaps: intervalCapsMap)
        let config = SessionConfig(
            scope: .init(courseIDs: Set(plan.reviewScope)),
            mode: .review,
            length: .all,
            order: .interleaved
        )
        try self.init(
            queue: queue,
            config: config,
            context: context,
            supportsCodeExecution: supportsCodeExecution,
            policy: effectivePolicy,
            sessionKind: plan.kind == "postclass" ? "postclass" : "plan",
            now: now
        )
    }

    public var currentItem: SessionItem? {
        isFinished ? nil : queue[safe: position]
    }

    public var currentPrompt: Prompt? {
        currentItem.flatMap { prompts[$0.promptID] }
    }

    public var currentConcept: Concept? {
        currentItem.flatMap { concepts[$0.conceptID] }
    }

    public var remainingCount: Int {
        isFinished ? 0 : queue.count - position
    }

    public func concept(withID id: String) -> Concept? {
        concepts[id]
    }

    /// Seconds left in a timed session, or `nil` if it isn't timed.
    public func timeRemaining(at now: Date = .now) -> TimeInterval? {
        guard case .minutes(let minutes) = config.length else { return nil }
        return max(0, startedAt.addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSince(now))
    }

    public func answer(_ grade: Grade, confidence: Confidence? = nil, duration: TimeInterval, answerText: String = "", now: Date = .now) throws {
        guard let item = currentItem, let prompt = prompts[item.promptID], let concept = concepts[item.conceptID] else { return }
        let before = (schedule: concept.scheduleState, introducedAt: concept.introducedAt, lastShownAt: prompt.lastShownAt,
                      queue: queue, position: position, summary: summary, requeued: requeued, wasFinished: isFinished, endedAt: record.endedAt)
        let log = try recorder.record(
            grade,
            for: prompt,
            confidence: confidence,
            duration: duration,
            mode: config.mode,
            sessionID: sessionID,
            answerText: answerText,
            sessionKind: sessionKind,
            calibrated: isCalibrated,
            now: now
        )
        undoStack.append(AnswerSnapshot(
            log: log, concept: concept, schedule: before.schedule, introducedAt: before.introducedAt,
            prompt: prompt, promptLastShownAt: before.lastShownAt, queue: before.queue, position: before.position,
            summary: before.summary, requeued: before.requeued, wasFinished: before.wasFinished, endedAt: before.endedAt
        ))
        summary.record(grade, for: item.conceptID)
        if grade == .again, !requeued.contains(item.conceptID) {
            requeued.insert(item.conceptID)
            let retry = SessionItem(conceptID: item.conceptID, promptID: retryPromptID(for: item), unitID: item.unitID)
            queue.insert(retry, at: min(position + 1 + Self.requeueGap, queue.count))
        }
        position += 1
        if position >= queue.count || timeRemaining(at: now) == 0 {
            try finish(at: now)
        }
    }

    /// Takes back the most recent answer: the review is deleted, the concept's
    /// schedule restored, and the same item shown again, unanswered.
    public func undoLastAnswer() throws {
        guard let snapshot = undoStack.popLast() else { return }
        context.delete(snapshot.log)
        snapshot.concept.scheduleState = snapshot.schedule
        snapshot.concept.introducedAt = snapshot.introducedAt
        snapshot.prompt.lastShownAt = snapshot.promptLastShownAt
        queue = snapshot.queue
        position = snapshot.position
        summary = snapshot.summary
        requeued = snapshot.requeued
        isFinished = snapshot.wasFinished
        record.endedAt = snapshot.endedAt
        try context.save()
    }

    /// Ends the session early or after the last item.
    public func finish(at now: Date = .now) throws {
        guard record.endedAt == nil else { return }
        isFinished = true
        record.endedAt = now
        try context.save()
        if sessionKind == PostclassQuiz.sessionKind {
            PostclassInbox.cleanupAnswered(in: context)
        }
        NotificationCenter.default.post(name: .studySessionDidFinish, object: sessionID)
        StateExportCoordinator.shared.schedulePostSessionExport(context: context)
    }

    /// The end-of-session reflection note (*Make It Stick*: reflection).
    public var reflection: String {
        get { record.reflection ?? "" }
        set {
            record.reflection = newValue.isEmpty ? nil : newValue
            try? context.save()
        }
    }

    private func retryPromptID(for item: SessionItem) -> String {
        guard let concept = concepts[item.conceptID] else { return item.promptID }
        let others = builder.eligiblePrompts(of: ConceptSnapshot(concept)).filter { $0.id != item.promptID }
        return others.randomElement()?.id ?? item.promptID
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Notification.Name {
    public static let studySessionDidFinish = Notification.Name("encore.studySessionDidFinish")
}
