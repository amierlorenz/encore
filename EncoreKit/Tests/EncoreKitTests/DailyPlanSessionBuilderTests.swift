import Foundation
@testable import EncoreKit
import Testing

struct DailyPlanSessionBuilderTests {
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64 = 42) { self.state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func makePrompt(id: String, kind: PromptKind = .flashcard, flagged: Bool = false) -> PromptSnapshot {
        PromptSnapshot(id: id, kind: kind, isFlagged: flagged, lastShownAt: nil)
    }

    private func makeConcept(
        id: String,
        courseID: String = "csc301",
        unitID: String = "u1",
        isNew: Bool = false,
        dueDate: Date? = nil,
        prompts: [PromptSnapshot] = []
    ) -> ConceptSnapshot {
        ConceptSnapshot(
            id: id,
            courseID: courseID,
            unitID: unitID,
            unitSortIndex: 0,
            tags: [],
            isNew: isNew,
            dueDate: dueDate,
            ease: 2.5,
            lapses: 0,
            createdAt: .now,
            prompts: prompts.isEmpty ? [makePrompt(id: "\(id).p1")] : prompts
        )
    }

    @Test func buildsSessionWithDueItemsFirstAndNewConceptsInPlanOrder() throws {
        let fixtureURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/valid_plan.json")
            .standardizedFileURL
        let data = try Data(contentsOf: fixtureURL)
        var plan = try JSONDecoder().decode(DailyPlan.self, from: data)

        // Add a second new concept to verify ordering
        plan.new = [
            PlanNew(conceptId: "csc301.process", promptIds: []),
            PlanNew(conceptId: "csc301.fork", promptIds: ["csc301.fork.p2"])
        ]

        let now = Date(timeIntervalSince1970: 1763660000)

        // Candidates:
        // 1. Due concepts in reviewScope
        let dueConcept1 = makeConcept(id: "csc301.threads", courseID: "csc301", dueDate: now.addingTimeInterval(-86400))
        let dueConcept2 = makeConcept(id: "csc301.locks", courseID: "csc301", dueDate: now.addingTimeInterval(-43200))

        // 2. Not due in reviewScope (should NOT be included)
        let notDueConcept = makeConcept(id: "csc301.paging", courseID: "csc301", dueDate: now.addingTimeInterval(86400))

        // 3. Due but outside reviewScope (should NOT be included)
        let outsideScopeConcept = makeConcept(id: "mat305.eigen", courseID: "mat305", dueDate: now.addingTimeInterval(-86400))

        // 4. New concept 1: promptIds empty -> all active prompts
        let newPrompt1 = makePrompt(id: "csc301.process.fc", kind: .flashcard)
        let newPrompt2 = makePrompt(id: "csc301.process.sa", kind: .shortAnswer)
        let newConcept1 = makeConcept(
            id: "csc301.process",
            courseID: "csc301",
            isNew: true,
            prompts: [newPrompt1, newPrompt2]
        )

        // 5. New concept 2: promptIds specific -> only csc301.fork.p2
        let forkPrompt1 = makePrompt(id: "csc301.fork.p1", kind: .flashcard)
        let forkPrompt2 = makePrompt(id: "csc301.fork.p2", kind: .shortAnswer)
        let newConcept2 = makeConcept(
            id: "csc301.fork",
            courseID: "csc301",
            isNew: true,
            prompts: [forkPrompt1, forkPrompt2]
        )

        let candidates = [
            dueConcept1,
            dueConcept2,
            notDueConcept,
            outsideScopeConcept,
            newConcept1,
            newConcept2
        ]

        var rng = SeededRNG()
        let builder = DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: true)
        let items = builder.build(from: candidates, now: now, using: &rng)

        // Total items expected:
        // 2 due items + 2 prompts for concept1 + 1 prompt for concept2 = 5 items
        #expect(items.count == 5)

        // 1. Due items must come FIRST
        let firstTwoConceptIDs = Set(items[0..<2].map(\.conceptID))
        #expect(firstTwoConceptIDs == ["csc301.threads", "csc301.locks"])

        // 2. New concepts follow in PLAN ORDER
        let remainingItems = Array(items[2...])
        // csc301.process prompts come first
        #expect(remainingItems[0].conceptID == "csc301.process")
        #expect(remainingItems[1].conceptID == "csc301.process")
        let processPromptIDs = Set([remainingItems[0].promptID, remainingItems[1].promptID])
        #expect(processPromptIDs == ["csc301.process.fc", "csc301.process.sa"])

        // csc301.fork prompt follows, only forkPrompt2
        #expect(remainingItems[2].conceptID == "csc301.fork")
        #expect(remainingItems[2].promptID == "csc301.fork.p2")

        // Excluded concepts are not present
        #expect(!items.contains { $0.conceptID == "csc301.paging" })
        #expect(!items.contains { $0.conceptID == "mat305.eigen" })
    }

    @Test func interleavesDueItemsAcrossCourses() throws {
        let fixtureURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/valid_plan.json")
            .standardizedFileURL
        let data = try Data(contentsOf: fixtureURL)
        var plan = try JSONDecoder().decode(DailyPlan.self, from: data)
        plan.reviewScope = ["csc301", "mat305"]
        plan.new = []

        let now = Date(timeIntervalSince1970: 1763660000)

        let csc1 = makeConcept(id: "csc301.c1", courseID: "csc301", dueDate: now.addingTimeInterval(-100))
        let csc2 = makeConcept(id: "csc301.c2", courseID: "csc301", dueDate: now.addingTimeInterval(-200))
        let mat1 = makeConcept(id: "mat305.m1", courseID: "mat305", dueDate: now.addingTimeInterval(-100))
        let mat2 = makeConcept(id: "mat305.m2", courseID: "mat305", dueDate: now.addingTimeInterval(-200))

        var rng = SeededRNG()
        let builder = DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: true)
        let items = builder.build(from: [csc1, csc2, mat1, mat2], now: now, using: &rng)

        #expect(items.count == 4)
        // With 2 items per course, consecutive items alternate courseID
        let courses = items.map { item in
            item.conceptID.hasPrefix("csc301") ? "csc301" : "mat305"
        }
        #expect(courses[0] != courses[1])
        #expect(courses[1] != courses[2])
        #expect(courses[2] != courses[3])
    }

    @Test func expiredPlanBuildsEmptyQueue() throws {
        let fixtureURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/valid_plan.json")
            .standardizedFileURL
        let data = try Data(contentsOf: fixtureURL)
        let plan = try JSONDecoder().decode(DailyPlan.self, from: data)

        // Plan validUntil is 2026-11-21 02:00:00 -05:00
        let afterExpiry = plan.validUntil.addingTimeInterval(3600)

        let concept = makeConcept(id: "csc301.process", courseID: "csc301", isNew: true)
        var rng = SeededRNG()
        let builder = DailyPlanSessionBuilder(plan: plan, supportsCodeExecution: true)
        let items = builder.build(from: [concept], now: afterExpiry, using: &rng)

        #expect(items.isEmpty)
    }

    @Test func chunkQueueSplitsInto5MinuteChunksWithoutCuttingOff() {
        let items = (1...25).map { i in
            SessionItem(conceptID: "c\(i)", promptID: "p\(i)", unitID: "u1")
        }

        // Past average answer duration: 25 seconds
        // 300 seconds (5 min) / 25s = 12 items per chunk
        let chunks = DailyPlanSessionBuilder.chunkQueue(items, averageItemDuration: 25.0, targetChunkMinutes: 5)

        #expect(chunks.count == 3)
        #expect(chunks[0].count == 12)
        #expect(chunks[1].count == 12)
        #expect(chunks[2].count == 1)

        // Every single item is preserved
        let flattened = chunks.flatMap { $0 }
        #expect(flattened == items)
    }

    @Test func iPhoneBuildsIdenticalSessionAfterSync() throws {
        let fixtureURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/valid_plan.json")
            .standardizedFileURL
        let data = try Data(contentsOf: fixtureURL)

        let suite = "test.builder.sync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removeSuite(named: suite) }

        // Mac loads and stores plan
        let macStore = DailyPlanStore(defaults: defaults)
        let macPlan = try macStore.loadFromData(data)

        // iPhone syncs plan
        let iPhoneStore = DailyPlanStore(defaults: defaults)
        iPhoneStore.loadFromDefaults()
        let iPhonePlan = try #require(iPhoneStore.activePlan(at: macPlan.header.createdAt))

        let now = macPlan.header.createdAt
        let candidate = makeConcept(id: "csc301.process", courseID: "csc301", isNew: true)

        var rng1 = SeededRNG(seed: 123)
        var rng2 = SeededRNG(seed: 123)

        let macItems = DailyPlanSessionBuilder(plan: macPlan, supportsCodeExecution: true)
            .build(from: [candidate], now: now, using: &rng1)
        let iPhoneItems = DailyPlanSessionBuilder(plan: iPhonePlan, supportsCodeExecution: true)
            .build(from: [candidate], now: now, using: &rng2)

        #expect(macItems == iPhoneItems)
        #expect(macItems.count == 1)
    }
}
