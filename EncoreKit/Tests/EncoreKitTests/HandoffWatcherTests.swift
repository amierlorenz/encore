import Foundation
@testable import EncoreKit
import SwiftData
import Testing

#if os(macOS)
@MainActor
struct HandoffWatcherTests {
    private func makeTempHandoff() throws -> (HandoffFolder, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "encore-test-\(UUID().uuidString)")
        let folder = HandoffFolder(rootURL: tempDir)
        return (folder, tempDir)
    }

    private func makeValidImportJSON(batchId: String = "batch-\(UUID().uuidString)") -> Data {
        let json = """
        {
          "header": {
            "schema": "encore.import",
            "version": 2,
            "id": "\(batchId)",
            "created_at": "2026-11-20T12:00:00Z",
            "producer": "articulate 0.1.0"
          },
          "courses": [
            {
              "id": "csc301",
              "name": "Operating Systems",
              "units": [
                {
                  "id": "csc301.processes",
                  "name": "Processes",
                  "order": 1,
                  "concepts": [
                    {
                      "id": "csc301.process",
                      "title": "Process",
                      "explanation": "A running program.",
                      "kind": "definition",
                      "status": "active",
                      "tier": "core",
                      "details": {
                        "explanationCitations": [],
                        "aliases": [],
                        "useWhen": [],
                        "conditions": [],
                        "workedExamples": []
                      },
                      "groupIds": [],
                      "tags": [],
                      "prompts": [
                        {
                          "id": "p1",
                          "kind": "flashcard",
                          "status": "active",
                          "content": {
                            "type": "flashcard",
                            "front": "What is a process?",
                            "back": "A running program."
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        return Data(json.utf8)
    }

    @Test func createsDirectoriesIfMissing() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let watcher = HandoffWatcher(handoffFolder: folder, context: container.mainContext)

        #expect(!FileManager.default.fileExists(atPath: folder.toEncoreURL.path))
        #expect(!FileManager.default.fileExists(atPath: folder.failedURL.path))
        #expect(!FileManager.default.fileExists(atPath: folder.fromEncoreURL.path))

        watcher.start()
        defer { watcher.stop() }

        #expect(FileManager.default.fileExists(atPath: folder.toEncoreURL.path))
        #expect(FileManager.default.fileExists(atPath: folder.failedURL.path))
        #expect(FileManager.default.fileExists(atPath: folder.fromEncoreURL.path))
    }

    @Test func scansAndImportsFilesInNameOrder() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = container.mainContext
        let watcher = HandoffWatcher(handoffFolder: folder, context: context)

        // Write three files in unordered timestamps
        let file03 = folder.toEncoreURL.appending(path: "import-03.json")
        let file01 = folder.toEncoreURL.appending(path: "import-01.json")
        let file02 = folder.toEncoreURL.appending(path: "import-02.json")

        try makeValidImportJSON(batchId: "batch-03").write(to: file03)
        try makeValidImportJSON(batchId: "batch-01").write(to: file01)
        try makeValidImportJSON(batchId: "batch-02").write(to: file02)

        let result = watcher.scan()
        #expect(result.importedFiles == ["import-01.json", "import-02.json", "import-03.json"])

        // All successful files must be deleted
        #expect(!FileManager.default.fileExists(atPath: file01.path))
        #expect(!FileManager.default.fileExists(atPath: file02.path))
        #expect(!FileManager.default.fileExists(atPath: file03.path))

        // AppliedBatch records must exist
        let batches = try context.fetch(FetchDescriptor<AppliedBatch>())
        let batchIDs = Set(batches.map(\.batchID))
        #expect(batchIDs.contains("batch-01"))
        #expect(batchIDs.contains("batch-02"))
        #expect(batchIDs.contains("batch-03"))
    }

    @Test func skipsDotfilesAndTmpFilesUntilRenamed() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let watcher = HandoffWatcher(handoffFolder: folder, context: container.mainContext)

        let tmpDotFile = folder.toEncoreURL.appending(path: ".import-test.json.tmp")
        let tmpFile = folder.toEncoreURL.appending(path: "import-test.tmp")

        try makeValidImportJSON(batchId: "batch-tmp").write(to: tmpDotFile)
        try makeValidImportJSON(batchId: "batch-tmp2").write(to: tmpFile)

        // Scan should skip both
        let result1 = watcher.scan()
        #expect(result1.importedFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: tmpDotFile.path))
        #expect(FileManager.default.fileExists(atPath: tmpFile.path))

        // Rename .import-test.json.tmp to import-test.json
        let targetFile = folder.toEncoreURL.appending(path: "import-test.json")
        try FileManager.default.moveItem(at: tmpDotFile, to: targetFile)

        // Next scan should pick it up and delete it on success
        let result2 = watcher.scan()
        #expect(result2.importedFiles == ["import-test.json"])
        #expect(!FileManager.default.fileExists(atPath: targetFile.path))
    }

    @Test func handsPlanAndPostclassToPlanHandlerWithoutDeletingPlan() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let planURL = folder.toEncoreURL.appending(path: "plan.json")
        let postclassURL = folder.toEncoreURL.appending(path: "postclass-csc301-l1.json")

        let planJSON = """
        {
          "header": {
            "schema": "encore.plan",
            "version": 1,
            "id": "plan-1",
            "created_at": "2026-11-20T02:00:00Z",
            "producer": "articulate 0.1.0"
          },
          "kind": "daily",
          "date": "2026-11-20",
          "validUntil": "2026-11-21T02:00:00Z",
          "reviewScope": ["csc301"],
          "new": []
        }
        """
        try Data(planJSON.utf8).write(to: planURL)
        try Data(planJSON.utf8).write(to: postclassURL)

        var handedURLs: [String] = []
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let watcher = HandoffWatcher(handoffFolder: folder, context: container.mainContext) { url in
            handedURLs.append(url.lastPathComponent)
        }

        let result = watcher.scan()
        #expect(result.planFiles == ["plan.json", "postclass-csc301-l1.json"])
        #expect(handedURLs == ["plan.json", "postclass-csc301-l1.json"])

        // plan.json must not be deleted!
        #expect(FileManager.default.fileExists(atPath: planURL.path))
    }

    @Test func failedImportMovesToFailedDirectoryWithErrorFile() throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try folder.createDirectoriesIfNeeded()

        let badFile = folder.toEncoreURL.appending(path: "import-corrupt.json")
        try Data("corrupted invalid json".utf8).write(to: badFile)

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let watcher = HandoffWatcher(handoffFolder: folder, context: container.mainContext)

        let result = watcher.scan()
        #expect(result.failedFiles == ["import-corrupt.json"])

        // File should be moved to failed/
        #expect(!FileManager.default.fileExists(atPath: badFile.path))
        let failedFile = folder.failedURL.appending(path: "import-corrupt.json")
        #expect(FileManager.default.fileExists(atPath: failedFile.path))

        // Error txt should be written
        let errorFile = folder.failedURL.appending(path: "corrupt.error.txt")
        #expect(FileManager.default.fileExists(atPath: errorFile.path))
    }

    @Test func fileSystemWatcherImportsAndDeletesLiveDroppedFile() async throws {
        let (folder, tempDir) = try makeTempHandoff()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try ModelContainerFactory.make(storage: .inMemory)
        let watcher = HandoffWatcher(handoffFolder: folder, context: container.mainContext)

        watcher.start()
        defer { watcher.stop() }

        // Live write: write as .tmp then rename to import-live.json
        let tmpFile = folder.toEncoreURL.appending(path: ".import-live.json.tmp")
        let finalFile = folder.toEncoreURL.appending(path: "import-live.json")

        try makeValidImportJSON(batchId: "batch-live").write(to: tmpFile)
        try FileManager.default.moveItem(at: tmpFile, to: finalFile)

        // Wait up to 2 seconds for dispatch source event to fire and scan
        var processed = false
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if !FileManager.default.fileExists(atPath: finalFile.path) {
                processed = true
                break
            }
        }

        #expect(processed)
        #expect(!FileManager.default.fileExists(atPath: finalFile.path))
    }
}
#endif
