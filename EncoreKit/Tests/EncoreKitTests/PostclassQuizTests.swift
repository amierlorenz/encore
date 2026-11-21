import Foundation
@testable import EncoreKit
import SwiftData
import Testing

@MainActor
struct PostclassQuizTests {
    final class MockNotificationScheduler: NotificationScheduling, @unchecked Sendable {
        var scheduled: [PostclassNotification] = []
        var cancelledIDs: [String] = []

        func schedule(_ notification: PostclassNotification) {
            scheduled.append(notification)
        }

        func cancel(ids: [String]) {
            cancelledIDs.append(contentsOf: ids)
        }
    }

    private func makeTempHandoff() throws -> (HandoffFolder, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "encore-test-\(UUID().uuidString)")
        let folder = HandoffFolder(rootURL: tempDir)
        return (folder, tempDir)
    }

    private func makeImportJSON(batchID: String = "batch-01", courseID: String = "mat305", conceptID: String = "mat305.eigen") -> Data {
        let json = """
        {
          "header": {
            "schema": "encore.import",
            "version": 2,
            "id": "\(batchID)",
            "created_at": "2026-12-01T14:00:00Z",
            "producer": "articulate 0.1.0"
          },
          "courses": [
            {
              "id": "\(courseID)",
              "name": "Linear Algebra",
              "units": [
                {
                  "id": "\(courseID).u1",
                  "name": "Eigenvalues",
                  "order": 1,
                  "concepts": [
                    {
                      "id": "\(conceptID)",
                      "title": "Eigenvalue",
                      "explanation": "A scalar associated with a linear system.",
                      "kind": "definition",
                      "status": "active",
                      "tier": "standard",
                      "details": {
                        "explanationCitations": [],
                        "aliases": [],
                        "useWhen": [],
                        "conditions": [],
                        "workedExamples": []
                      },
                      "groupIds": [],
                      "tags": [],
                      "prompts": [
                        {
                          "id": "\(conceptID).p1",
                          "kind": "flashcard",
                          "status": "active",
                          "content": {
                            "type": "flashcard",
                            "front": "What is an eigenvalue?",
                            "back": "A scalar associated with a linear system."
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        return Data(json.utf8)
    }

    private func makePostclassPlanJSON(
        planID: String = "postclass-plan-01",
        lectureID: String = "mat305.l.2026-12-01",
        importBatch: String = "batch-01",
        conceptID: String = "mat305.eigen",
        promptID: String = "mat305.eigen.p1",
        validUntil: String = "2026-12-02T02:00:00Z"
    ) -> Data {
        let json = """
        {
          "header": {
            "schema": "encore.plan",
            "version": 1,
            "id": "\(planID)",
            "created_at": "2026-12-01T14:30:00Z",
            "producer": "articulate 0.1.0"
          },
          "kind": "postclass",
          "date": "2026-12-01",
          "validUntil": "\(validUntil)",
          "reviewScope": ["mat305"],
          "new": [
            {
              "conceptId": "\(conceptID)",
              "promptIds": ["\(promptID)"],
              "reason": "standard"
            }
          ],
          "importBatch": "\(importBatch)"
        }
        """
        return Data(json.utf8)
    }

    @Test func planWaitsForBatchAndImportsInOrder() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let defaults = UserDefaults(suiteName: "test-postclass-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let store = PostclassPlanStore(defaults: defaults)
        let mockScheduler = MockNotificationScheduler()
        let notifications = PostclassNotifications(scheduler: mockScheduler, defaults: defaults)
        let inbox = PostclassInbox(handoffFolder: folder, context: context, store: store, notifications: notifications)

        let postclassURL = folder.toEncoreURL.appending(path: "postclass-mat305.l.2026-12-01.json")
        try makePostclassPlanJSON(importBatch: "batch-01").write(to: postclassURL)

        // 1. Plan arrived before batch -> outcome is waiting, file remains in to-encore
        let outcome1 = inbox.process(postclassURL)
        #expect(outcome1 == .waiting)
        #expect(FileManager.default.fileExists(atPath: postclassURL.path))
        #expect(store.plans().isEmpty)
        #expect(mockScheduler.scheduled.isEmpty)

        // 2. Now import the batch
        let importURL = folder.toEncoreURL.appending(path: "import-batch-01.json")
        try makeImportJSON(batchID: "batch-01").write(to: importURL)

        let importer = Importer(context: context)
        _ = try importer.importFile(at: importURL, handoff: folder, deleteOnSuccess: true)

        // 3. Re-process the post-class plan -> now served!
        let outcome2 = inbox.process(postclassURL)
        #expect(outcome2 == .served)
        #expect(store.plans().count == 1)
        #expect(store.plans().first?.lectureID == "mat305.l.2026-12-01")
        #expect(mockScheduler.scheduled.count >= 1)
    }

    @Test func handoffWatcherProcessesBatchAndPlanInOrder() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let defaults = UserDefaults(suiteName: "test-postclass-watcher-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let store = PostclassPlanStore(defaults: defaults)
        let mockScheduler = MockNotificationScheduler()
        let notifications = PostclassNotifications(scheduler: mockScheduler, defaults: defaults)

        let postclassURL = folder.toEncoreURL.appending(path: "postclass-mat305.l.2026-12-01.json")
        let importURL = folder.toEncoreURL.appending(path: "import-batch-01.json")

        try makePostclassPlanJSON(importBatch: "batch-01").write(to: postclassURL)
        try makeImportJSON(batchID: "batch-01").write(to: importURL)

        #if os(macOS)
        let watcher = HandoffWatcher(handoffFolder: folder, context: context) { url in
            if url.lastPathComponent.hasPrefix("postclass-") {
                _ = PostclassInbox(handoffFolder: folder, context: context, store: store, notifications: notifications).process(url)
            }
        }
        let result = watcher.scan()
        #expect(result.importedFiles.contains("import-batch-01.json"))
        #expect(result.planFiles.contains("postclass-mat305.l.2026-12-01.json"))
        #expect(store.plans().count == 1)
        #endif
    }

    @Test func answeringIntroducesConceptAndNextReviewIsAtLeastOneDayLaterWithCalibratedFalse() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        // Import the concept batch
        let importURL = folder.toEncoreURL.appending(path: "import-batch-01.json")
        try makeImportJSON(batchID: "batch-01", conceptID: "mat305.eigen").write(to: importURL)
        _ = try Importer(context: context).importFile(at: importURL, handoff: folder, deleteOnSuccess: true)

        let concept = try #require(try context.fetch(FetchDescriptor<Concept>(predicate: #Predicate { $0.externalID == "mat305.eigen" })).first)
        #expect(concept.isNew)
        #expect(concept.introducedAt == nil)

        // Load the post-class plan
        let planData = makePostclassPlanJSON(conceptID: "mat305.eigen", promptID: "mat305.eigen.p1")
        let plan = try JSONDecoder().decode(DailyPlan.self, from: planData)

        let quizNow = Date(timeIntervalSince1970: 1733065200) // 2024-12-01 15:00:00 UTC
        let engine = try SessionEngine(
            plan: plan,
            context: context,
            supportsCodeExecution: false,
            now: quizNow
        )

        #expect(engine.sessionKind == "postclass")
        #expect(!engine.isCalibrated)
        #expect(engine.queue.count == 1)

        // Answer in the post-class quiz
        try engine.answer(.good, duration: 3.0, answerText: "A scalar", now: quizNow)
        try engine.finish(at: quizNow)

        // 1. Concept is now introduced
        #expect(!concept.isNew)
        #expect(concept.introducedAt == quizNow)

        // 2. Schedule is at least 1 day later
        let nextDue = try #require(concept.dueDate)
        let calendar = Calendar.current
        let startOfQuizDay = calendar.startOfDay(for: quizNow)
        let oneDayLater = calendar.date(byAdding: .day, value: 1, to: startOfQuizDay)!
        #expect(nextDue >= oneDayLater)
        #expect(concept.awaitsFirstReviewAfterPostclass)

        let initialEase = concept.ease

        // 3. First scheduled review after post-class quiz
        let reviewNow = nextDue.addingTimeInterval(3600) // Study when due
        let reviewEngine = try SessionEngine(
            queue: [.init(conceptID: "mat305.eigen", promptID: "mat305.eigen.p1", unitID: "mat305.u1")],
            config: .init(mode: .review),
            context: context,
            supportsCodeExecution: false,
            sessionKind: "plan",
            now: reviewNow
        )
        #expect(reviewEngine.isCalibrated)

        // Answer with .hard (which normally decreases ease by 0.15 in SM2)
        try reviewEngine.answer(.hard, duration: 4.0, answerText: "scalar", now: reviewNow)
        try reviewEngine.finish(at: reviewNow)

        // First review leaves ease alone!
        #expect(concept.ease == initialEase)
        #expect(!concept.awaitsFirstReviewAfterPostclass)

        // Export attempts and check calibrated: false
        let exporter = StateExporter(context: context, handoffFolder: folder)
        let attemptsURL = try #require(try exporter.exportAttempts(now: reviewNow))
        let lines = (try String(contentsOf: attemptsURL, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")

        #expect(lines.count == 3) // Header + Postclass attempt + First review attempt

        let firstReviewAttemptData = try #require(lines[2].data(using: .utf8))
        let firstReviewAttempt = try #require(try JSONSerialization.jsonObject(with: firstReviewAttemptData) as? [String: Any])
        #expect(firstReviewAttempt["conceptId"] as? String == "mat305.eigen")
        #expect(firstReviewAttempt["sessionKind"] as? String == "plan")
        #expect(firstReviewAttempt["calibrated"] as? Bool == false)

        // 4. Subsequent review after the first review updates ease normally and has calibrated: true
        let subsequentNow = reviewNow.addingTimeInterval(86400 * 3)
        let secondReviewEngine = try SessionEngine(
            queue: [.init(conceptID: "mat305.eigen", promptID: "mat305.eigen.p1", unitID: "mat305.u1")],
            config: .init(mode: .review),
            context: context,
            supportsCodeExecution: false,
            sessionKind: "plan",
            now: subsequentNow
        )
        try secondReviewEngine.answer(.hard, duration: 4.0, answerText: "scalar", now: subsequentNow)
        try secondReviewEngine.finish(at: subsequentNow)

        // Ease is now updated
        #expect(concept.ease < initialEase)

        let secondAttemptsURL = try #require(try exporter.exportAttempts(now: subsequentNow))
        let secondLines = (try String(contentsOf: secondAttemptsURL, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        let secondAttemptData = try #require(secondLines[1].data(using: .utf8))
        let secondAttempt = try #require(try JSONSerialization.jsonObject(with: secondAttemptData) as? [String: Any])
        #expect(secondAttempt["calibrated"] as? Bool == true)
    }

    @Test func notificationsAreScheduledOncePerLecture() throws {
        let defaults = UserDefaults(suiteName: "test-notifications-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let mockScheduler = MockNotificationScheduler()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        let notifications = PostclassNotifications(scheduler: mockScheduler, defaults: defaults, calendar: cal)

        let planData = makePostclassPlanJSON(validUntil: "2026-12-01T23:00:00Z")
        let plan = try JSONDecoder().decode(DailyPlan.self, from: planData)
        let entry = PostclassPlan(lectureID: "mat305.l.2026-12-01", plan: plan)

        let landingNow = Date(timeIntervalSince1970: 1764590400) // 12:00 UTC on 2026-12-01
        notifications.planLanded(entry, courseName: "Linear Algebra", at: landingNow)

        // Should schedule "ready" (immediate) and "reminder" (at 15:00)
        #expect(mockScheduler.scheduled.count == 2)
        let ready = mockScheduler.scheduled.first { $0.id == PostclassNotifications.readyID("mat305.l.2026-12-01") }
        let reminder = mockScheduler.scheduled.first { $0.id == PostclassNotifications.reminderID("mat305.l.2026-12-01") }
        #expect(ready != nil)
        #expect(ready?.date == nil)
        #expect(reminder != nil)
        #expect(reminder?.date != nil)

        // Calling planLanded a second time for the same lecture does nothing
        notifications.planLanded(entry, courseName: "Linear Algebra", at: landingNow.addingTimeInterval(300))
        #expect(mockScheduler.scheduled.count == 2)

        // Closing quiz cancels reminder
        notifications.quizClosed(lectureID: "mat305.l.2026-12-01")
        #expect(mockScheduler.cancelledIDs == [PostclassNotifications.reminderID("mat305.l.2026-12-01")])
    }

    @Test func expiredPlanIsCleanedUp() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let defaults = UserDefaults(suiteName: "test-expired-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let mockScheduler = MockNotificationScheduler()
        let notifications = PostclassNotifications(scheduler: mockScheduler, defaults: defaults)
        let store = PostclassPlanStore(defaults: defaults)
        let inbox = PostclassInbox(handoffFolder: folder, context: context, store: store, notifications: notifications)

        let postclassURL = folder.toEncoreURL.appending(path: "postclass-mat305.l.2026-12-01.json")
        let planData = makePostclassPlanJSON(validUntil: "2026-12-01T10:00:00Z")
        try planData.write(to: postclassURL)
        let plan = try JSONDecoder().decode(DailyPlan.self, from: planData)

        let now = plan.validUntil.addingTimeInterval(3600) // past validUntil
        let outcome = inbox.process(postclassURL, now: now)

        #expect(outcome == .expired)
        #expect(!FileManager.default.fileExists(atPath: postclassURL.path))
        #expect(store.plans().isEmpty)
    }
}
