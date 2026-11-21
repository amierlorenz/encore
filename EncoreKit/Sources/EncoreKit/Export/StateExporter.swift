import Foundation
import SwiftData

/// Date formatter for ISO 8601 with internet date time and timezone offset.
public enum ExportDateFormatter {
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// Header for encore.state schema v1.
public struct StateHeader: Codable, Hashable, Sendable {
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
        schema: String = "encore.state",
        version: Int = 1,
        id: String = "state-\(UUID().uuidString.lowercased())",
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

/// Concept state entry in encore.state v1.
public struct StateConcept: Codable, Hashable, Sendable {
    public var conceptId: String
    public var introducedAt: String?
    public var suspended: Bool

    public init(conceptId: String, introducedAt: String? = nil, suspended: Bool = false) {
        self.conceptId = conceptId
        self.introducedAt = introducedAt
        self.suspended = suspended
    }
}

/// Prompt state entry in encore.state v1.
public struct StatePrompt: Codable, Hashable, Sendable {
    public var promptId: String
    public var conceptId: String
    public var due: String?
    public var ease: Double?
    public var interval: Double?
    public var lapses: Int
    public var introducedAt: String?
    public var suspended: Bool

    public init(
        promptId: String,
        conceptId: String,
        due: String? = nil,
        ease: Double? = nil,
        interval: Double? = nil,
        lapses: Int = 0,
        introducedAt: String? = nil,
        suspended: Bool = false
    ) {
        self.promptId = promptId
        self.conceptId = conceptId
        self.due = due
        self.ease = ease
        self.interval = interval
        self.lapses = lapses
        self.introducedAt = introducedAt
        self.suspended = suspended
    }
}

/// Document format for encore.state v1.
public struct StateDocument: Codable, Hashable, Sendable {
    public var header: StateHeader
    public var exportedAt: String
    public var appliedBatches: [String]
    public var planIdSeen: String?
    public var concepts: [StateConcept]
    public var prompts: [StatePrompt]

    public init(
        header: StateHeader = StateHeader(),
        exportedAt: String = ExportDateFormatter.string(from: .now),
        appliedBatches: [String] = [],
        planIdSeen: String? = nil,
        concepts: [StateConcept] = [],
        prompts: [StatePrompt] = []
    ) {
        self.header = header
        self.exportedAt = exportedAt
        self.appliedBatches = appliedBatches
        self.planIdSeen = planIdSeen
        self.concepts = concepts
        self.prompts = prompts
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> StateDocument {
        try JSONDecoder().decode(StateDocument.self, from: data)
    }
}

/// Header for encore.attempt schema v1.
public struct AttemptHeader: Codable, Hashable, Sendable {
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
        schema: String = "encore.attempt",
        version: Int = 1,
        id: String = "export-\(UUID().uuidString.lowercased())",
        createdAt: String = ExportDateFormatter.string(from: .now),
        producer: String = "encore 1.0"
    ) {
        self.schema = schema
        self.version = version
        self.id = id
        self.createdAt = createdAt
        self.producer = producer
    }

    public func encodedLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Single attempt record in attempts-<exportId>.jsonl.
public struct AttemptRecord: Codable, Hashable, Sendable {
    public var attemptId: String
    public var promptId: String
    public var conceptId: String
    public var answeredAt: String
    public var answerText: String
    public var grade: Int
    public var msTaken: Int
    public var sessionKind: String
    public var calibrated: Bool
    /// Additive: the plan the attempt was answered in; omitted outside plan sessions.
    public var planId: String?

    public init(
        attemptId: String,
        promptId: String,
        conceptId: String,
        answeredAt: String,
        answerText: String,
        grade: Int,
        msTaken: Int,
        sessionKind: String,
        calibrated: Bool,
        planId: String? = nil
    ) {
        self.attemptId = attemptId
        self.promptId = promptId
        self.conceptId = conceptId
        self.answeredAt = answeredAt
        self.answerText = answerText
        self.grade = grade
        self.msTaken = msTaken
        self.sessionKind = sessionKind
        self.calibrated = calibrated
        self.planId = planId
    }

    public func encodedLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Exports scheduling state and grading attempts to Handoff/from-encore/.
public struct StateExporter {
    private let context: ModelContext
    private let handoffFolder: HandoffFolder

    public init(context: ModelContext, handoffFolder: HandoffFolder = HandoffFolder()) {
        self.context = context
        self.handoffFolder = handoffFolder
    }

    /// Atomically writes data to a file by writing to `.<name>.tmp` first and then renaming.
    public static func writeAtomically(data: Data, to destinationURL: URL) throws {
        let folder = destinationURL.deletingLastPathComponent()
        let filename = destinationURL.lastPathComponent
        let tmpURL = folder.appending(path: ".\(filename).tmp")

        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        try data.write(to: tmpURL, options: .atomic)

        // Atomically replace destination with tmpURL using rename POSIX
        if fm.fileExists(atPath: destinationURL.path) {
            _ = try? fm.removeItem(at: destinationURL)
        }
        try fm.moveItem(at: tmpURL, to: destinationURL)
    }

