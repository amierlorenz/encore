import Foundation
import EncoreKit
import Testing

struct SchemaFileTests {
    @Test func schemaListsEveryPromptKind() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../Schema/import-v1.schema.json")
            .standardizedFileURL
        let schema = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let defs = try #require(schema["$defs"] as? [String: Any])
        let prompt = try #require(defs["prompt"] as? [String: Any])
        let variants = try #require(prompt["oneOf"] as? [[String: Any]])
        let kinds = variants.compactMap { (($0["properties"] as? [String: Any])?["type"] as? [String: Any])?["const"] as? String }

        #expect(Set(kinds) == Set(PromptKind.allCases.map(\.rawValue)))
        #expect((schema["properties"] as? [String: Any]).flatMap { ($0["schemaVersion"] as? [String: Any])?["const"] as? Int } == EncoreKit.schemaVersion)
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
