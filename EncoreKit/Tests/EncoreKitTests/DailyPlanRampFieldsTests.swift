import Foundation
@testable import EncoreKit
import SwiftData
import Testing

/// The Phase 3 plan fields (encore#41): decoding, serve order, caps and pauses.
struct DailyPlanRampFieldsTests {
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64 = 42) { self.state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private let now = Date(timeIntervalSince1970: 1763660000) // 2026-11-20, inside the fixtures' window

    private func fixture(_ name: String) throws -> DailyPlan {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
        return try JSONDecoder().decode(DailyPlan.self, from: Data(contentsOf: url))
    }

    /// A plan from `valid_plan.json`, which has none of the Phase 3 fields.
    private func basePlan() throws -> DailyPlan {
        var plan = try fixture("valid_plan.json")
        plan.reviewScope = ["csc301", "mat305"]
        return plan
    }

    private func concept(
        _ id: String,
        course: String? = nil,
        unit: String = "u1",
        tier: String = "standard",
        exams: Set<String> = [],
        overdueDays: Double? = 1,
        isNew: Bool = false,
        prompts: [PromptSnapshot]? = nil
    ) -> ConceptSnapshot {
        ConceptSnapshot(
            id: id,
            courseID: course ?? String(id.split(separator: ".")[0]),
            unitID: unit,
            isNew: isNew,
            dueDate: isNew ? nil : overdueDays.map { now.addingTimeInterval(-$0 * 86400) },
            tier: tier,
            examIDs: exams,
            prompts: prompts ?? [PromptSnapshot(id: "\(id).fc", kind: .flashcard)]
        )
    }

    private func build(_ plan: DailyPlan, _ candidates: [ConceptSnapshot], seed: UInt64 = 42) -> [SessionItem] {
        var rng = SeededRNG(seed: seed)
        return DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: true).build(from: candidates, now: now, using: &rng)
    }

    // MARK: Decoding

    @Test func decodesEveryRampField() throws {
        let plan = try fixture("ramp_plan.json")
        #expect(plan.practiceTest == PracticeTest(examId: "mat305.x.final", itemCount: 15, freeRecallMin: 0.5))
        #expect(plan.reviewQuiz == ReviewQuiz(examId: "csc301.x.midterm", conceptIds: ["csc301.locks", "csc301.threads"]))
        #expect(plan.reviewLimit == 3)
        #expect(plan.reviewPriority == ["mat305.x.final"])
        #expect(plan.newPaused)
        #expect(plan.holdNewForExams == ["csc301.x.midterm"])
        #expect(plan.examFocus == [ExamFocus(examId: "mat305.x.final", rampDay: 9)])

        let roundTripped = try JSONDecoder().decode(DailyPlan.self, from: JSONEncoder().encode(plan))
        #expect(roundTripped == plan)
    }

    @Test func planWithoutRampFieldsDecodesToDefaults() throws {
        let plan = try fixture("valid_plan.json")
        #expect(plan.practiceTest == nil)
        #expect(plan.reviewQuiz == nil)
        #expect(plan.reviewLimit == nil)
        #expect(plan.reviewPriority.isEmpty)
        #expect(!plan.newPaused)
        #expect(plan.holdNewForExams.isEmpty)
    }

    // MARK: Today's session

    @Test func planWithoutRampFieldsServesEveryDueReviewThenNew() throws {
        let plan = try basePlan()
        let candidates = [
            concept("csc301.a", exams: ["csc301.x.midterm"]),
            concept("csc301.b", tier: "core"),
            concept("mat305.c", exams: ["mat305.x.final"]),
            concept("mat305.d"),
            concept("csc301.process", exams: ["csc301.x.midterm"], isNew: true),
        ]
        let items = build(plan, candidates)
        #expect(Set(items.prefix(4).map(\.conceptID)) == ["csc301.a", "csc301.b", "mat305.c", "mat305.d"])
        #expect(items.last?.conceptID == "csc301.process")
        #expect(items.count == 5)
    }

    @Test func reviewLimitKeepsPriorityThenCoreThenMostOverdue() throws {
        var plan = try basePlan()
        plan.new = []
        plan.reviewLimit = 3
        let candidates = [
            concept("csc301.old", overdueDays: 10),
            concept("csc301.older", overdueDays: 20),
            concept("csc301.core", tier: "core", overdueDays: 1),
            concept("mat305.final", exams: ["mat305.x.final"], overdueDays: 0.5),
            concept("mat305.recent", overdueDays: 2),
        ]

        // Without priority: core first, then most overdue.
        #expect(Set(build(plan, candidates).map(\.conceptID)) == ["csc301.core", "csc301.older", "csc301.old"])

        // With priority: the exam's concept takes a slot ahead of core.
        plan.reviewPriority = ["mat305.x.final"]
        #expect(Set(build(plan, candidates).map(\.conceptID)) == ["mat305.final", "csc301.core", "csc301.older"])

        plan.reviewLimit = 0
        #expect(build(plan, candidates).isEmpty)
    }

    @Test func reviewPriorityServesTheExamsConceptsFirst() throws {
        var plan = try basePlan()
        plan.new = []
        plan.reviewPriority = ["mat305.x.final"]
        let candidates = [
            concept("csc301.a"), concept("csc301.b"), concept("csc301.c"),
            concept("mat305.x1", exams: ["mat305.x.final"]),
            concept("mat305.x2", exams: ["mat305.x.final"]),
            concept("mat305.other"),
        ]
        for seed in UInt64(1)...20 {
            let ids = build(plan, candidates, seed: seed).map(\.conceptID)
            #expect(ids.count == 6)
            #expect(Set(ids.prefix(2)) == ["mat305.x1", "mat305.x2"])
        }
    }

    @Test func newPausedIntroducesNothingNew() throws {
        var plan = try basePlan()
        plan.newPaused = true
        let items = build(plan, [concept("csc301.due"), concept("csc301.process", isNew: true)])
        #expect(items.map(\.conceptID) == ["csc301.due"])
    }

    @Test func holdNewForExamsSkipsOnlyThatExamsConcepts() throws {
        var plan = try basePlan()
        plan.new = [PlanNew(conceptId: "csc301.held"), PlanNew(conceptId: "mat305.free"), PlanNew(conceptId: "csc301.untagged")]
        plan.holdNewForExams = ["csc301.x.midterm"]
        let candidates = [
            concept("csc301.held", exams: ["csc301.x.midterm"], isNew: true),
            concept("mat305.free", exams: ["mat305.x.final"], isNew: true),
            concept("csc301.untagged", isNew: true),
        ]
        #expect(build(plan, candidates).map(\.conceptID) == ["mat305.free", "csc301.untagged"])
    }

    // MARK: Practice test

    private func practiceCandidates() -> [ConceptSnapshot] {
        var result: [ConceptSnapshot] = []
        for i in 0..<30 {
            let id = "mat305.t\(i)"
            // Every third concept has only a recognition prompt.
            let prompts = i % 3 == 0
                ? [PromptSnapshot(id: "\(id).mc", kind: .multipleChoice)]
                : [PromptSnapshot(id: "\(id).mc", kind: .multipleChoice), PromptSnapshot(id: "\(id).sa", kind: .shortAnswer)]
            result.append(concept(id, unit: "u\(i % 3)", exams: ["mat305.x.final"], overdueDays: -5, prompts: prompts))
        }
        result.append(concept("mat305.unseen", exams: ["mat305.x.final"], isNew: true))
        result.append(concept("mat305.offscope"))
        return result
    }

    @Test func practiceTestDrawsItemCountFromExamScopeWithEnoughFreeRecall() throws {
        var plan = try basePlan()
        plan.practiceTest = PracticeTest(examId: "mat305.x.final", itemCount: 16, freeRecallMin: 0.75)
        var rng = SeededRNG()
        let items = DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: true)
            .buildPracticeTest(from: practiceCandidates(), now: now, using: &rng)

        #expect(items.count == 16)
        #expect(Set(items.map(\.conceptID)).count == 16)
        #expect(items.allSatisfy { $0.conceptID.hasPrefix("mat305.t") })
        let freeRecall = items.count { $0.promptID.hasSuffix(".sa") }
        #expect(freeRecall >= 12)
        // Mixed across units: no long runs from one unit.
        #expect(zip(items, items.dropFirst()).allSatisfy { $0.unitID != $1.unitID })
    }

    @Test func practiceTestIsEmptyWithoutTheField() throws {
        var rng = SeededRNG()
        let items = DailyPlanSessionBuilder(plan: try basePlan(), supportsCodeExecution: true)
            .buildPracticeTest(from: practiceCandidates(), now: now, using: &rng)
        #expect(items.isEmpty)
    }

    // MARK: Review quiz

    @Test func reviewQuizAsksExactlyTheListedConceptsInOrder() throws {
        var plan = try basePlan()
        plan.reviewQuiz = ReviewQuiz(examId: "csc301.x.midterm", conceptIds: ["csc301.locks", "csc301.missing", "csc301.threads"])
        let candidates = [
            concept("csc301.threads", overdueDays: -3, prompts: [
                PromptSnapshot(id: "csc301.threads.mc", kind: .multipleChoice),
                PromptSnapshot(id: "csc301.threads.sa", kind: .shortAnswer),
            ]),
            concept("csc301.locks", overdueDays: -3),
            concept("csc301.paging", exams: ["csc301.x.midterm"]),
        ]
        let builder = DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: true)
        let items = builder.buildReviewQuiz(from: candidates, now: now)
        #expect(items.map(\.promptID) == ["csc301.locks.fc", "csc301.threads.sa"])

        plan.reviewQuiz = nil
        #expect(DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: true).buildReviewQuiz(from: candidates, now: now).isEmpty)
    }

    // MARK: Attempts

    @MainActor
    @Test func practiceTestAttemptsCarryThePlanID() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext
        let course = Course(externalID: "mat305", name: "Statistics")
        let unit = CourseUnit(externalID: "mat305.u1", name: "Probability")
        unit.course = course
        let exam = Exam(externalID: "mat305.x.final", name: "Final", date: now.addingTimeInterval(9 * 86400), kind: "final")
        exam.units = [unit]
        let concept = Concept(externalID: "mat305.bayes", title: "Bayes")
        concept.unit = unit
        concept.introducedAt = now.addingTimeInterval(-5 * 86400)
        concept.dueDate = now.addingTimeInterval(3 * 86400)
        let prompt = Prompt(
            externalID: "mat305.bayes.fc",
            content: .flashcard(.init(front: "Bayes' rule?", back: "P(A|B) = P(B|A)P(A)/P(B)")),
            origin: .imported
        )
        prompt.concept = concept
        context.insert(course)
        context.insert(unit)
        context.insert(exam)
        context.insert(concept)
        context.insert(prompt)
        try context.save()

        var plan = try basePlan()
        plan.practiceTest = PracticeTest(examId: "mat305.x.final", itemCount: 15)
        let engine = try SessionEngine(plan: plan, part: .practiceTest, context: context, supportsCodeExecution: false, now: now)
        #expect(engine.queue.map(\.conceptID) == ["mat305.bayes"])
        let dueBefore = concept.dueDate
        try engine.answer(.good, duration: 3, now: now)

        // A passed test item that wasn't due keeps its schedule.
        #expect(concept.dueDate == dueBefore)

        let tempDir = FileManager.default.temporaryDirectory.appending(path: "encore-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = try #require(try StateExporter(context: context, handoffFolder: HandoffFolder(rootURL: tempDir)).exportAttempts(now: now))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let attempt = try #require(try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        #expect(attempt["planId"] as? String == plan.header.id)
        #expect(attempt["sessionKind"] as? String == "plan")
    }
}
