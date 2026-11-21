import Foundation

/// Articulate's daily or post-class plan schema (encore.plan v1).
public struct DailyPlan: Codable, Hashable, Sendable {
    public var header: PlanHeader
    public var kind: String // "daily" or "postclass"
    public var date: String // "YYYY-MM-DD"
    public var validUntil: Date
    public var reviewScope: [String]
    public var new: [PlanNew]
    public var examFocus: [ExamFocus]
    public var budgetMinutes: BudgetMinutes
    public var kindsMix: KindsMix
    public var readingShare: Double
    public var intervalCaps: [IntervalCap]
    public var importBatch: String?
    public var macPractice: [String]
    /// Phase 3: a practice test to offer today.
    public var practiceTest: PracticeTest?
    /// Phase 3: the day before an exam, a short quiz on exactly these concepts.
    public var reviewQuiz: ReviewQuiz?
    /// Phase 3: serve at most this many due reviews today.
    public var reviewLimit: Int?
    /// Phase 3: due reviews of these exams' concepts come first.
    public var reviewPriority: [String]
    /// Phase 3: introduce no new concepts today.
    public var newPaused: Bool
    /// Phase 3: introduce no new concepts that belong to these exams.
    public var holdNewForExams: [String]

    public init(
        header: PlanHeader,
        kind: String = "daily",
        date: String,
        validUntil: Date,
        reviewScope: [String],
        new: [PlanNew],
        examFocus: [ExamFocus] = [],
        budgetMinutes: BudgetMinutes = BudgetMinutes(),
        kindsMix: KindsMix = KindsMix(),
        readingShare: Double = 0.0,
        intervalCaps: [IntervalCap] = [],
        importBatch: String? = nil,
        macPractice: [String] = [],
        practiceTest: PracticeTest? = nil,
        reviewQuiz: ReviewQuiz? = nil,
        reviewLimit: Int? = nil,
        reviewPriority: [String] = [],
        newPaused: Bool = false,
        holdNewForExams: [String] = []
    ) {
        self.header = header
        self.kind = kind
        self.date = date
        self.validUntil = validUntil
        self.reviewScope = reviewScope
        self.new = new
        self.examFocus = examFocus
        self.budgetMinutes = budgetMinutes
        self.kindsMix = kindsMix
        self.readingShare = readingShare
        self.intervalCaps = intervalCaps
        self.importBatch = importBatch
        self.macPractice = macPractice
        self.practiceTest = practiceTest
        self.reviewQuiz = reviewQuiz
        self.reviewLimit = reviewLimit
        self.reviewPriority = reviewPriority
        self.newPaused = newPaused
        self.holdNewForExams = holdNewForExams
    }

    enum CodingKeys: String, CodingKey {
        case header
        case kind
        case date
        case validUntil
        case reviewScope
        case new
        case examFocus
        case budgetMinutes
        case kindsMix
        case readingShare
        case intervalCaps
        case importBatch
        case macPractice
        case practiceTest
        case reviewQuiz
        case reviewLimit
        case reviewPriority
        case newPaused
        case holdNewForExams
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        header = try c.decode(PlanHeader.self, forKey: .header)
        guard header.schema == "encore.plan" else {
            throw DecodingError.dataCorruptedError(forKey: .header, in: c, debugDescription: "Unknown schema '\(header.schema)', expected 'encore.plan'")
        }
        guard header.version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .header, in: c, debugDescription: "Unsupported version \(header.version), expected 1")
        }
        kind = try c.decode(String.self, forKey: .kind)
        date = try c.decode(String.self, forKey: .date)
        validUntil = try Self.decodeDate(from: c, forKey: .validUntil)
        reviewScope = try c.decode([String].self, forKey: .reviewScope)
        new = try c.decode([PlanNew].self, forKey: .new)
        examFocus = try c.decodeIfPresent([ExamFocus].self, forKey: .examFocus) ?? []
        budgetMinutes = try c.decodeIfPresent(BudgetMinutes.self, forKey: .budgetMinutes) ?? BudgetMinutes()
        kindsMix = try c.decodeIfPresent(KindsMix.self, forKey: .kindsMix) ?? KindsMix()
        readingShare = try c.decodeIfPresent(Double.self, forKey: .readingShare) ?? 0.0
        intervalCaps = try c.decodeIfPresent([IntervalCap].self, forKey: .intervalCaps) ?? []
        importBatch = try c.decodeIfPresent(String.self, forKey: .importBatch)
        macPractice = try c.decodeIfPresent([String].self, forKey: .macPractice) ?? []
        practiceTest = try c.decodeIfPresent(PracticeTest.self, forKey: .practiceTest)
        reviewQuiz = try c.decodeIfPresent(ReviewQuiz.self, forKey: .reviewQuiz)
        reviewLimit = try c.decodeIfPresent(Int.self, forKey: .reviewLimit)
        reviewPriority = try c.decodeIfPresent([String].self, forKey: .reviewPriority) ?? []
        newPaused = try c.decodeIfPresent(Bool.self, forKey: .newPaused) ?? false
        holdNewForExams = try c.decodeIfPresent([String].self, forKey: .holdNewForExams) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(header, forKey: .header)
        try c.encode(kind, forKey: .kind)
        try c.encode(date, forKey: .date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        try c.encode(formatter.string(from: validUntil), forKey: .validUntil)
        try c.encode(reviewScope, forKey: .reviewScope)
        try c.encode(new, forKey: .new)
        try c.encode(examFocus, forKey: .examFocus)
        try c.encode(budgetMinutes, forKey: .budgetMinutes)
        try c.encode(kindsMix, forKey: .kindsMix)
        try c.encode(readingShare, forKey: .readingShare)
        try c.encode(intervalCaps, forKey: .intervalCaps)
        try c.encodeIfPresent(importBatch, forKey: .importBatch)
        try c.encode(macPractice, forKey: .macPractice)
        try c.encodeIfPresent(practiceTest, forKey: .practiceTest)
        try c.encodeIfPresent(reviewQuiz, forKey: .reviewQuiz)
        try c.encodeIfPresent(reviewLimit, forKey: .reviewLimit)
        try c.encode(reviewPriority, forKey: .reviewPriority)
        try c.encode(newPaused, forKey: .newPaused)
        try c.encode(holdNewForExams, forKey: .holdNewForExams)
    }

    /// Whether this plan has expired (now >= validUntil). Missed plans expire and are ignored.
    public func isExpired(at now: Date = .now) -> Bool {
        now >= validUntil
    }

    /// The time when this plan becomes available for study (06:00 local time on `date`).
    public func availableAt(calendar: Calendar = .current) -> Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 6
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)
    }

    /// Whether the plan is currently active and available to study (from 06:00 until validUntil).
    public func isAvailable(at now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isExpired(at: now) else { return false }
        if let start = availableAt(calendar: calendar) {
            return now >= start
        }
        return true
    }

    static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        let str = try container.decode(String.self, forKey: key)
        if let date = parseISO8601(str) {
            return date
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid ISO 8601 date: \(str)")
    }

    public static func parseISO8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}

