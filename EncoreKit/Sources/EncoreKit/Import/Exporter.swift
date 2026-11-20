import Foundation
import SwiftData

/// Writes the whole store as an ``ImportDocument`` for backups and round trips.
///
/// AI variants and review history are not exported; variants are regenerated
/// and history stays in iCloud.
public struct Exporter {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func document() throws -> ImportDocument {
        let courses = try context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.name)]))
        let exams = try context.fetch(FetchDescriptor<Exam>(sortBy: [SortDescriptor(\.date)]))
        let header = ImportHeader(
            schema: "encore.import",
            version: 2,
            id: "export-\(UUID().uuidString)",
            createdAt: ISO8601DateFormatter().string(from: Date.now),
            producer: "encore 1.0"
        )
        return ImportDocument(
            header: header,
            courses: courses.map(Self.export),
            exams: exams.compactMap(Self.export)
        )
    }

    private static func export(_ course: Course) -> ImportDocument.Course {
        .init(
            id: course.externalID,
            name: course.name,
            shortName: course.shortName,
            coding: course.allowsCodingPrompts ? true : nil,
            units: course.sortedUnits.map(export),
            contrastGroups: course.contrastGroups,
            sourceFiles: course.sourceFiles
        )
    }

    private static func export(_ unit: CourseUnit) -> ImportDocument.Unit {
        let concepts = (unit.concepts ?? []).sorted { ($0.createdAt, $0.externalID) < ($1.createdAt, $1.externalID) }
        return .init(id: unit.externalID, name: unit.name, order: unit.sortIndex, concepts: concepts.map(export))
    }

    private static func export(_ concept: Concept) -> ImportDocument.Concept {
        let prompts = (concept.prompts ?? [])
            .filter { $0.origin != .aiVariant }
            .sorted { ($0.createdAt, $0.externalID) < ($1.createdAt, $1.externalID) }
            .compactMap { prompt in
                prompt.content.map {
                    ImportDocument.Prompt(id: prompt.externalID, kind: prompt.kind.rawValue, status: prompt.status, content: $0)
                }
            }
        return .init(
            id: concept.externalID,
            title: concept.title,
            explanation: concept.explanation,
            kind: concept.kind,
            status: concept.status,
            tier: concept.tier,
            details: concept.details,
            groupIds: concept.groupIds,
            tags: (concept.tags ?? []).map(\.name).sorted(),
            prompts: prompts
        )
    }

    private static func export(_ exam: Exam) -> ImportDocument.Exam? {
        guard let course = exam.course else { return nil }
        let dateString = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().format(exam.date)
        return .init(
            id: exam.externalID,
            courseId: course.externalID,
            name: exam.name,
            date: dateString,
            kind: exam.kind,
            unitIds: (exam.units ?? []).map(\.externalID).sorted()
        )
    }
}
