import Foundation
import EncoreKit
import SwiftData
import Testing

@MainActor
struct StateExporterTests {
    private func makeTemporaryHandoffFolder() -> (HandoffFolder, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "encore-test-\(UUID().uuidString)")
        let folder = HandoffFolder(rootURL: tempDir)
        return (folder, tempDir)
    }

    @Test func exportStateProducesValidDocumentAndExcludesAIVariants() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup AppliedBatch
        let batch = AppliedBatch(batchID: "import-01JD0000000000000000000001", appliedAt: .now)
        context.insert(batch)

        // Setup DailyPlanStore
        let planHeader = PlanHeader(id: "plan-01JD0000000000000000000002", createdAt: .now)
        let plan = DailyPlan(header: planHeader, date: "2026-11-20", validUntil: Date.now.addingTimeInterval(3600), reviewScope: ["csc301"], new: [])
        DailyPlanStore.shared.applyPlan(plan)
        defer { DailyPlanStore.shared.reset() }

        // Setup Course, Unit, Concept, Prompts
        let course = Course(externalID: "csc301", name: "Operating Systems")
        context.insert(course)
        let unit = CourseUnit(externalID: "csc301.u1", name: "Processes")
        unit.course = course
        context.insert(unit)

        let concept = Concept(externalID: "csc301.process", title: "Process")
        concept.unit = unit
        concept.introducedAt = Date(timeIntervalSince1970: 1732071600) // 2024-11-20T03:00:00Z
        concept.dueDate = Date(timeIntervalSince1970: 1732158000) // 2024-11-21T03:00:00Z
        concept.ease = 2.5
        concept.intervalDays = 1.0
        concept.lapses = 0
        context.insert(concept)

        let prompt = Prompt(
            externalID: "csc301.process.flashcard.1",
            content: .flashcard(.init(front: "What is a process?", back: "A program in execution")),
            origin: .imported
        )
        prompt.concept = concept
        context.insert(prompt)

        // AI variant that must be excluded from state.json
        let variant = Prompt(
            externalID: "csc301.process.flashcard.variant",
            content: .flashcard(.init(front: "Process definition?", back: "A program in execution")),
            origin: .aiVariant
        )
        variant.concept = concept
        variant.sourcePrompt = prompt
        context.insert(variant)

        try context.save()

        let now = Date(timeIntervalSince1970: 1732071600)
        let exporter = StateExporter(context: context, handoffFolder: folder)
        let stateURL = try exporter.exportState(now: now)

        #expect(FileManager.default.fileExists(atPath: stateURL.path))
        #expect(stateURL.lastPathComponent == "state.json")

        // Temporary file should not exist
        let tmpURL = folder.fromEncoreURL.appending(path: ".state.json.tmp")
        #expect(!FileManager.default.fileExists(atPath: tmpURL.path))

        let data = try Data(contentsOf: stateURL)
        let document = try StateDocument.decode(from: data)

        #expect(document.header.schema == "encore.state")
        #expect(document.header.version == 1)
        #expect(document.header.producer == "encore 1.0")
        #expect(document.appliedBatches == ["import-01JD0000000000000000000001"])
        #expect(document.planIdSeen == "plan-01JD0000000000000000000002")

        #expect(document.concepts.count == 1)
        #expect(document.concepts[0].conceptId == "csc301.process")
        #expect(document.concepts[0].suspended == false)
        #expect(document.concepts[0].introducedAt != nil)

        #expect(document.prompts.count == 1)
        #expect(document.prompts[0].promptId == "csc301.process.flashcard.1")
        #expect(document.prompts[0].conceptId == "csc301.process")
        #expect(document.prompts[0].ease == 2.5)
        #expect(document.prompts[0].interval == 1.0)
        #expect(document.prompts[0].lapses == 0)
        #expect(document.prompts[0].suspended == false)
    }

    @Test func exportAttemptsOutputsJSONLAndMarksExported() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let course = Course(externalID: "csc301", name: "Operating Systems")
        context.insert(course)
        let unit = CourseUnit(externalID: "csc301.u1", name: "Processes")
        unit.course = course
        context.insert(unit)

        let concept = Concept(externalID: "csc301.process", title: "Process")
        concept.unit = unit
        context.insert(concept)

        let prompt = Prompt(
            externalID: "csc301.process.flashcard.1",
            content: .flashcard(.init(front: "What is a process?", back: "A program in execution")),
            origin: .imported
        )
        prompt.concept = concept
        context.insert(prompt)
        try context.save()

        // Create a plan session and record answer
        let engine = try SessionEngine(
            queue: [.init(conceptID: "csc301.process", promptID: "csc301.process.flashcard.1", unitID: "csc301.u1")],
            config: .init(),
            context: context,
            supportsCodeExecution: false,
            sessionKind: "plan"
        )
        let answeredAt = Date(timeIntervalSince1970: 1732069800)
        try engine.answer(.good, duration: 4.5, answerText: "A program in execution", now: answeredAt)

        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        #expect(logs[0].exportedAt == nil)
        #expect(logs[0].answerText == "A program in execution")
        #expect(logs[0].sessionKind == "plan")
        #expect(logs[0].calibrated == true)

        let exporter = StateExporter(context: context, handoffFolder: folder)
        let exportNow = Date(timeIntervalSince1970: 1732071600)
        let attemptsURL = try #require(try exporter.exportAttempts(now: exportNow))

        #expect(FileManager.default.fileExists(atPath: attemptsURL.path))
        #expect(attemptsURL.lastPathComponent.hasPrefix("attempts-"))
        #expect(attemptsURL.lastPathComponent.hasSuffix(".jsonl"))

        // Check file lines
        let contents = try String(contentsOf: attemptsURL, encoding: .utf8)
        let lines = contents.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        #expect(lines.count == 2)

        let headerData = try #require(lines[0].data(using: .utf8))
        let headerObj = try #require(try JSONSerialization.jsonObject(with: headerData) as? [String: Any])
        #expect(headerObj["schema"] as? String == "encore.attempt")
        #expect(headerObj["version"] as? Int == 1)
        #expect(headerObj["producer"] as? String == "encore 1.0")

        let attemptData = try #require(lines[1].data(using: .utf8))
        let attemptObj = try #require(try JSONSerialization.jsonObject(with: attemptData) as? [String: Any])
        #expect(attemptObj["promptId"] as? String == "csc301.process.flashcard.1")
        #expect(attemptObj["conceptId"] as? String == "csc301.process")
        #expect(attemptObj["answerText"] as? String == "A program in execution")
        #expect(attemptObj["grade"] as? Int == 3) // good == 3
        #expect(attemptObj["msTaken"] as? Int == 4500) // 4.5s -> 4500ms
        #expect(attemptObj["sessionKind"] as? String == "plan")
        #expect(attemptObj["calibrated"] as? Bool == true)

        // Attempt should now be marked exported
        let updatedLogs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(updatedLogs[0].exportedAt == exportNow)

        // Second export produces nil since no unexported attempts remain
        let secondURL = try exporter.exportAttempts(now: exportNow)
        #expect(secondURL == nil)
    }

    @Test func exportAfterSessionContainsExactlyThatSessionsAttempts() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let course = Course(externalID: "c1", name: "Course")
        context.insert(course)
        let unit = CourseUnit(externalID: "c1.u1", name: "Unit")
        unit.course = course
        context.insert(unit)

        let concept1 = Concept(externalID: "c1.k1", title: "Concept 1")
        concept1.unit = unit
        let prompt1 = Prompt(externalID: "c1.p1", content: .flashcard(.init(front: "Q1", back: "A1")))
        prompt1.concept = concept1
        context.insert(concept1)
        context.insert(prompt1)

        let concept2 = Concept(externalID: "c1.k2", title: "Concept 2")
        concept2.unit = unit
        let prompt2 = Prompt(externalID: "c1.p2", content: .flashcard(.init(front: "Q2", back: "A2")))
        prompt2.concept = concept2
        context.insert(concept2)
        context.insert(prompt2)
        try context.save()

        let exporter = StateExporter(context: context, handoffFolder: folder)

        // First session runs and finishes
        let engine1 = try SessionEngine(
            queue: [.init(conceptID: "c1.k1", promptID: "c1.p1", unitID: "c1.u1")],
            config: .init(),
            context: context,
            supportsCodeExecution: false
        )
        try engine1.answer(.easy, duration: 2.0, answerText: "Ans1")
        try engine1.finish()

        let file1 = try #require(try exporter.exportAttempts(now: .now))
        let lines1 = (try String(contentsOf: file1, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        #expect(lines1.count == 2) // Header + 1 attempt

        // Second session runs and finishes
        let engine2 = try SessionEngine(
            queue: [.init(conceptID: "c1.k2", promptID: "c1.p2", unitID: "c1.u1")],
            config: .init(),
            context: context,
            supportsCodeExecution: false
        )
        try engine2.answer(.again, duration: 1.5, answerText: "Ans2")
        try engine2.finish()

        let file2 = try #require(try exporter.exportAttempts(now: .now))
        let lines2 = (try String(contentsOf: file2, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        #expect(lines2.count == 2) // Header + 1 attempt from session 2 only!

        let attemptData = try #require(lines2[1].data(using: .utf8))
        let attemptObj = try #require(try JSONSerialization.jsonObject(with: attemptData) as? [String: Any])
        #expect(attemptObj["promptId"] as? String == "c1.p2")
        #expect(attemptObj["answerText"] as? String == "Ans2")
        #expect(attemptObj["grade"] as? Int == 1) // again == 1
    }

    @Test func launchExportProducesStateNewerThanLaunch() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let launchTime = Date.now
        let result = StateExporter.exportOnLaunch(context: context, folder: folder, now: launchTime)
        let stateURL = try #require(result?.stateURL)

        #expect(FileManager.default.fileExists(atPath: stateURL.path))
        let data = try Data(contentsOf: stateURL)
        let document = try StateDocument.decode(from: data)

        let exportedDate = try #require(ExportDateFormatter.date(from: document.exportedAt))
        #expect(exportedDate.timeIntervalSince1970 >= launchTime.timeIntervalSince1970 - 1)
    }
}
