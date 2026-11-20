import Foundation

/// A reference to a source file, page or time segment supporting a claim.
public struct Citation: Codable, Hashable, Sendable {
    public var sourceFileId: String
    public var page: Int?
    public var startSec: Double?
    public var endSec: Double?
    public var quote: String
    public var status: String
    public var verifiedBy: String?

    public init(
        sourceFileId: String,
        page: Int? = nil,
        startSec: Double? = nil,
        endSec: Double? = nil,
        quote: String,
        status: String = "verified",
        verifiedBy: String? = nil
    ) {
        self.sourceFileId = sourceFileId
        self.page = page
        self.startSec = startSec
        self.endSec = endSec
        self.quote = quote
        self.status = status
        self.verifiedBy = verifiedBy
    }
}

/// A statement of fact or definition with provenance and citations.
public struct Claim: Codable, Hashable, Sendable {
    public var text: String
    public var provenance: String
    public var citations: [Citation]

    public init(text: String, provenance: String = "cited", citations: [Citation] = []) {
        self.text = text
        self.provenance = provenance
        self.citations = citations
    }
}

/// Detailed knowledge claims and citations for a concept.
public struct ConceptDetails: Codable, Hashable, Sendable {
    public var explanationCitations: [Citation]
    public var aliases: [String]
    public var useWhen: [Claim]
    public var conditions: [Claim]
    public var workedExamples: [Claim]

    public init(
        explanationCitations: [Citation] = [],
        aliases: [String] = [],
        useWhen: [Claim] = [],
        conditions: [Claim] = [],
        workedExamples: [Claim] = []
    ) {
        self.explanationCitations = explanationCitations
        self.aliases = aliases
        self.useWhen = useWhen
        self.conditions = conditions
        self.workedExamples = workedExamples
    }
}

/// Contrast between two concepts in a contrast group.
public struct ContrastPair: Codable, Hashable, Sendable {
    public var conceptA: String
    public var conceptB: String
    public var decidingFeature: Claim

    public init(conceptA: String, conceptB: String, decidingFeature: Claim) {
        self.conceptA = conceptA
        self.conceptB = conceptB
        self.decidingFeature = decidingFeature
    }
}

/// A group of confusable or related concepts.
public struct ContrastGroup: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var question: String?
    public var memberIds: [String]
    public var contrasts: [ContrastPair]

    public init(
        id: String,
        name: String,
        question: String? = nil,
        memberIds: [String] = [],
        contrasts: [ContrastPair] = []
    ) {
        self.id = id
        self.name = name
        self.question = question
        self.memberIds = memberIds
        self.contrasts = contrasts
    }
}

/// A lecture slide deck, reading or transcript source file.
public struct SourceFile: Codable, Hashable, Sendable {
    public var id: String
    public var origin: String
    public var displayName: String
    public var pageCount: Int?
    public var contentHash: String
    public var canvasFileId: Int?

    public init(
        id: String,
        origin: String = "canvas",
        displayName: String,
        pageCount: Int? = nil,
        contentHash: String,
        canvasFileId: Int? = nil
    ) {
        self.id = id
        self.origin = origin
        self.displayName = displayName
        self.pageCount = pageCount
        self.contentHash = contentHash
        self.canvasFileId = canvasFileId
    }
}
