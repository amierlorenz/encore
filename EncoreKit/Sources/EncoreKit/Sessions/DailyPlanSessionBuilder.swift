import Foundation

/// Builds a study session queue and chunks from Articulate's daily plan.
///
/// Rules:
/// - Due reviews in `reviewScope` first (Encore's own schedule).
/// - New concepts in the given order from the plan (`promptIds` empty = all active prompts of the concept).
/// - Due items interleaved across courses.
/// - Keeping `kindsMix.freeRecallMin` (≥½ free recall).
/// - Size from `budgetMinutes` using past answer times, served in ~5-minute chunks without cutting off at the budget.
public struct DailyPlanSessionBuilder: Sendable {
    public var plan: DailyPlan
    public var supportsCodeExecution: Bool

    public init(plan: DailyPlan, supportsCodeExecution: Bool) {
        self.plan = plan
        self.supportsCodeExecution = supportsCodeExecution
    }

    /// Builds the complete ordered session items for the plan at the given time.
    /// Returns an empty array if the plan is expired (`now >= plan.validUntil`).
    public func build(
        from candidates: [ConceptSnapshot],
        now: Date = .now,
        using rng: inout some RandomNumberGenerator
    ) -> [SessionItem] {
        guard !plan.isExpired(at: now) else { return [] }

        // 1. Due reviews in reviewScope (Encore's schedule)
        let dueItems = buildDueReviews(from: candidates, now: now, using: &rng)

        // 2. New concepts in the given order from the plan
        let newItems = buildNewConcepts(from: candidates)

        // Combine: due items first, new concepts in plan order second
        return dueItems + newItems
    }

    /// Filters and orders due reviews across courses in reviewScope.
    private func buildDueReviews(
        from candidates: [ConceptSnapshot],
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) -> [SessionItem] {
        let inScope: [ConceptSnapshot]
        if plan.reviewScope.contains("all courses") || plan.reviewScope.isEmpty {
            inScope = candidates
        } else {
            let scopes = Set(plan.reviewScope)
            inScope = candidates.filter { scopes.contains($0.courseID) }
        }

        let dueConcepts = inScope.filter { concept in
            !concept.isNew && (concept.dueDate.map { $0 <= now } ?? false)
        }

        // Pick one eligible prompt for each due concept, tracking free recall ratio
        let freeRecallMin = plan.kindsMix.freeRecallMin
        var chosen: [(concept: ConceptSnapshot, prompt: PromptSnapshot)] = []
        var freeRecallCount = 0

        for concept in dueConcepts {
            let eligible = eligiblePrompts(for: concept)
            guard !eligible.isEmpty else { continue }

            let prompt: PromptSnapshot
            let needsFreeRecall = chosen.isEmpty || (Double(freeRecallCount) / Double(chosen.count) < freeRecallMin)

            if needsFreeRecall, let freeRecallPrompt = eligible.filter({ $0.kind.isFreeRecall }).min(by: { ($0.lastShownAt ?? .distantPast) < ($1.lastShownAt ?? .distantPast) }) {
                prompt = freeRecallPrompt
            } else {
                prompt = eligible.shuffled(using: &rng).min { ($0.lastShownAt ?? .distantPast) < ($1.lastShownAt ?? .distantPast) }!
            }

            if prompt.kind.isFreeRecall { freeRecallCount += 1 }
            chosen.append((concept, prompt))
        }

        // Interleave due items across courses
        let orderedConcepts = interleaveAcrossCourses(chosen.map(\.concept), using: &rng)
        let promptLookup = Dictionary(uniqueKeysWithValues: chosen.map { ($0.concept.id, $0.prompt) })

        return orderedConcepts.compactMap { concept in
            promptLookup[concept.id].map { SessionItem(conceptID: concept.id, promptID: $0.id, unitID: concept.unitID) }
        }
    }

    /// Builds new concept items in the exact order specified in plan.new.
    private func buildNewConcepts(from candidates: [ConceptSnapshot]) -> [SessionItem] {
        let conceptMap = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var items: [SessionItem] = []

        for entry in plan.new {
            guard let concept = conceptMap[entry.conceptId] else { continue }
            let eligible = eligiblePrompts(for: concept)
            guard !eligible.isEmpty else { continue }

            if entry.promptIds.isEmpty {
                // All active prompts of the concept
                for prompt in eligible {
                    items.append(SessionItem(conceptID: concept.id, promptID: prompt.id, unitID: concept.unitID))
                }
            } else {
                // Specific prompts matching entry.promptIds
                let allowed = Set(entry.promptIds)
                let matching = eligible.filter { allowed.contains($0.id) }
                for prompt in matching {
                    items.append(SessionItem(conceptID: concept.id, promptID: prompt.id, unitID: concept.unitID))
                }
            }
        }

        return items
    }

    /// Eligible prompts of a concept (non-flagged and platform-supported).
    private func eligiblePrompts(for concept: ConceptSnapshot) -> [PromptSnapshot] {
        concept.prompts.filter { prompt in
            !prompt.isFlagged && (supportsCodeExecution || !prompt.kind.requiresCodeRunner)
        }
    }

    /// Interleaves concepts across courses so consecutive items don't share a course unless forced.
    private func interleaveAcrossCourses(_ concepts: [ConceptSnapshot], using rng: inout some RandomNumberGenerator) -> [ConceptSnapshot] {
        var groups = Dictionary(grouping: concepts, by: \.courseID).mapValues { $0.shuffled(using: &rng) }
        var result: [ConceptSnapshot] = []
        var previousCourse: String?

        while !groups.isEmpty {
            let candidates = groups.filter { $0.key != previousCourse }
            let pool = candidates.isEmpty ? groups : candidates
            let largest = pool.values.map(\.count).max() ?? 0
            let course = pool.filter { $0.value.count == largest }.keys.sorted().randomElement(using: &rng)!
            result.append(groups[course]!.removeLast())
            if groups[course]!.isEmpty { groups[course] = nil }
            previousCourse = course
        }

        return result
    }

    /// Splits a queue into ~5-minute chunks using past answer times.
    ///
    /// Target chunk size is derived from past average answer duration (e.g. 300 seconds / averageSeconds).
    /// Nothing is cut off: every item belongs to a chunk.
    public static func chunkQueue(
        _ queue: [SessionItem],
        averageItemDuration: TimeInterval = 25.0,
        targetChunkMinutes: Int = 5
    ) -> [[SessionItem]] {
        guard !queue.isEmpty else { return [] }
        let targetSeconds = Double(targetChunkMinutes * 60)
        let safeDuration = max(5.0, averageItemDuration)
        let chunkSize = max(1, Int((targetSeconds / safeDuration).rounded()))

        var chunks: [[SessionItem]] = []
        var startIndex = 0
        while startIndex < queue.count {
            let endIndex = min(startIndex + chunkSize, queue.count)
            chunks.append(Array(queue[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return chunks
    }
}
