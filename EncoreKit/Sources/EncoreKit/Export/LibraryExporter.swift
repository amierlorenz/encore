import Foundation
import SwiftData

/// Header for encore.library schema v1.
public struct LibraryHeader: Codable, Hashable, Sendable {
    public var schema: String
    public var version: Int
    public var id: String
    public var createdAt: String
    public var producer: String

    private enum CodingKeys: String, CodingKey {
        case schema
        case version
        case id
        case createdAt = "created_at"
        case producer
    }

    public init(
        schema: String = "encore.library",
        version: Int = 1,
        id: String = "lib-\(UUID().uuidString.lowercased())",
        createdAt: String = ExportDateFormatter.string(from: .now),
        producer: String = "encore 1.0"
    ) {
        self.schema = schema
        self.version = version
        self.id = id
        self.createdAt = createdAt
        self.producer = producer
    }
}

/// Unit entry in a course within encore.library v1.
public struct LibraryUnit: Codable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Course entry in encore.library v1.
public struct LibraryCourse: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var units: [LibraryUnit]
    public var status: String

    public init(id: String, name: String, units: [LibraryUnit] = [], status: String = "active") {
        self.id = id
        self.name = name
        self.units = units
        self.status = status
    }
}

/// Exam entry in encore.library v1.
public struct LibraryExam: Codable, Hashable, Sendable {
    public var id: String
    public var courseId: String
    public var name: String
    public var date: String
    public var unitIds: [String]

    public init(id: String, courseId: String, name: String, date: String, unitIds: [String] = []) {
        self.id = id
        self.courseId = courseId
        self.name = name
        self.date = date
        self.unitIds = unitIds
    }
}

/// Concept entry in encore.library v1.
public struct LibraryConcept: Codable, Hashable, Sendable {
    public var id: String
    public var courseId: String
    public var unitId: String
    public var title: String
    public var status: String

    public init(id: String, courseId: String, unitId: String, title: String, status: String = "active") {
        self.id = id
        self.courseId = courseId
        self.unitId = unitId
        self.title = title
        self.status = status
    }
}

/// Document format for encore.library v1.
public struct LibraryDocument: Codable, Hashable, Sendable {
    public var header: LibraryHeader
    public var exportedAt: String
    public var courses: [LibraryCourse]
    public var exams: [LibraryExam]
    public var concepts: [LibraryConcept]

    public init(
        header: LibraryHeader = LibraryHeader(),
        exportedAt: String = ExportDateFormatter.string(from: .now),
        courses: [LibraryCourse] = [],
        exams: [LibraryExam] = [],
        concepts: [LibraryConcept] = []
    ) {
        self.header = header
        self.exportedAt = exportedAt
        self.courses = courses
        self.exams = exams
        self.concepts = concepts
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> LibraryDocument {
        try JSONDecoder().decode(LibraryDocument.self, from: data)
    }
}

/// Exports library content (courses, units, exams, concepts) to Handoff/from-encore/library.json.
public struct LibraryExporter {
    private let context: ModelContext
    private let handoffFolder: HandoffFolder

    public init(context: ModelContext, handoffFolder: HandoffFolder = HandoffFolder()) {
        self.context = context
        self.handoffFolder = handoffFolder
    }

    /// Exports library.json snapshot.
    @discardableResult
    public func exportLibrary(now: Date = .now) throws -> URL {
        try handoffFolder.createDirectoriesIfNeeded()

        let courses = try context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.externalID)]))
        let libraryCourses = courses.map { course in
            let sortedUnits = course.sortedUnits.map { unit in
                LibraryUnit(id: unit.externalID, name: unit.name)
            }
            return LibraryCourse(
                id: course.externalID,
                name: course.name,
                units: sortedUnits,
                status: "active"
            )
        }

        let exams = try context.fetch(FetchDescriptor<Exam>(sortBy: [SortDescriptor(\.externalID)]))
        let libraryExams = exams.map { exam in
            let dateString = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().format(exam.date)
            let unitIds = (exam.units ?? []).map(\.externalID).sorted()
            return LibraryExam(
                id: exam.externalID,
                courseId: exam.course?.externalID ?? "",
                name: exam.name,
                date: dateString,
                unitIds: unitIds
            )
        }

        let concepts = try context.fetch(FetchDescriptor<Concept>(sortBy: [SortDescriptor(\.externalID)]))
        let libraryConcepts = concepts.map { concept in
            LibraryConcept(
                id: concept.externalID,
                courseId: concept.unit?.course?.externalID ?? "",
                unitId: concept.unit?.externalID ?? "",
                title: concept.title,
                status: concept.status
            )
        }

        let exportID = "lib-\(UUID().uuidString.lowercased())"
        let header = LibraryHeader(
            id: exportID,
            createdAt: ExportDateFormatter.string(from: now),
            producer: "encore 1.0"
        )
        let doc = LibraryDocument(
            header: header,
            exportedAt: ExportDateFormatter.string(from: now),
            courses: libraryCourses,
            exams: libraryExams,
            concepts: libraryConcepts
        )

        let data = try doc.encoded()
        let destinationURL = handoffFolder.fromEncoreURL.appending(path: "library.json")
        try StateExporter.writeAtomically(data: data, to: destinationURL)
        return destinationURL
    }

    /// Convenience for launch export.
    @discardableResult
    public static func exportOnLaunch(context: ModelContext, folder: HandoffFolder = HandoffFolder(), now: Date = .now) -> URL? {
        do {
            let exporter = LibraryExporter(context: context, handoffFolder: folder)
            return try exporter.exportLibrary(now: now)
        } catch {
            return nil
        }
    }
}