public struct PlanHeader: Codable, Hashable, Sendable {
    public var schema: String
    public var version: Int
    public var id: String
    public var createdAt: Date
    public var producer: String

    public init(
        schema: String = "encore.plan",
        version: Int = 1,
        id: String,
        createdAt: Date,
        producer: String = "articulate 0.1.0"
    ) {
        self.schema = schema
        self.version = version
        self.id = id
        self.createdAt = createdAt
        self.producer = producer
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case version
        case id
        case createdAt = "created_at"
        case producer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(String.self, forKey: .id)
        producer = try c.decode(String.self, forKey: .producer)
        let str = try c.decode(String.self, forKey: .createdAt)
        if let date = DailyPlan.parseISO8601(str) {
            createdAt = date
        } else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: c, debugDescription: "Invalid ISO 8601 date: \(str)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(version, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(producer, forKey: .producer)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        try c.encode(formatter.string(from: createdAt), forKey: .createdAt)
    }
}

public struct PlanNew: Codable, Hashable, Sendable {
    public var conceptId: String
    public var promptIds: [String]
    public var reason: String

    public init(conceptId: String, promptIds: [String] = [], reason: String = "core") {
        self.conceptId = conceptId
        self.promptIds = promptIds
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case conceptId
        case promptIds
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conceptId = try c.decode(String.self, forKey: .conceptId)
        promptIds = try c.decodeIfPresent([String].self, forKey: .promptIds) ?? []
        reason = try c.decode(String.self, forKey: .reason)
    }
}

public struct ExamFocus: Codable, Hashable, Sendable {
    public var examId: String
    public var rampDay: Int

    public init(examId: String, rampDay: Int) {
        self.examId = examId
        self.rampDay = rampDay
    }
}

public struct BudgetMinutes: Codable, Hashable, Sendable {
    public var target: Int
    public var planned: Int

    public init(target: Int = 20, planned: Int = 20) {
        self.target = target
        self.planned = planned
    }

    enum CodingKeys: String, CodingKey {
        case target
        case planned
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(Int.self, forKey: .target) ?? 20
        planned = try c.decodeIfPresent(Int.self, forKey: .planned) ?? target
    }
}

public struct KindsMix: Codable, Hashable, Sendable {
    public var freeRecallMin: Double

    public init(freeRecallMin: Double = 0.5) {
        self.freeRecallMin = freeRecallMin
    }

    enum CodingKeys: String, CodingKey {
        case freeRecallMin
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        freeRecallMin = try c.decodeIfPresent(Double.self, forKey: .freeRecallMin) ?? 0.5
    }
}

public struct IntervalCap: Codable, Hashable, Sendable {
    public var courseId: String
    public var maxDays: Int

    public init(courseId: String, maxDays: Int) {
        self.courseId = courseId
        self.maxDays = maxDays
    }

    enum CodingKeys: String, CodingKey {
        case courseId
        case maxDays
    }
}

public struct PracticeTest: Codable, Hashable, Sendable {
    public var examId: String
    /// How many items to draw from the exam's scope (15–20).
    public var itemCount: Int
    /// The smallest share of free-recall items.
    public var freeRecallMin: Double

    public init(examId: String, itemCount: Int, freeRecallMin: Double = 0.5) {
        self.examId = examId
        self.itemCount = itemCount
        self.freeRecallMin = freeRecallMin
    }

    enum CodingKeys: String, CodingKey {
        case examId
        case itemCount
        case freeRecallMin
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        examId = try c.decode(String.self, forKey: .examId)
        itemCount = try c.decode(Int.self, forKey: .itemCount)
        freeRecallMin = try c.decodeIfPresent(Double.self, forKey: .freeRecallMin) ?? 0.5
    }
}

public struct ReviewQuiz: Codable, Hashable, Sendable {
    public var examId: String
    public var conceptIds: [String]

    public init(examId: String, conceptIds: [String]) {
        self.examId = examId
        self.conceptIds = conceptIds
    }
}
