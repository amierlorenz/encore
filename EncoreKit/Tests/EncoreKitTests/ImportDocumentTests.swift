import Foundation
import EncoreKit
import Testing

struct ImportDocumentTests {
    static func fixture(_ name: String = "sample-v2") throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func decodesValidImportFixture() throws {
        let document = try ImportDocument.decode(from: Self.fixture("valid_import"))
        #expect(document.header.schema == "encore.import")
        #expect(document.header.version == 2)
        #expect(document.header.id == "import-01JD0000000000000000000001")

        let course = try #require(document.courses.first)
        #expect(course.id == "csc301")
        #expect(course.name == "Operating Systems")
        #expect(course.units.count == 1)
        #expect(course.contrastGroups.count == 1)
        #expect(course.sourceFiles.count == 1)

        let unit = try #require(course.units.first)
        #expect(unit.id == "csc301.u.processes")
        #expect(unit.concepts.count == 1)

        let concept = try #require(unit.concepts.first)
        #expect(concept.id == "csc301.process")
        #expect(concept.kind == "definition")
        #expect(concept.status == "active")
        #expect(concept.tier == "core")
        #expect(concept.details.aliases == ["task", "job"])
        #expect(concept.prompts.count == 1)
        #expect(concept.prompts[0].id == "csc301.process.flashcard.1")
        #expect(concept.prompts[0].kind == "flashcard")

        let exam = try #require(document.exams.first)
        #expect(exam.id == "csc301.x.midterm")
        #expect(exam.unitIds == ["csc301.u.processes"])
    }

    @Test func roundTripsThroughEncoding() throws {
        let document = try ImportDocument.decode(from: Self.fixture("valid_import"))
        #expect(try ImportDocument.decode(from: document.encoded()) == document)
    }

    @Test func rejectsUnknownSchemaVersion() throws {
        #expect(throws: ImportDecodingError.self) {
            try ImportDocument.decode(from: Self.fixture("unknown_version"))
        }
    }

    @Test func ignoresUnknownFields() throws {
        let json = """
        {
          "header": {
            "schema": "encore.import",
            "version": 2,
            "id": "batch-1",
            "created_at": "2026-11-20T12:00:00Z",
            "producer": "articulate",
            "unknownHeaderField": 123
          },
          "unknownRootField": "foo",
          "courses": []
        }
        """
        let doc = try ImportDocument.decode(from: Data(json.utf8))
        #expect(doc.header.id == "batch-1")
    }

    @Test func reportsMissingFieldWithPath() {
        let json = #"{"header": {"schema": "encore.import", "version": 2, "id": "1", "created_at": "now", "producer": "test"}, "courses": [{"id": "c", "units": []}]}"#
        #expect {
            try ImportDocument.decode(from: Data(json.utf8))
        } throws: { error in
            (error as? ImportDecodingError)?.message.hasPrefix("courses.name") == true
                || (error as? ImportDecodingError)?.message.contains("name") == true
        }
    }

    @Test(arguments: [
        ("2026-11-04", true),
        ("2026-11-04T14:30:00Z", true),
        ("Nov 4", false),
    ])
    func parsesExamDates(text: String, isValid: Bool) {
        let exam = ImportDocument.Exam(id: "e", courseId: "c", name: "Exam", date: text)
        #expect((exam.parsedDate() != nil) == isValid)
    }

    @Test func dayOnlyDateIsLocalStartOfDay() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let exam = ImportDocument.Exam(id: "e", courseId: "c", name: "Exam", date: "2026-11-04")
        let date = try #require(exam.parsedDate(in: timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: date) == DateComponents(year: 2026, month: 11, day: 4, hour: 0))
    }
}
