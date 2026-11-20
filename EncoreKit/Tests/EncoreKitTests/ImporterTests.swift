import Foundation
import EncoreKit
import SwiftData
import Testing

@MainActor
struct ImporterTests {
    let container: ModelContainer
    let context: ModelContext
    let importer: Importer
    let sample: ImportDocument

    init() throws {
        container = try ModelContainerFactory.make(storage: .inMemory)
        context = container.mainContext
        importer = Importer(context: context)
        sample = try ImportDocument.decode(from: ImportDocumentTests.fixture("valid_import"))
    }

    func concept(_ id: String) throws -> Concept {
        try #require(try context.fetch(FetchDescriptor<Concept>(predicate: #Predicate { $0.externalID == id })).first)
    }

    @Test func planDoesNotChangeStore() throws {
        let plan = try importer.plan(sample)
        #expect(plan.courses == .init(new: 1))
        #expect(plan.units == .init(new: 1))
        #expect(plan.concepts == .init(new: 1))
        #expect(plan.prompts == .init(new: 1))
        #expect(plan.exams == .init(new: 1))
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 0)
    }

    @Test func appliesValidImport() throws {
        try importer.apply(sample)

        let proc = try concept("csc301.process")
        #expect(proc.unit?.externalID == "csc301.u.processes")
        #expect(proc.unit?.course?.name == "Operating Systems")
        #expect(proc.unit?.course?.contrastGroups.count == 1)
        #expect(proc.unit?.course?.sourceFiles.count == 1)
        #expect(proc.kind == "definition")
        #expect(proc.tier == "core")
        #expect(proc.status == "active")
        #expect(proc.details.aliases == ["task", "job"])
        #expect(proc.details.explanationCitations.first?.quote == "A process is a program in execution.")
        #expect(proc.prompts?.count == 1)
        #expect(proc.prompts?.first?.externalID == "csc301.process.flashcard.1")
        #expect(proc.prompts?.first?.kind == .flashcard)
        #expect(proc.tags?.map(\.name) == ["processes"])

        let exam = try #require(try context.fetch(FetchDescriptor<Exam>()).first)
        #expect(exam.externalID == "csc301.x.midterm")
        #expect(exam.course?.externalID == "csc301")
        #expect(exam.units?.map(\.externalID) == ["csc301.u.processes"])
        #expect(exam.covers(proc))

        let batches = try context.fetch(FetchDescriptor<AppliedBatch>())
        #expect(batches.count == 1)
        #expect(batches.first?.batchID == "import-01JD0000000000000000000001")
    }

    @Test func reimportIsIdempotent() throws {
        try importer.apply(sample)
        let plan = try importer.plan(sample)
        #expect(!plan.hasChanges)
        #expect(plan.prompts == .init(unchanged: 1))

        try importer.apply(sample)
        #expect(try context.fetchCount(FetchDescriptor<Prompt>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ConceptTag>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AppliedBatch>()) == 1)
    }

    @Test func updatesInPlaceAndKeepsHistory() throws {
        try importer.apply(sample)
        let proc = try concept("csc301.process")
        proc.repetitions = 4
        proc.dueDate = .distantFuture
        let log = ReviewLog(grade: .good, duration: 3, mode: .review, wasDue: true, wasNew: false)
        log.concept = proc
        try context.save()

        var edited = sample
        edited.courses[0].units[0].concepts[0].title = "Updated Process Title"
        edited.courses[0].units[0].concepts[0].prompts[0].content = .flashcard(.init(front: "Where is process?", back: "In execution."))
        let plan = try importer.apply(edited)

        #expect(plan.concepts == .init(updated: 1, unchanged: 0))
        #expect(plan.prompts == .init(updated: 1, unchanged: 0))
        #expect(proc.title == "Updated Process Title")
        #expect(proc.repetitions == 4)
        #expect(proc.dueDate == .distantFuture)
        #expect(proc.reviews?.count == 1)
    }

    @Test func retiredConceptDisappearsFromSessionsButKeepsHistory() throws {
        try importer.apply(sample)
        let proc = try concept("csc301.process")
        proc.repetitions = 2
        let log = ReviewLog(grade: .good, duration: 2, mode: .learnNew, wasDue: false, wasNew: true)
        log.concept = proc
        try context.save()

        var rng = SeededGenerator(seed: 42)
        let builder = SessionBuilder(
            config: SessionConfig(scope: .init(), mode: .practice, length: .count(10), promptKinds: Set(PromptKind.allCases)),
            newRemaining: 10,
            supportsCodeExecution: true
        )

        let initialQueue = builder.build(from: [ConceptSnapshot(proc)], now: .now, using: &rng)
        #expect(initialQueue.count == 1)

        // Retire the concept
        var retiredDoc = sample
        retiredDoc.courses[0].units[0].concepts[0].status = "retired"
        try importer.apply(retiredDoc)

        #expect(proc.isRetired)
        #expect(proc.reviews?.count == 1) // Review history kept!

        let retiredQueue = builder.build(from: [ConceptSnapshot(proc)], now: .now, using: &rng)
        #expect(retiredQueue.isEmpty) // Retired concept disappears from sessions!

        // Un-retire the concept
        var unretiredDoc = sample
        unretiredDoc.courses[0].units[0].concepts[0].status = "active"
        try importer.apply(unretiredDoc)

        #expect(!proc.isRetired)
        let unretiredQueue = builder.build(from: [ConceptSnapshot(proc)], now: .now, using: &rng)
        #expect(unretiredQueue.count == 1)
    }

    @Test func changedContentRemovesStaleVariants() throws {
        try importer.apply(sample)
        let source = try #require(try concept("csc301.process").prompts?.first { $0.externalID == "csc301.process.flashcard.1" })
        let variant = Prompt(content: .flashcard(.init(front: "Reworded", back: "Execution.")), origin: .aiVariant)
        variant.concept = source.concept
        variant.sourcePrompt = source
        try context.save()

        var edited = sample
        edited.courses[0].units[0].concepts[0].prompts[0].content = .flashcard(.init(front: "New front", back: "New back"))
        try importer.apply(edited)

        #expect(source.variants?.isEmpty == true)
        #expect(try context.fetchCount(FetchDescriptor<Prompt>()) == 1)
    }

    @Test func refusesInvalidDocument() throws {
        var broken = sample
        broken.header.version = 99
        #expect(throws: Importer.Failure.self) {
            try importer.apply(broken)
        }
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 0)
    }

    @Test func unknownVersionLandsInFailedWithErrorFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let handoff = HandoffFolder(rootURL: tempDir)
        try handoff.createDirectoriesIfNeeded()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let unknownData = try ImportDocumentTests.fixture("unknown_version")
        let sourceURL = handoff.toEncoreURL.appending(path: "unknown_version.json")
        try unknownData.write(to: sourceURL)

        #expect(throws: (any Error).self) {
            try importer.importFile(at: sourceURL, handoff: handoff)
        }

        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        let failedFile = handoff.failedURL.appending(path: "unknown_version.json")
        #expect(FileManager.default.fileExists(atPath: failedFile.path))

        let errorFile1 = handoff.failedURL.appending(path: "unknown_version.error.txt")
        let errorFile2 = handoff.failedURL.appending(path: "future-version.error.txt")
        let hasErrorFile = FileManager.default.fileExists(atPath: errorFile1.path)
            || FileManager.default.fileExists(atPath: errorFile2.path)
        #expect(hasErrorFile)
    }

    @Test func successfulImportDeletesFileAndRecordsAppliedBatch() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let handoff = HandoffFolder(rootURL: tempDir)
        try handoff.createDirectoriesIfNeeded()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let validData = try ImportDocumentTests.fixture("valid_import")
        let sourceURL = handoff.toEncoreURL.appending(path: "import-01JD.json")
        try validData.write(to: sourceURL)

        let plan = try importer.importFile(at: sourceURL, handoff: handoff)
        #expect(plan.concepts.new == 1)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))

        let batches = try context.fetch(FetchDescriptor<AppliedBatch>())
        #expect(batches.contains { $0.batchID == "import-01JD0000000000000000000001" })
    }
}
