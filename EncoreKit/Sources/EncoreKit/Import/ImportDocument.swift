import Foundation

/// The import file format (schema v2).
///
/// Shared header: `{schema, version, id, created_at, producer}`.
/// Decode `encore.import` v2 only. Adding a field does not bump the version;
/// unknown fields are ignored. An unknown version or schema is refused.
public struct ImportHeader: Codable, Hashable, Sendable {
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
        schema: String = "encore.import",
        version: Int = 2,
        id: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date.now),
        producer: String = "articulate"
    ) {
        self.schema = schema
        self.version = version
        self.id = id
        self.createdAt = createdAt
        self.producer = producer
    }
}

public struct ImportDocument: Codable, Hashable, Sendable {
    public var header: ImportHeader
    public var courses: [Course]
    public var exams: [Exam]

    public init(header: ImportHeader = ImportHeader(id: UUID().uuidString), courses: [Course], exams: [Exam] = []) {
        self.header = header
        self.courses = courses
        self.exams = exams
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        header = try c.decode(ImportHeader.self, forKey: .header)
        courses = try c.decodeIfPresent([Course].self, forKey: .courses) ?? []
        exams = try c.decodeIfPresent([Exam].self, forKey: .exams) ?? []
    }

    /// Decodes a document, refusing any version other than v2 and any schema other than encore.import.
    public static func decode(from data: Data) throws(ImportDecodingError) -> ImportDocument {
        do {
            struct HeaderCheck: Decodable {
                var header: ImportHeader
            }
            if let check = try? JSONDecoder().decode(HeaderCheck.self, from: data) {
                if check.header.schema != "encore.import" {
                    throw ImportDecodingError(message: "Unsupported schema \"\(check.header.schema)\"; expected encore.import.")
                }
                if check.header.version != 2 {
                    throw ImportDecodingError(message: "Unsupported schema version \(check.header.version); expected 2.")
                }
            }
            let doc = try JSONDecoder().decode(ImportDocument.self, from: data)
            if doc.header.schema != "encore.import" {
                throw ImportDecodingError(message: "Unsupported schema \"\(doc.header.schema)\"; expected encore.import.")
            }
            if doc.header.version != 2 {
                throw ImportDecodingError(message: "Unsupported schema version \(doc.header.version); expected 2.")
            }
            return doc
        } catch let error as ImportDecodingError {
            throw error
        } catch let error as DecodingError {
            throw ImportDecodingError(error)
        } catch {
            throw ImportDecodingError(message: error.localizedDescription)
        }
    }

    /// Encodes with stable, human-readable formatting.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension ImportDocument {
    public struct Course: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var shortName: String?
        public var coding: Bool?
        public var units: [Unit]
        public var contrastGroups: [ContrastGroup]
        public var sourceFiles: [SourceFile]

        public init(
            id: String,
            name: String,
            shortName: String? = nil,
            coding: Bool? = nil,
            units: [Unit] = [],
            contrastGroups: [ContrastGroup] = [],
            sourceFiles: [SourceFile] = []
        ) {
            self.id = id
            self.name = name
            self.shortName = shortName
            self.coding = coding
            self.units = units
            self.contrastGroups = contrastGroups
            self.sourceFiles = sourceFiles
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
            coding = try c.decodeIfPresent(Bool.self, forKey: .coding)
            units = try c.decodeIfPresent([Unit].self, forKey: .units) ?? []
            contrastGroups = try c.decodeIfPresent([ContrastGroup].self, forKey: .contrastGroups) ?? []
            sourceFiles = try c.decodeIfPresent([SourceFile].self, forKey: .sourceFiles) ?? []
        }

        public var impliesCoding: Bool {
            coding ?? units.contains { $0.concepts.contains { $0.prompts.contains { $0.content.kind.isCoding } } }
        }
    }

    public struct Unit: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var order: Int
        public var concepts: [Concept]

        public init(id: String, name: String, order: Int = 1, concepts: [Concept] = []) {
            self.id = id
            self.name = name
            self.order = order
            self.concepts = concepts
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            order = try c.decode(Int.self, forKey: .order)
            concepts = try c.decodeIfPresent([Concept].self, forKey: .concepts) ?? []
        }
    }

    public struct Concept: Codable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var explanation: String
        public var kind: String
        public var status: String
        public var tier: String
        public var details: ConceptDetails
        public var groupIds: [String]
        public var tags: [String]
        public var prompts: [Prompt]

        public init(
            id: String,
            title: String,
            explanation: String = "",
            kind: String = "definition",
            status: String = "active",
            tier: String = "standard",
            details: ConceptDetails = ConceptDetails(),
            groupIds: [String] = [],
            tags: [String] = [],
            prompts: [Prompt] = []
        ) {
            self.id = id
            self.title = title
            self.explanation = explanation
            self.kind = kind
            self.status = status
            self.tier = tier
            self.details = details
            self.groupIds = groupIds
            self.tags = tags
            self.prompts = prompts
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "definition"
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
            tier = try c.decodeIfPresent(String.self, forKey: .tier) ?? "standard"
            details = try c.decodeIfPresent(ConceptDetails.self, forKey: .details) ?? ConceptDetails()
            groupIds = try c.decodeIfPresent([String].self, forKey: .groupIds) ?? []
            tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
            prompts = try c.decodeIfPresent([Prompt].self, forKey: .prompts) ?? []
        }
    }

    public struct Prompt: Codable, Hashable, Sendable {
        public var id: String
        public var kind: String
        public var status: String
        public var content: PromptContent

        private enum CodingKeys: String, CodingKey {
            case id
            case kind
            case status
            case content
        }

        public init(id: String, kind: String? = nil, status: String = "active", content: PromptContent) {
            self.id = id
            self.kind = kind ?? content.kind.rawValue
            self.status = status
            self.content = content
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            kind = try c.decode(String.self, forKey: .kind)
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
            content = try PromptContent.decode(kind: kind, from: c.superDecoder(forKey: .content))
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(kind, forKey: .kind)
            try c.encode(status, forKey: .status)
            try content.encodePayload(to: c.superEncoder(forKey: .content))
        }
    }

    public struct Exam: Codable, Hashable, Sendable {
        public var id: String
        public var courseId: String
        public var name: String
        public var date: String
        public var kind: String
        public var unitIds: [String]

        public init(
            id: String,
            courseId: String,
            name: String,
            date: String,
            kind: String = "test",
            unitIds: [String] = []
        ) {
            self.id = id
            self.courseId = courseId
            self.name = name
            self.date = date
            self.kind = kind
            self.unitIds = unitIds
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            courseId = try c.decode(String.self, forKey: .courseId)
            name = try c.decode(String.self, forKey: .name)
            date = try c.decode(String.self, forKey: .date)
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "test"
            unitIds = try c.decodeIfPresent([String].self, forKey: .unitIds) ?? []
        }

        public func parsedDate(in timeZone: TimeZone = .current) -> Date? {
            if let date = try? Date(date, strategy: .iso8601) {
                return date
            }
            let dayOnly = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
            return try? Date(date, strategy: dayOnly)
        }
    }
}

public struct ImportDecodingError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public init(_ error: DecodingError) {
        switch error {
        case .keyNotFound(let key, let context):
            let path = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            message = "\(path) is missing."
        case .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            message = "\(path) is null or missing."
        case .typeMismatch(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            message = "\(path) has the wrong type: \(context.debugDescription)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            message = path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            message = error.localizedDescription
        }
    }

    public var description: String { message }
}
