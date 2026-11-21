import Foundation
import EncoreKit
import SwiftData
import Testing

@MainActor
struct LibraryExporterTests {
    private func makeTemporaryHandoffFolder() -> (HandoffFolder, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "encore-lib-test-\(UUID().uuidString)")
        let folder = HandoffFolder(rootURL: tempDir)
        return (folder, tempDir)
    }

    @Test func exportLibraryProducesValidDocumentMatchingSchemaAndFixtures() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup Course with units
        let course = Course(externalID: "csc301", name: "Operating Systems")
        context.insert(course)

        let unit1 = CourseUnit(externalID: "csc301.u.processes", name: "Processes", sortIndex: 0)
        unit1.course = course
        context.insert(unit1)

        let unit2 = CourseUnit(externalID: "csc301.u.memory", name: "Virtual Memory", sortIndex: 1)
        unit2.course = course
        context.insert(unit2)

        // Setup Exam
        let examDate = Date(timeIntervalSince1970: 1733400000) // 2024-12-05
        let exam = Exam(externalID: "csc301.x.midterm", name: "Midterm", date: examDate)
        exam.course = course
        exam.units = [unit1]
        context.insert(exam)

        // Setup Concepts (active and retired)
        let concept1 = Concept(
            externalID: "csc301.process",
            title: "Process",
            explanation: "A running program.",
            kind: "definition",
            tier: "core",
            status: "active"
        )
        concept1.unit = unit1
        context.insert(concept1)

        let concept2 = Concept(
            externalID: "csc301.old_idea",
            title: "Old Idea",
            explanation: "Retired concept.",
            kind: "definition",
            tier: "out",
            status: "retired"
        )
        concept2.unit = unit2
        context.insert(concept2)

        try context.save()

        let now = Date(timeIntervalSince1970: 1732071600)
        let exporter = LibraryExporter(context: context, handoffFolder: folder)
        let libraryURL = try exporter.exportLibrary(now: now)

        #expect(FileManager.default.fileExists(atPath: libraryURL.path))
        #expect(libraryURL.lastPathComponent == "library.json")

        // Temporary file should not exist
        let tmpURL = folder.fromEncoreURL.appending(path: ".library.json.tmp")
        #expect(!FileManager.default.fileExists(atPath: tmpURL.path))

        let data = try Data(contentsOf: libraryURL)
        let document = try LibraryDocument.decode(from: data)

        // Verify Header
        #expect(document.header.schema == "encore.library")
        #expect(document.header.version == 1)
        #expect(document.header.producer == "encore 1.0")
        #expect(document.header.id.hasPrefix("lib-"))
        #expect(document.exportedAt == ExportDateFormatter.string(from: now))

        // Verify Courses
        #expect(document.courses.count == 1)
        let exportedCourse = document.courses[0]
        #expect(exportedCourse.id == "csc301")
        #expect(exportedCourse.name == "Operating Systems")
        #expect(exportedCourse.status == "active")
        #expect(exportedCourse.units.count == 2)
        #expect(exportedCourse.units[0].id == "csc301.u.processes")
        #expect(exportedCourse.units[0].name == "Processes")
        #expect(exportedCourse.units[1].id == "csc301.u.memory")
        #expect(exportedCourse.units[1].name == "Virtual Memory")

        // Verify Exams
        #expect(document.exams.count == 1)
        let exportedExam = document.exams[0]
        #expect(exportedExam.id == "csc301.x.midterm")
        #expect(exportedExam.courseId == "csc301")
        #expect(exportedExam.name == "Midterm")
        #expect(exportedExam.unitIds == ["csc301.u.processes"])

        // Verify Concepts
        #expect(document.concepts.count == 2)
        let c1 = document.concepts.first { $0.id == "csc301.process" }
        #expect(c1 != nil)
        #expect(c1?.courseId == "csc301")
        #expect(c1?.unitId == "csc301.u.processes")
        #expect(c1?.title == "Process")
        #expect(c1?.status == "active")

        let c2 = document.concepts.first { $0.id == "csc301.old_idea" }
        #expect(c2 != nil)
        #expect(c2?.courseId == "csc301")
        #expect(c2?.unitId == "csc301.u.memory")
        #expect(c2?.title == "Old Idea")
        #expect(c2?.status == "retired")

        // Verify against raw JSON structure matching fixture
        let jsonObject = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(jsonObject["header"] is [String: Any])
        #expect(jsonObject["exportedAt"] is String)
        #expect(jsonObject["courses"] is [[String: Any]])
        #expect(jsonObject["exams"] is [[String: Any]])
        #expect(jsonObject["concepts"] is [[String: Any]])
    }

    @Test func exportLibraryWithEmptyStore() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exporter = LibraryExporter(context: context, handoffFolder: folder)
        let libraryURL = try exporter.exportLibrary()

        #expect(FileManager.default.fileExists(atPath: libraryURL.path))
        let data = try Data(contentsOf: libraryURL)
        let document = try LibraryDocument.decode(from: data)

        #expect(document.header.schema == "encore.library")
        #expect(document.courses.isEmpty)
        #expect(document.exams.isEmpty)
        #expect(document.concepts.isEmpty)
    }

    @Test func exportOnLaunchProducesLibraryAndState() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let launchTime = Date.now
        let result = StateExporter.exportOnLaunch(context: context, folder: folder, now: launchTime)
        let urls = try #require(result)

        #expect(FileManager.default.fileExists(atPath: urls.stateURL.path))
        #expect(FileManager.default.fileExists(atPath: urls.libraryURL.path))
        #expect(urls.libraryURL.lastPathComponent == "library.json")

        let libData = try Data(contentsOf: urls.libraryURL)
        let libDoc = try LibraryDocument.decode(from: libData)
        #expect(libDoc.header.schema == "encore.library")
    }

    @Test func libraryExportOverwritesExistingAtomically() throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext

        let (folder, tempDir) = makeTemporaryHandoffFolder()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let course = Course(externalID: "c1", name: "Course 1")
        context.insert(course)
        try context.save()

        let exporter = LibraryExporter(context: context, handoffFolder: folder)
        let url1 = try exporter.exportLibrary()

        let doc1 = try LibraryDocument.decode(from: try Data(contentsOf: url1))
        #expect(doc1.courses.count == 1)

        // Add second course and export again
        let course2 = Course(externalID: "c2", name: "Course 2")
        context.insert(course2)
        try context.save()

        let url2 = try exporter.exportLibrary()
        #expect(url1 == url2)

        let doc2 = try LibraryDocument.decode(from: try Data(contentsOf: url2))
        #expect(doc2.courses.count == 2)
    }
}
