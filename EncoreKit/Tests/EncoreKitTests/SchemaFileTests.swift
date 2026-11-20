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
}