    /// Exports state.json snapshot.
    @discardableResult
    public func exportState(now: Date = .now) throws -> URL {
        try handoffFolder.createDirectoriesIfNeeded()

        let batches = try context.fetch(FetchDescriptor<AppliedBatch>(sortBy: [SortDescriptor(\.appliedAt)]))
        let appliedBatches = batches.map(\.batchID)

        let planIdSeen = DailyPlanStore.shared.planIdSeen

        let concepts = try context.fetch(FetchDescriptor<Concept>(sortBy: [SortDescriptor(\.externalID)]))
        let stateConcepts = concepts.map { concept in
            StateConcept(
                conceptId: concept.externalID,
                introducedAt: concept.introducedAt.map(ExportDateFormatter.string),
                suspended: concept.isRetired
            )
        }

        var statePrompts: [StatePrompt] = []
        for concept in concepts {
            let validPrompts = (concept.prompts ?? [])
                .filter { $0.origin != .aiVariant }
                .sorted { $0.externalID < $1.externalID }
            for prompt in validPrompts {
                statePrompts.append(StatePrompt(
                    promptId: prompt.externalID,
                    conceptId: concept.externalID,
                    due: concept.dueDate.map(ExportDateFormatter.string),
                    ease: concept.ease,
                    interval: concept.intervalDays,
                    lapses: concept.lapses,
                    introducedAt: concept.introducedAt.map(ExportDateFormatter.string),
                    suspended: prompt.isRetired || concept.isRetired
                ))
            }
        }
        statePrompts.sort { $0.promptId < $1.promptId }

        let exportID = "state-\(UUID().uuidString.lowercased())"
        let header = StateHeader(
            id: exportID,
            createdAt: ExportDateFormatter.string(from: now),
            producer: "encore 1.0"
        )
        let doc = StateDocument(
            header: header,
            exportedAt: ExportDateFormatter.string(from: now),
            appliedBatches: appliedBatches,
            planIdSeen: planIdSeen,
            concepts: stateConcepts,
            prompts: statePrompts
        )

        let data = try doc.encoded()
        let destinationURL = handoffFolder.fromEncoreURL.appending(path: "state.json")
        try Self.writeAtomically(data: data, to: destinationURL)
        return destinationURL
    }

    /// Exports any unexported ReviewLogs to attempts-<exportId>.jsonl.
    /// If there are no unexported attempts, returns nil.
    @discardableResult
    public func exportAttempts(now: Date = .now) throws -> URL? {
        try handoffFolder.createDirectoriesIfNeeded()

        let predicate = #Predicate<ReviewLog> { $0.exportedAt == nil }
        let descriptor = FetchDescriptor<ReviewLog>(predicate: predicate, sortBy: [SortDescriptor(\.reviewedAt)])
        let unexported = try context.fetch(descriptor)
        guard !unexported.isEmpty else { return nil }

        let exportId = UUID().uuidString.lowercased()
        let header = AttemptHeader(
            id: "export-\(exportId)",
            createdAt: ExportDateFormatter.string(from: now),
            producer: "encore 1.0"
        )

        var lines: [String] = [try header.encodedLine()]
        for log in unexported {
            let promptId = (log.prompt?.origin == .aiVariant ? log.prompt?.sourcePrompt?.externalID : log.prompt?.externalID)
                ?? log.prompt?.externalID
                ?? ""
            let conceptId = log.concept?.externalID ?? ""
            let record = AttemptRecord(
                attemptId: log.attemptID.uuidString.lowercased(),
                promptId: promptId,
                conceptId: conceptId,
                answeredAt: ExportDateFormatter.string(from: log.reviewedAt),
                answerText: log.answerText,
                grade: log.grade.numericValue,
                msTaken: max(0, Int((log.duration * 1000).rounded())),
                sessionKind: log.sessionKind,
                calibrated: log.calibrated,
                planId: log.planID
            )
            lines.append(try record.encodedLine())
        }

        let content = lines.joined(separator: "\n") + "\n"
        guard let data = content.data(using: .utf8) else { return nil }

        let destinationURL = handoffFolder.fromEncoreURL.appending(path: "attempts-\(exportId).jsonl")
        try Self.writeAtomically(data: data, to: destinationURL)

        for log in unexported {
            log.exportedAt = now
        }
        try context.save()

        return destinationURL
    }

    /// Runs both state and attempts exports.
    @discardableResult
    public func exportAll(now: Date = .now) throws -> (stateURL: URL, attemptsURL: URL?) {
        let stateURL = try exportState(now: now)
        let attemptsURL = try exportAttempts(now: now)
        return (stateURL, attemptsURL)
    }

    /// Convenience for launch export.
    @discardableResult
    public static func exportOnLaunch(context: ModelContext, folder: HandoffFolder = HandoffFolder(), now: Date = .now) -> (stateURL: URL, attemptsURL: URL?)? {
        do {
            let exporter = StateExporter(context: context, handoffFolder: folder)
            return try exporter.exportAll(now: now)
        } catch {
            return nil
        }
    }
}

/// Coordinates delayed export after sessions finish.
@MainActor
public final class StateExportCoordinator {
    public static let shared = StateExportCoordinator()

    private var exportTask: Task<Void, Never>?

    public init() {}

    public func schedulePostSessionExport(
        context: ModelContext,
        delay: Duration = .seconds(30),
        folder: HandoffFolder = HandoffFolder()
    ) {
        exportTask?.cancel()
        exportTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            _ = StateExporter.exportOnLaunch(context: context, folder: folder)
        }
    }
}
