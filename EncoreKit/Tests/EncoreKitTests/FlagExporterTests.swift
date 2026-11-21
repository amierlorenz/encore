import Foundation
import EncoreKit
import SwiftData
import Testing

@MainActor
struct FlagExporterTests {
    private func makeTemporaryHandoffFolder() -> (HandoffFolder, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "encore-flag-test-\(UUID().uuidString)")
        let folder = HandoffFolder(rootURL: tempDir)
        return (folder, tempDir)
    }

    @Test func exportFlagWritesValidJSONFileAtomically() throws {
        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exporter = FlagExporter(handoffFolder: folder)
        let flagId = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1732071600)

        let doc = FlagDocument(
            flagId: flagId,
            promptId: "csc301.process.flashcard.1",
            conceptId: "csc301.process",
            reason: .wrong,
            note: "Typo in definition",
            suggestedFix: "Program in execution.",
            flaggedAt: fixedDate
        )

        let fileURL = try exporter.exportFlag(doc)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(fileURL.lastPathComponent == "flag-\(flagId.uuidString.lowercased()).json")

        // Temporary file should not exist
        let tmpURL = folder.fromEncoreURL.appending(path: ".flag-\(flagId.uuidString.lowercased()).json.tmp")
        #expect(!FileManager.default.fileExists(atPath: tmpURL.path))

        let data = try Data(contentsOf: fileURL)
        let decoded = try FlagDocument.decode(from: data)

        #expect(decoded.header.schema == "encore.flag")
        #expect(decoded.header.version == 1)
        #expect(decoded.header.id == "flag-\(flagId.uuidString.lowercased())")
        #expect(decoded.header.producer == "encore 1.0")
        #expect(decoded.flagId == flagId.uuidString.lowercased())
        #expect(decoded.promptId == "csc301.process.flashcard.1")
        #expect(decoded.conceptId == "csc301.process")
        #expect(decoded.reason == .wrong)
        #expect(decoded.note == "Typo in definition")
        #expect(decoded.suggestedFix == "Program in execution.")
    }

    @Test func exportFlagForPromptResolvesConceptAndAIVariantSource() throws {
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

        let sourcePrompt = Prompt(
            externalID: "csc301.process.flashcard.1",
            content: .flashcard(.init(front: "What is a process?", back: "A program in execution")),
            origin: .imported
        )
        sourcePrompt.concept = concept
        context.insert(sourcePrompt)

        // AI variant derived from sourcePrompt
        let variantPrompt = Prompt(
            externalID: "csc301.process.flashcard.variant.99",
            content: .flashcard(.init(front: "Process definition?", back: "A program in execution")),
            origin: .aiVariant
        )
        variantPrompt.concept = concept
        variantPrompt.sourcePrompt = sourcePrompt
        context.insert(variantPrompt)
        try context.save()

        let exporter = FlagExporter(handoffFolder: folder)
        let flagId = UUID()

        let fileURL = try exporter.exportFlag(
            for: variantPrompt,
            reason: .unclear,
            note: "Ambiguous question",
            suggestedFix: nil,
            flagId: flagId
        )

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        let decoded = try FlagDocument.decode(from: data)

        // Should report the source prompt's ID, not the variant ID
        #expect(decoded.promptId == "csc301.process.flashcard.1")
        #expect(decoded.conceptId == "csc301.process")
        #expect(decoded.reason == .unclear)
        #expect(decoded.suggestedFix == nil)
    }

    @Test func flagReasonAllCasesAndDisplayNames() {
        #expect(FlagReason.wrong.rawValue == "wrong")
        #expect(FlagReason.unclear.rawValue == "unclear")
        #expect(FlagReason.duplicate.rawValue == "duplicate")
        #expect(FlagReason.other.rawValue == "other")
        #expect(FlagReason.allCases.count == 4)
    }
}
