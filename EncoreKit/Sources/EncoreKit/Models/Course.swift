import Foundation
import SwiftData

/// A class being studied, such as "CS 101". The top of the content hierarchy.
@Model
public final class Course {
    #Index<Course>([\.externalID])

    /// Stable identifier used to match imported content across re-imports.
    public var externalID: String = UUID().uuidString
    public var name: String = ""
    /// A compact label such as "CSC 395 | Swift"; `nil` shows the full name.
    public var shortName: String?
    /// Whether coding prompt kinds make sense for this class.
    public var allowsCodingPrompts: Bool = false
    public var contrastGroupsData: Data = Data()
    public var sourceFilesData: Data = Data()
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \CourseUnit.course)
    public var units: [CourseUnit]? = []

    @Relationship(deleteRule: .cascade, inverse: \Exam.course)
    public var exams: [Exam]? = []

    public init(externalID: String = UUID().uuidString, name: String) {
        self.externalID = externalID
        self.name = name
    }

    public var contrastGroups: [ContrastGroup] {
        get { (try? JSONDecoder().decode([ContrastGroup].self, from: contrastGroupsData)) ?? [] }
        set { contrastGroupsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var sourceFiles: [SourceFile] {
        get { (try? JSONDecoder().decode([SourceFile].self, from: sourceFilesData)) ?? [] }
        set { sourceFilesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// The short name when set, otherwise the full name.
    public var displayName: String {
        guard let shortName, !shortName.trimmingCharacters(in: .whitespaces).isEmpty else { return name }
        return shortName
    }

    /// The prompt kinds that make sense for this class.
    public var allowedPromptKinds: [PromptKind] {
        PromptKind.allCases.filter { allowsCodingPrompts || !$0.isCoding }
    }

    /// Units ordered by ``CourseUnit/sortIndex``.
    public var sortedUnits: [CourseUnit] {
        (units ?? []).sorted { ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name) }
    }
}
