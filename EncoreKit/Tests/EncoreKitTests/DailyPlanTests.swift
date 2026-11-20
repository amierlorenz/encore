import Foundation
@testable import EncoreKit
import Testing

struct DailyPlanTests {
    private func fixtureURL() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/valid_plan.json")
            .standardizedFileURL
    }

    @Test func decodesFixturePlan() throws {
        let data = try Data(contentsOf: fixtureURL())
        let plan = try JSONDecoder().decode(DailyPlan.self, from: data)

        #expect(plan.header.schema == "encore.plan")
        #expect(plan.header.version == 1)
        #expect(plan.header.id == "plan-01JD0000000000000000000002")
        #expect(plan.header.producer == "articulate 0.1.0")
        #expect(plan.kind == "daily")
        #expect(plan.date == "2026-11-20")
        #expect(plan.reviewScope == ["csc301"])
        #expect(plan.new.count == 1)
        #expect(plan.new[0].conceptId == "csc301.process")
        #expect(plan.new[0].promptIds.isEmpty)
        #expect(plan.new[0].reason == "core")
        #expect(plan.examFocus.count == 1)
        #expect(plan.examFocus[0].examId == "csc301.x.midterm")
        #expect(plan.examFocus[0].rampDay == 15)
        #expect(plan.budgetMinutes.target == 20)
        #expect(plan.budgetMinutes.planned == 20)
        #expect(plan.kindsMix.freeRecallMin == 0.5)
        #expect(plan.readingShare == 0.1)
        #expect(plan.intervalCaps.count == 1)
        #expect(plan.intervalCaps[0].courseId == "csc301")
        #expect(plan.intervalCaps[0].maxDays == 30)
    }

    @Test func rejectsUnknownSchemaOrVersion() throws {
        let invalidSchemaJSON = """
        {
            "header": {
                "schema": "unknown.schema",
                "version": 1,
                "id": "test",
                "created_at": "2026-11-20T02:00:00Z",
                "producer": "test"
            },
            "kind": "daily",
            "date": "2026-11-20",
            "validUntil": "2026-11-21T02:00:00Z",
            "reviewScope": [],
            "new": []
        }
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DailyPlan.self, from: invalidSchemaJSON)
        }

        let invalidVersionJSON = """
        {
            "header": {
                "schema": "encore.plan",
                "version": 99,
                "id": "test",
                "created_at": "2026-11-20T02:00:00Z",
                "producer": "test"
            },
            "kind": "daily",
            "date": "2026-11-20",
            "validUntil": "2026-11-21T02:00:00Z",
            "reviewScope": [],
            "new": []
        }
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DailyPlan.self, from: invalidVersionJSON)
        }
    }

    @Test func planExpirationAndAvailability() throws {
        let data = try Data(contentsOf: fixtureURL())
        let plan = try JSONDecoder().decode(DailyPlan.self, from: data)

        // Valid until is 2026-11-21 02:00:00 -05:00
        let beforeValid = plan.validUntil.addingTimeInterval(-3600)
        let afterValid = plan.validUntil.addingTimeInterval(3600)

        #expect(!plan.isExpired(at: beforeValid))
        #expect(plan.isExpired(at: afterValid))

        // Available from 06:00 local time on 2026-11-20
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!

        var morning5AM = DateComponents()
        morning5AM.year = 2026
        morning5AM.month = 11
        morning5AM.day = 20
        morning5AM.hour = 5
        morning5AM.minute = 30
        let at530AM = cal.date(from: morning5AM)!

        var morning7AM = DateComponents()
        morning7AM.year = 2026
        morning7AM.month = 11
        morning7AM.day = 20
        morning7AM.hour = 7
        let at7AM = cal.date(from: morning7AM)!

        #expect(!plan.isAvailable(at: at530AM, calendar: cal))
        #expect(plan.isAvailable(at: at7AM, calendar: cal))
        #expect(!plan.isAvailable(at: afterValid, calendar: cal))
    }

    @Test func planStoreTracksPlanIdSeenAndCreatedAt() throws {
        let suite = "test.plan.store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removeSuite(named: suite) }

        let store = DailyPlanStore(defaults: defaults)
        let data = try Data(contentsOf: fixtureURL())
        let plan = try store.loadFromData(data)

        #expect(store.planIdSeen == "plan-01JD0000000000000000000002")
        #expect(store.planCreatedAt == plan.header.createdAt)
        #expect(store.activePlan(at: plan.header.createdAt) != nil)

        // After validUntil, activePlan returns nil
        let expiredTime = plan.validUntil.addingTimeInterval(10)
        #expect(store.activePlan(at: expiredTime) == nil)
    }

    @Test func syncRoundTripToIPhone() throws {
        let suite = "test.plan.sync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removeSuite(named: suite) }

        // 1. Mac loads plan and stores in defaults
        let macStore = DailyPlanStore(defaults: defaults)
        let data = try Data(contentsOf: fixtureURL())
        let plan = try macStore.loadFromData(data)

        // 2. iPhone reads from defaults
        let iPhoneStore = DailyPlanStore(defaults: defaults)
        iPhoneStore.loadFromDefaults()

        let activeOnPhone = try #require(iPhoneStore.activePlan(at: plan.header.createdAt))
        #expect(activeOnPhone.header.id == plan.header.id)
        #expect(activeOnPhone.date == plan.date)
        #expect(activeOnPhone.new.count == plan.new.count)
        #expect(iPhoneStore.planIdSeen == plan.header.id)
    }

    @Test func respectsIntervalCapsInReviewPolicy() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1700000000)

        // Policy with interval cap of 30 days for csc301
        let policy = ReviewPolicy(
            calendar: cal,
            intervalCaps: ["csc301": 30]
        )

        // High ease and repetitions would normally give interval > 30 days
        var state = ScheduleState()
        state.ease = 2.5
        state.intervalDays = 25
        state.repetitions = 3

        let next = policy.next(
            state,
            grade: .easy,
            context: .init(mode: .review, isNew: false, wasDue: true, courseID: "csc301", now: now)
        )

        // Normally 25 * 2.5 * 1.3 = 81.25 -> 81 days. Capped at 30 days!
        #expect(next.intervalDays == 30)
        let expectedDue = cal.date(byAdding: .day, value: 30, to: cal.startOfDay(for: now))
        #expect(next.dueDate == expectedDue)
    }

    @Test func examCapTakesPrecedenceIfTighterThanIntervalCap() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1700000000)
        let examDate = cal.date(byAdding: .day, value: 8, to: now)! // daysLeft = 8 -> cap = 4 days

        let policy = ReviewPolicy(
            calendar: cal,
            intervalCaps: ["csc301": 30]
        )

        var state = ScheduleState()
        state.ease = 2.5
        state.intervalDays = 20
        state.repetitions = 2

        let next = policy.next(
            state,
            grade: .good,
            context: .init(mode: .review, isNew: false, wasDue: true, examDates: [examDate], courseID: "csc301", now: now)
        )

        // Exam cap is 4 days, which is tighter than interval cap 30 days
        #expect(next.intervalDays == 4)
    }

    @Test func practicePassingDoesNotMoveDueDates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1700000000)
        let initialDue = cal.date(byAdding: .day, value: 5, to: now)!

        let policy = ReviewPolicy(calendar: cal)
        var state = ScheduleState()
        state.dueDate = initialDue
        state.intervalDays = 5

        let next = policy.next(
            state,
            grade: .good,
            context: .init(mode: .practice, isNew: false, wasDue: false, now: now)
        )

        #expect(next.dueDate == initialDue)
        #expect(next.intervalDays == 5)
    }
}
