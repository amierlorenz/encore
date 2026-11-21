import Foundation
import SwiftData

/// A post-class quiz: the `kind: "postclass"` plan Articulate writes after a
/// lecture, served as its own short session apart from Today's session.
///
/// Only the plan's `new` entries are served, in plan order; due reviews are
/// not. A prompt counts as answered once it has a post-class answer logged
/// after the plan was created, so a quiz left halfway resumes where it stopped.
public enum PostclassQuiz {
    /// The `sessionKind` recorded on post-class answers.
    public static let sessionKind = "postclass"

    /// The prompts of `plan` still to answer, in plan order.
    public static func items(
        for plan: DailyPlan,
        in context: ModelContext,
        supportsCodeExecution: Bool
    ) throws -> [SessionItem] {
        let candidates = try context.fetch(FetchDescriptor<Concept>()).map(ConceptSnapshot.init)
        return items(
            for: plan,
            from: candidates,
            answeredPromptIDs: try answeredPromptIDs(for: plan, in: context),
            supportsCodeExecution: supportsCodeExecution
        )
    }

    /// The pure part of ``items(for:in:supportsCodeExecution:)``.
    public static func items(
        for plan: DailyPlan,
        from candidates: [ConceptSnapshot],
        answeredPromptIDs: Set<String>,
        supportsCodeExecution: Bool
    ) -> [SessionItem] {
        let concepts = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var items: [SessionItem] = []
        for entry in plan.new {
            guard let concept = concepts[entry.conceptId] else { continue }
            let allowed = Set(entry.promptIds)
            for prompt in concept.prompts {
                guard !prompt.isFlagged, !prompt.isRetired,
                      supportsCodeExecution || !prompt.kind.requiresCodeRunner,
                      allowed.isEmpty || allowed.contains(prompt.id),
                      !answeredPromptIDs.contains(prompt.id),
                      seen.insert(prompt.id).inserted
                else { continue }
                items.append(SessionItem(conceptID: concept.id, promptID: prompt.id, unitID: concept.unitID))
            }
        }
        return items
    }

    /// Whether every concept of `plan` has arrived and nothing is left to answer.
    /// A concept that hasn't arrived yet (its batch is still syncing) keeps the quiz open.
    public static func isAnswered(_ plan: DailyPlan, in context: ModelContext) throws -> Bool {
        let concepts = try context.fetch(FetchDescriptor<Concept>())
        let known = Set(concepts.map(\.externalID))
        guard plan.new.allSatisfy({ known.contains($0.conceptId) }) else { return false }
        return items(
            for: plan,
            from: concepts.map(ConceptSnapshot.init),
            answeredPromptIDs: try answeredPromptIDs(for: plan, in: context),
            supportsCodeExecution: true
        ).isEmpty
    }

    /// Prompts answered in a post-class session since `plan` was created.
    static func answeredPromptIDs(for plan: DailyPlan, in context: ModelContext) throws -> Set<String> {
        let kind = sessionKind
        let since = plan.header.createdAt
        let logs = try context.fetch(FetchDescriptor<ReviewLog>(
            predicate: #Predicate { $0.sessionKindRaw == kind && $0.reviewedAt >= since }
        ))
        return Set(logs.compactMap { $0.prompt?.externalID })
    }

    /// The lecture id in a `postclass-<lectureId>.json` file name, such as `mat305.l.2026-12-01`.
    public static func lectureID(fromFileName name: String) -> String? {
        guard name.hasPrefix("postclass-"), name.hasSuffix(".json") else { return nil }
        let id = String(name.dropFirst("postclass-".count).dropLast(".json".count))
        return id.isEmpty ? nil : id
    }

    /// The course id in a lecture id (`<course>.l.<YYYY-MM-DD>`).
    public static func courseID(fromLectureID lectureID: String) -> String {
        if let range = lectureID.range(of: ".l.", options: .backwards) {
            return String(lectureID[..<range.lowerBound])
        }
        return lectureID
    }
}

extension ReviewLog {
    /// Whether this answer left the concept's schedule where it was: a post-class
    /// answer, or a passing practice answer on a concept that wasn't due.
    var isPostclassOrUnscheduledPractice: Bool {
        sessionKind == PostclassQuiz.sessionKind || (mode == .practice && !wasDue && grade.isPass)
    }
}

extension Concept {
    /// Whether the concept was introduced in a post-class quiz and hasn't had
    /// its first scheduled review yet. That review's grade leaves ease alone
    /// and is exported with `calibrated: false`.
    public var awaitsFirstReviewAfterPostclass: Bool {
        let logs = reviews ?? []
        return logs.contains { $0.wasNew && $0.sessionKind == PostclassQuiz.sessionKind }
            && logs.allSatisfy(\.isPostclassOrUnscheduledPractice)
    }
}
