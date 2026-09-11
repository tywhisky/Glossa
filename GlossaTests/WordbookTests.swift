import Foundation
import Testing
@testable import Glossa

struct WordbookTests {
    @Test func backupRoundTripAndMergeKeepDeletionAndRejectConflicts() async throws {
        let time = Date(timeIntervalSinceReferenceDate: 800_000_000.123456)
        var original = WordbookEntry(term: "subtle", sourceLanguage: "en", targetLanguage: "zh-Hans",
                                     context: "A subtle difference.", answerMarkdown: "细微的区别", createdAt: time, updatedAt: time)
        let decoded = try WordbookBackup.decode(WordbookBackup(entries: [original]).encoded())
        #expect(decoded.entries == [original])
        #expect(try WordbookBackup.changes(incoming: decoded.entries, existing: [original]).isEmpty)

        var deleted = original
        deleted.updatedAt = time.addingTimeInterval(10)
        deleted.deletedAt = deleted.updatedAt
        #expect(try WordbookBackup.changes(incoming: [original], existing: [deleted]).isEmpty)
        #expect(try WordbookBackup.changes(incoming: [deleted], existing: [original]) == [deleted])

        original.context = "Same timestamp, different content."
        #expect(throws: WordbookError.self) {
            try WordbookBackup.changes(incoming: [original], existing: decoded.entries)
        }
        #expect(throws: WordbookError.self) {
            try WordbookBackup.decode(WordbookBackup(entries: [original, original]).encoded())
        }
        #expect(throws: WordbookError.self) {
            try WordbookBackup.decode(Data("{\"formatVersion\":999}".utf8))
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: "GlossaWordbook-\(UUID())")
        let database = WordbookDatabase(url: directory.appending(path: "wordbook.store"), cloudIdentifier: nil)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await database.merge(decoded.entries)
        try await database.merge([deleted])
        var invalid = original
        invalid.id = UUID()
        invalid.term = ""
        do {
            try await database.merge([original, invalid])
            Issue.record("Invalid imports must fail before saving any changes")
        } catch { }
        let stored = try await database.entries()
        #expect(stored == [deleted])
        let reopened = WordbookDatabase(url: directory.appending(path: "wordbook.store"), cloudIdentifier: nil)
        #expect(try await reopened.entries() == [deleted])
    }

    @Test func memoryNoteValidatesProviderOutput() throws {
        let valid = "```json\n{\"meaning\":\"细微而难以察觉\",\"memoryHook\":\"subtle difference\"}\n```"
        #expect(try WordbookMemoryNote.decode(valid).memoryHook == "subtle difference")
        #expect(throws: (any Error).self) { try WordbookMemoryNote.decode("{\"meaning\":\"\",\"memoryHook\":\"\"}") }
        #expect(throws: (any Error).self) { try WordbookMemoryNote.decode("not JSON") }
    }
}
