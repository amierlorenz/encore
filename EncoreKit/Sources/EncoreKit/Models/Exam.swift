import Foundation
import SwiftData

/// A graded test covering some units and tags of a course.
///
/// Concepts an upcoming exam covers are scheduled so they come up before its date.
@Model
public final class Exam {
    #Index<Exam>([\.externalID], [\.date])

    public var externalID: String = UUID().uuidString
    public var name: String = ""
    public var date: Date = Date.now
    public var kind: String = "test"

    public var course: Course?

    @Relationship(deleteRule: .nullify, inverse: \CourseUnit.exams)
    public var units: [CourseUnit]? = []

    @Relationship(deleteRule: .nullify, inverse: \ConceptTag.exams)
    public var tags: [ConceptTag]? = []

    public init(externalID: String = UUID().uuidString, name: String, date: Date, kind: String = "test") {
        self.externalID = externalID
        self.name = name
        self.date = date
        self.kind = kind
    }

    /// Whether the exam covers a concept through one of its units or tags.
    public func covers(_ concept: Concept) -> Bool {
        if let unit = concept.unit, (units ?? []).contains(where: { $0 === unit }) {
            return true
        }
        let examTags = Set((tags ?? []).map(\.name))
        return (concept.tags ?? []).contains { examTags.contains($0.name) }
    }
}
