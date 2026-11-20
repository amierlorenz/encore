import Foundation
import SwiftData

/// Upserts an ``ImportDocument`` into the store by stable id.
///
/// Imports never delete content and never touch a concept's schedule or review
/// history. The one exception: AI variants of a prompt whose content changed are
/// removed, because they copied the old answer.
public struct Importer {
    public enum Failure: Error, Equatable {
        case invalidDocument([ImportIssue])
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Reports what ``apply(_:)`` would do without changing anything.
    public func plan(_ document: ImportDocument) throws -> ImportPlan {
        try run(document, dryRun: true)
    }

    /// Applies the document and saves. Throws ``Failure/invalidDocument(_:)`` if validation finds errors.
    @discardableResult
    public func apply(_ document: ImportDocument) throws -> ImportPlan {
        let plan = try run(document, dryRun: true)
        guard plan.canApply else { throw Failure.invalidDocument(plan.issues) }
        let applied = try run(document, dryRun: false)
        try context.save()
        return applied
    }

    /// Ingests a file at the given URL according to hand-off folder rules:
    /// - If decode or validation fails, moves the file to `failed/` with `<batchId>.error.txt` and throws.
    /// - If successful, records `AppliedBatch`, deletes the source file (if `deleteOnSuccess` is true), and returns the plan.
    @discardableResult
    public func importFile(
        at fileURL: URL,
        handoff: HandoffFolder = HandoffFolder(),
        deleteOnSuccess: Bool = true
    ) throws -> ImportPlan {
        try handoff.createDirectoriesIfNeeded()

        func fail(error: any Error, documentHeader: ImportHeader? = nil) throws -> Never {
            let filename = fileURL.lastPathComponent
            let stem = fileURL.deletingPathExtension().lastPathComponent
            let batchId: String = {
                if stem.hasPrefix("import-") {
                    return String(stem.dropFirst("import-".count))
                }
                if let hId = documentHeader?.id {
                    if hId.hasPrefix("import-") {
                        return String(hId.dropFirst("import-".count))
                    }
                    return hId
                }
                return stem
            }()

            let destFileURL = handoff.failedURL.appending(path: filename)
            let fm = FileManager.default
            if fm.fileExists(atPath: destFileURL.path) {
                try? fm.removeItem(at: destFileURL)
            }
            try? fm.moveItem(at: fileURL, to: destFileURL)

            let errorMessage = (error as? ImportDecodingError)?.message ?? error.localizedDescription
            let errorFileURL = handoff.failedURL.appending(path: "\(batchId).error.txt")
            try? errorMessage.write(to: errorFileURL, atomically: true, encoding: .utf8)
            if batchId != stem {
                let stemErrorFileURL = handoff.failedURL.appending(path: "\(stem).error.txt")
                try? errorMessage.write(to: stemErrorFileURL, atomically: true, encoding: .utf8)
            }
            throw error
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            try fail(error: error)
        }

        let document: ImportDocument
        do {
            document = try ImportDocument.decode(from: data)
        } catch {
            struct HeaderOnly: Decodable { var header: ImportHeader }
            let header = try? JSONDecoder().decode(HeaderOnly.self, from: data).header
            try fail(error: error, documentHeader: header)
        }

        let plan: ImportPlan
        do {
            plan = try apply(document)
        } catch {
            try fail(error: error, documentHeader: document.header)
        }

        if deleteOnSuccess {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return plan
    }

    private func run(_ document: ImportDocument, dryRun: Bool) throws -> ImportPlan {
        var store = try Store(context: context)
        var plan = ImportPlan()
        plan.issues = ImportValidator(
            knownCourseIDs: Set(store.courses.keys),
            knownUnitIDs: Set(store.units.keys)
        ).validate(document)
        guard dryRun || plan.canApply else { return plan }

        for course in document.courses {
            let model = upsertCourse(course, store: &store, counts: &plan.courses, dryRun: dryRun)
            for unit in course.units {
                let unitModel = upsertUnit(unit, courseID: course.id, parent: model, store: &store, counts: &plan.units, dryRun: dryRun)
                for concept in unit.concepts {
                    let conceptModel = try upsertConcept(concept, unitID: unit.id, parent: unitModel, store: &store, counts: &plan.concepts, dryRun: dryRun)
                    for prompt in concept.prompts {
                        upsertPrompt(prompt, conceptID: concept.id, parent: conceptModel, store: &store, counts: &plan.prompts, dryRun: dryRun)
                    }
                }
            }
        }
        for exam in document.exams {
            try upsertExam(exam, store: &store, counts: &plan.exams, dryRun: dryRun)
        }

        if !dryRun {
            let batchID = document.header.id
            if !store.appliedBatches.contains(batchID) {
                let batch = AppliedBatch(batchID: batchID)
                context.insert(batch)
                store.appliedBatches.insert(batchID)
            }
        }

        return plan
    }

    private func upsertCourse(_ item: ImportDocument.Course, store: inout Store, counts: inout ImportPlan.Counts, dryRun: Bool) -> Course? {
        guard let existing = store.courses[item.id] else {
            counts.new += 1
            guard !dryRun else { return nil }
            let course = Course(externalID: item.id, name: item.name)
            course.allowsCodingPrompts = item.impliesCoding
            course.shortName = item.shortName
            course.contrastGroups = item.contrastGroups
            course.sourceFiles = item.sourceFiles
            context.insert(course)
            store.courses[item.id] = course
            return course
        }
        let allowsCoding = existing.allowsCodingPrompts || item.impliesCoding
        let shortName = item.shortName ?? existing.shortName
        let contrastGroupsChanged = existing.contrastGroups != item.contrastGroups
        let sourceFilesChanged = existing.sourceFiles != item.sourceFiles
        let changed = existing.name != item.name
            || existing.allowsCodingPrompts != allowsCoding
            || existing.shortName != shortName
            || contrastGroupsChanged
            || sourceFilesChanged
        counts.record(changed)
        if changed && !dryRun {
            existing.name = item.name
            existing.allowsCodingPrompts = allowsCoding
            existing.shortName = shortName
            if !item.contrastGroups.isEmpty || contrastGroupsChanged {
                existing.contrastGroups = item.contrastGroups
            }
            if !item.sourceFiles.isEmpty || sourceFilesChanged {
                existing.sourceFiles = item.sourceFiles
            }
        }
        return existing
    }

    private func upsertUnit(
        _ item: ImportDocument.Unit,
        courseID: String,
        parent: Course?,
        store: inout Store,
        counts: inout ImportPlan.Counts,
        dryRun: Bool
    ) -> CourseUnit? {
        let sortIndex = item.order
        guard let existing = store.units[item.id] else {
            counts.new += 1
            guard !dryRun else { return nil }
            let unit = CourseUnit(externalID: item.id, name: item.name, sortIndex: sortIndex)
            context.insert(unit)
            unit.course = parent
            store.units[item.id] = unit
            return unit
        }
        let changed = existing.name != item.name || existing.sortIndex != sortIndex || existing.course?.externalID != courseID
        counts.record(changed)
        if changed && !dryRun {
            existing.name = item.name
            existing.sortIndex = sortIndex
            existing.course = parent
        }
        return existing
    }

    private func upsertConcept(
        _ item: ImportDocument.Concept,
        unitID: String,
        parent: CourseUnit?,
        store: inout Store,
        counts: inout ImportPlan.Counts,
        dryRun: Bool
    ) throws -> Concept? {
        guard let existing = store.concepts[item.id] else {
            counts.new += 1
            guard !dryRun else { return nil }
            let concept = Concept(
                externalID: item.id,
                title: item.title,
                explanation: item.explanation,
                kind: item.kind,
                tier: item.tier,
                status: item.status,
                details: item.details,
                groupIds: item.groupIds
            )
            context.insert(concept)
            concept.unit = parent
            concept.tags = try ConceptTag.resolve(names: item.tags, in: context)
            store.concepts[item.id] = concept
            return concept
        }
        let tagsChanged = Set((existing.tags ?? []).map(\.name)) != Set(item.tags)
        let changed = existing.title != item.title
            || existing.explanation != item.explanation
            || existing.kind != item.kind
            || existing.tier != item.tier
            || existing.status != item.status
            || existing.details != item.details
            || existing.groupIds != item.groupIds
            || tagsChanged
            || existing.unit?.externalID != unitID
        counts.record(changed)
        if changed && !dryRun {
            existing.title = item.title
            existing.explanation = item.explanation
            existing.kind = item.kind
            existing.tier = item.tier
            existing.status = item.status
            existing.details = item.details
            existing.groupIds = item.groupIds
            if tagsChanged {
                existing.tags = try ConceptTag.resolve(names: item.tags, in: context)
            }
            existing.unit = parent
        }
        return existing
    }

    private func upsertPrompt(
        _ item: ImportDocument.Prompt,
        conceptID: String,
        parent: Concept?,
        store: inout Store,
        counts: inout ImportPlan.Counts,
        dryRun: Bool
    ) {
        guard let existing = store.prompts[item.id] else {
            counts.new += 1
            guard !dryRun else { return }
            let prompt = Prompt(externalID: item.id, content: item.content, origin: .imported, status: item.status)
            context.insert(prompt)
            prompt.concept = parent
            store.prompts[item.id] = prompt
            return
        }
        let contentChanged = existing.content != item.content
        let statusChanged = existing.status != item.status
        let changed = contentChanged || statusChanged || existing.concept?.externalID != conceptID
        counts.record(changed)
        guard changed && !dryRun else { return }
        if contentChanged {
            existing.content = item.content
            for variant in existing.variants ?? [] where variant.origin == .aiVariant {
                context.delete(variant)
            }
        }
        if statusChanged {
            existing.status = item.status
        }
        existing.concept = parent
    }

    private func upsertExam(_ item: ImportDocument.Exam, store: inout Store, counts: inout ImportPlan.Counts, dryRun: Bool) throws {
        guard let date = item.parsedDate() else { return }
        let existing = store.exams[item.id]
        if let existing {
            let changed = existing.name != item.name
                || existing.date != date
                || existing.kind != item.kind
                || existing.course?.externalID != item.courseId
                || Set((existing.units ?? []).map(\.externalID)) != Set(item.unitIds)
            counts.record(changed)
            guard changed else { return }
        } else {
            counts.new += 1
        }
        guard !dryRun else { return }

        let exam = existing ?? Exam(externalID: item.id, name: item.name, date: date, kind: item.kind)
        if existing == nil {
            context.insert(exam)
            store.exams[item.id] = exam
        }
        exam.name = item.name
        exam.date = date
        exam.kind = item.kind
        exam.course = store.courses[item.courseId]
        exam.units = item.unitIds.compactMap { store.units[$0] }
    }
}

private extension ImportPlan.Counts {
    mutating func record(_ changed: Bool) {
        if changed { updated += 1 } else { unchanged += 1 }
    }
}

/// Existing records indexed by external id.
private struct Store {
    var courses: [String: Course]
    var units: [String: CourseUnit]
    var concepts: [String: Concept]
    var prompts: [String: Prompt]
    var exams: [String: Exam]
    var appliedBatches: Set<String>

    init(context: ModelContext) throws {
        courses = try Self.index(context, \Course.externalID)
        units = try Self.index(context, \CourseUnit.externalID)
        concepts = try Self.index(context, \Concept.externalID)
        prompts = try Self.index(context, \Prompt.externalID)
        exams = try Self.index(context, \Exam.externalID)
        appliedBatches = Set(try context.fetch(FetchDescriptor<AppliedBatch>()).map(\.batchID))
    }

    private static func index<Model: PersistentModel>(_ context: ModelContext, _ key: KeyPath<Model, String>) throws -> [String: Model] {
        Dictionary(try context.fetch(FetchDescriptor<Model>()).map { ($0[keyPath: key], $0) }, uniquingKeysWith: { first, _ in first })
    }
}
