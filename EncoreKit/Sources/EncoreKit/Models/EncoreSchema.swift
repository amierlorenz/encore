import SwiftData

/// The first versioned schema. New versions are added alongside it with a
/// migration stage in ``EncoreMigrationPlan``.
public enum EncoreSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Course.self,
            CourseUnit.self,
            Concept.self,
            Prompt.self,
            ReviewLog.self,
            ConceptTag.self,
            Exam.self,
            SessionPreset.self,
            StudySession.self,
        ]
    }
}

public enum EncoreMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [EncoreSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
