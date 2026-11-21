import Foundation
import SwiftData

/// Reason for flagging a prompt or card as problematic.
public enum FlagReason: String, Codable, CaseIterable, Sendable {
    case wrong
    case unclear
    case duplicate
    case other

    public var displayName: String {
        switch self {
        case .wrong: "Factually wrong"
        case .unclear: "Unclear or ambiguous"
        case .duplicate: "Duplicate concept"
        case .other: "Other"
        }
    }
}

/// Header for encore.flag schema v1.
public struct FlagHeader: Codable, Hashable, Sendable {
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
        schema: String = "encore.flag",
        version: Int = 1,
        id: String,
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

/// Document representation of encore.flag v1.
public struct FlagDocument: Codable, Hashable, Sendable {
    public var header: FlagHeader
    public var flagId: String
    public var promptId: String
    public var conceptId: String
    public var reason: FlagReason
    public var note: String
    public var suggestedFix: String?
    public var flaggedAt: String

    public init(
        flagId: UUID = UUID(),
        promptId: String,
        conceptId: String,
        reason: FlagReason,
        note: String = "",
        suggestedFix: String? = nil,
        flaggedAt: Date = .now
    ) {
        let flagIdString = flagId.uuidString.lowercased()
        let formattedDate = ExportDateFormatter.string(from: flaggedAt)
        self.header = FlagHeader(
            schema: "encore.flag",
            version: 1,
            id: "flag-\(flagIdString)",
            createdAt: formattedDate,
            producer: "encore 1.0"
        )
        self.flagId = flagIdString
        self.promptId = promptId
        self.conceptId = conceptId
        self.reason = reason
        self.note = note
        let trimmedFix = suggestedFix?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.suggestedFix = (trimmedFix?.isEmpty == false) ? trimmedFix : nil
        self.flaggedAt = formattedDate
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> FlagDocument {
        try JSONDecoder().decode(FlagDocument.self, from: data)
    }
}

/// Writes card flags to Handoff/from-encore/ atomically.
public struct FlagExporter: Sendable {
    public let handoffFolder: HandoffFolder

    public init(handoffFolder: HandoffFolder = HandoffFolder()) {
        self.handoffFolder = handoffFolder
    }

    /// Atomically writes a flag document to `from-encore/flag-<flagId>.json`.
    @discardableResult
    public func exportFlag(_ document: FlagDocument) throws -> URL {
        try handoffFolder.createDirectoriesIfNeeded()
        let filename = "flag-\(document.flagId).json"
        let destinationURL = handoffFolder.fromEncoreURL.appending(path: filename)
        let data = try document.encoded()
        try StateExporter.writeAtomically(data: data, to: destinationURL)
        return destinationURL
    }

    /// Helper to export a flag for a given `Prompt`.
    @discardableResult
    public func exportFlag(
        for prompt: Prompt,
        concept: Concept? = nil,
        reason: FlagReason,
        note: String = "",
        suggestedFix: String? = nil,
        flagId: UUID = UUID(),
        now: Date = .now
    ) throws -> URL {
        let effectiveConcept = concept ?? prompt.concept
        let conceptId = effectiveConcept?.externalID ?? ""
        let promptId = (prompt.origin == .aiVariant ? prompt.sourcePrompt?.externalID : prompt.externalID) ?? prompt.externalID
        let document = FlagDocument(
            flagId: flagId,
            promptId: promptId,
            conceptId: conceptId,
            reason: reason,
            note: note,
            suggestedFix: suggestedFix,
            flaggedAt: now
        )
        return try exportFlag(document)
    }
}
