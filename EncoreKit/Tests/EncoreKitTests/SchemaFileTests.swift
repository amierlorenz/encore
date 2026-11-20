import Foundation
import EncoreKit
import Testing

struct SchemaFileTests {
    @Test func schemaFileIsValidAndMatchesV2() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../Schema/encore.import.v2.json")
            .standardizedFileURL
        let data = try Data(contentsOf: url)
        let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(schema["title"] as? String == "ImportBatch")

        let defs = try #require(schema["$defs"] as? [String: Any])
        #expect(defs["Header"] != nil)
        #expect(defs["Course"] != nil)
        #expect(defs["Unit"] != nil)
        #expect(defs["Concept"] != nil)
        #expect(defs["Prompt"] != nil)
        #expect(defs["Exam"] != nil)
        #expect(defs["ContrastGroup"] != nil)
        #expect(defs["SourceFile"] != nil)
        #expect(defs["Citation"] != nil)
        #expect(defs["Claim"] != nil)
        #expect(defs["ConceptDetails"] != nil)
    }

    @Test func planSchemaIsValid() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../Schema/encore.plan.v1.json")
            .standardizedFileURL
        let data = try Data(contentsOf: url)
        let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let required = try #require(schema["required"] as? [String])
        #expect(required.contains("header"))
        #expect(required.contains("kind"))
        #expect(required.contains("date"))
        #expect(required.contains("validUntil"))
        #expect(required.contains("reviewScope"))
        #expect(required.contains("new"))
        #expect(required.contains("budgetMinutes"))
        #expect(required.contains("kindsMix"))
    }
}
