import Foundation
import SwiftData

/// One idea to learn. Concepts are the unit of scheduling: each has a single
/// review schedule shared by all of its prompts.
@Model
public final class Concept {
    #Index<Concept>([\.externalID], [\.dueDate])

    public var externalID: String = UUID().uuidString
    public var title: String = ""
    /// Markdown with optional LaTeX, shown after answering.
    public var explanation: String = ""
    public var kind: String = "definition"
    public var tier: String = "standard"
    public var status: String = "active"
    public var groupIds: [String] = []
    public var detailsData: Data = Data()
    public var resources: [Resource] = []
    public var createdAt: Date = Date.now

    public var ease: Double = 2.5
    public var intervalDays: Double = 0
    public var repetitions: Int = 0
    public var lapses: Int = 0
    public var dueDate: Date?
    public var lastReviewedAt: Date?
    /// When the concept was first studied; `nil` means the concept is new.
    public var introducedAt: Date?

    public var unit: CourseUnit?

    @Relationship(deleteRule: .nullify, inverse: \ConceptTag.concepts)
    public var tags: [ConceptTag]? = []

    @Relationship(deleteRule: .cascade, inverse: \Prompt.concept)
    public var prompts: [Prompt]? = []

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.concept)
    public var reviews: [ReviewLog]? = []

    public init(
        externalID: String = UUID().uuidString,
        title: String,
        explanation: String = "",
        kind: String = "definition",
        tier: String = "standard",
        status: String = "active",
        details: ConceptDetails = ConceptDetails(),
        groupIds: [String] = [],
        resources: [Resource] = []
    ) {
        self.externalID = externalID
        self.title = title
        self.explanation = explanation
        self.kind = kind
        self.tier = tier
        self.status = status
        self.groupIds = groupIds
        self.resources = resources
        self.detailsData = (try? JSONEncoder().encode(details)) ?? Data()
    }

    public var isNew: Bool { introducedAt == nil }
    public var isRetired: Bool { status == "retired" }

    public var details: ConceptDetails {
        get { (try? JSONDecoder().decode(ConceptDetails.self, from: detailsData)) ?? ConceptDetails() }
        set { detailsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

/// A link to outside material about a concept.
public struct Resource: Codable, Hashable, Sendable {
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }

    /// Parses one resource per line in the form `Title | https://…`.
    ///
    /// A line with only a URL uses the URL's host as its title. Lines without a
    /// valid `http` or `https` URL are skipped.
    public static func parse(lines text: String) -> [Resource] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let urlText = parts.last, let url = URL(string: urlText),
                  let scheme = url.scheme, ["http", "https"].contains(scheme) else { return nil }
            let title = parts.count == 2 && !parts[0].isEmpty ? parts[0] : (url.host() ?? urlText)
            return Resource(title: title, url: url)
        }
    }

    /// The inverse of ``parse(lines:)``.
    public static func format(lines resources: [Resource]) -> String {
        resources.map { "\($0.title) | \($0.url.absoluteString)" }.joined(separator: "\n")
    }
}
