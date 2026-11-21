import Foundation

/// The sessions a daily plan offers.
public enum DailyPlanPart: String, Hashable, Sendable {
    /// Due reviews, then new concepts.
    case session
    /// The plan's `practiceTest`.
    case practiceTest
    /// The plan's `reviewQuiz`.
    case reviewQuiz
}

/// Builds a study session queue and chunks from Articulate's daily plan.
///
/// Rules:
/// - Due reviews in `reviewScope` first (Encore's own schedule).
/// - New concepts in the given order from the plan (`promptIds` empty = all active prompts of the concept).
/// - Due items interleaved across courses.
/// - Keeping `kindsMix.freeRecallMin` (≥½ free recall).
/// - Size from `budgetMinutes` using past answer times, served in ~5-minute chunks without cutting off at the budget.
/// - Phase 3 fields: `reviewLimit` caps due reviews (priority exams, then core, then most overdue),
///   `reviewPriority` serves those exams' due reviews first, `newPaused` and `holdNewForExams` hold back new
///   concepts. `practiceTest` and `reviewQuiz` are separate sessions, built by ``buildPracticeTest(from:using:)``
///   and ``buildReviewQuiz(from:)``.
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

        var dueConcepts = inScope.filter { concept in
            !concept.isNew && (concept.dueDate.map { $0 <= now } ?? false)
        }
        if let limit = plan.reviewLimit {
            dueConcepts = Array(dueConcepts.sorted(by: reviewRank).prefix(max(0, limit)))
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

        // Interleave due items across courses, priority exams' concepts first
        let chosenConcepts = chosen.map(\.concept)
        let orderedConcepts: [ConceptSnapshot]
        if plan.reviewPriority.isEmpty {
            orderedConcepts = interleaveAcrossCourses(chosenConcepts, using: &rng)
        } else {
            let first = chosenConcepts.filter(isPriority)
            let rest = chosenConcepts.filter { !isPriority($0) }
            orderedConcepts = interleaveAcrossCourses(first, using: &rng) + interleaveAcrossCourses(rest, using: &rng)
        }
        let promptLookup = Dictionary(uniqueKeysWithValues: chosen.map { ($0.concept.id, $0.prompt) })

        return orderedConcepts.compactMap { concept in
            promptLookup[concept.id].map { SessionItem(conceptID: concept.id, promptID: $0.id, unitID: concept.unitID) }
        }
    }

    /// Builds new concept items in the exact order specified in plan.new.
    private func buildNewConcepts(from candidates: [ConceptSnapshot]) -> [SessionItem] {
        guard !plan.newPaused else { return [] }
        let conceptMap = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let heldExams = Set(plan.holdNewForExams)
        var items: [SessionItem] = []

        for entry in plan.new {
            guard let concept = conceptMap[entry.conceptId] else { continue }
            guard concept.examIDs.isDisjoint(with: heldExams) else { continue }
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

    /// Whether a concept belongs to an exam in `reviewPriority`.
    private func isPriority(_ concept: ConceptSnapshot) -> Bool {
        !concept.examIDs.isDisjoint(with: plan.reviewPriority)
    }

    /// Order for picking due reviews under `reviewLimit`: priority exams first, then core, then most overdue.
    private func reviewRank(_ a: ConceptSnapshot, _ b: ConceptSnapshot) -> Bool {
        let aPriority = isPriority(a), bPriority = isPriority(b)
        if aPriority != bPriority { return aPriority }
        let aCore = a.tier == "core", bCore = b.tier == "core"
        if aCore != bCore { return aCore }
        return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
    }

    // MARK: - Practice test and review quiz

    /// The practice test the plan offers today: `itemCount` concepts drawn from the exam's scope (concepts
    /// already introduced), one prompt each, at least `freeRecallMin` of them free recall, mixed across units.
    /// Empty when the plan has no practice test or is expired.
    public func buildPracticeTest(
        from candidates: [ConceptSnapshot],
        now: Date = .now,
        using rng: inout some RandomNumberGenerator
    ) -> [SessionItem] {
        guard let test = plan.practiceTest, !plan.isExpired(at: now), test.itemCount > 0 else { return [] }

        let pool = candidates
            .filter { $0.examIDs.contains(test.examId) && !$0.isNew && !$0.isRetired && !quizPrompts(for: $0).isEmpty }
            .shuffled(using: &rng)
        // Concepts that can be asked as free recall go first while the test still needs them.
        let freeRecallTarget = Int((Double(test.itemCount) * test.freeRecallMin).rounded(.up))
        let withFreeRecall = pool.filter { quizPrompts(for: $0).contains { $0.kind.isFreeRecall } }
        let freeRecallPicks = Array(withFreeRecall.prefix(min(freeRecallTarget, test.itemCount)))
        let pickedIDs = Set(freeRecallPicks.map(\.id))
        let otherPicks = pool.filter { !pickedIDs.contains($0.id) }.prefix(test.itemCount - freeRecallPicks.count)

        var items: [SessionItem] = []
        for concept in freeRecallPicks {
            let prompt = leastRecentlyShown(quizPrompts(for: concept).filter { $0.kind.isFreeRecall }, using: &rng)
            items.append(SessionItem(conceptID: concept.id, promptID: prompt.id, unitID: concept.unitID))
        }
        for concept in otherPicks {
            let prompt = leastRecentlyShown(quizPrompts(for: concept), using: &rng)
            items.append(SessionItem(conceptID: concept.id, promptID: prompt.id, unitID: concept.unitID))
        }
        return interleave(items, by: \.unitID, using: &rng)
    }

    /// The review quiz the plan offers the day before an exam: one prompt for each listed concept, in plan
    /// order, preferring free recall. Empty when the plan has no review quiz or is expired.
    public func buildReviewQuiz(from candidates: [ConceptSnapshot], now: Date = .now) -> [SessionItem] {
        guard let quiz = plan.reviewQuiz, !plan.isExpired(at: now) else { return [] }
        let conceptMap = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        return quiz.conceptIds.compactMap { id in
            guard seen.insert(id).inserted, let concept = conceptMap[id], !concept.isRetired else { return nil }
            let prompts = quizPrompts(for: concept)
            let preferred = prompts.filter(\.kind.isFreeRecall)
            let pick = (preferred.isEmpty ? prompts : preferred)
                .min { ($0.lastShownAt ?? .distantPast, $0.id) < ($1.lastShownAt ?? .distantPast, $1.id) }
            return pick.map { SessionItem(conceptID: concept.id, promptID: $0.id, unitID: concept.unitID) }
        }
    }

    /// Prompts a test may ask: eligible and not retired.
    private func quizPrompts(for concept: ConceptSnapshot) -> [PromptSnapshot] {
        eligiblePrompts(for: concept).filter { !$0.isRetired }
    }

    private func leastRecentlyShown(_ prompts: [PromptSnapshot], using rng: inout some RandomNumberGenerator) -> PromptSnapshot {
        prompts.shuffled(using: &rng).min { ($0.lastShownAt ?? .distantPast) < ($1.lastShownAt ?? .distantPast) }!
    }

    /// Spreads items so consecutive ones don't share a key unless forced.
    private func interleave(
        _ items: [SessionItem],
        by key: (SessionItem) -> String,
        using rng: inout some RandomNumberGenerator
    ) -> [SessionItem] {
        var groups = Dictionary(grouping: items, by: key)
        var result: [SessionItem] = []
        var previous: String?
        while !groups.isEmpty {
            let others = groups.filter { $0.key != previous }
            let pool = others.isEmpty ? groups : others
            let largest = pool.values.map(\.count).max() ?? 0
            let next = pool.filter { $0.value.count == largest }.keys.sorted().randomElement(using: &rng)!
            result.append(groups[next]!.removeFirst())
            if groups[next]!.isEmpty { groups[next] = nil }
            previous = next
        }
        return result
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
