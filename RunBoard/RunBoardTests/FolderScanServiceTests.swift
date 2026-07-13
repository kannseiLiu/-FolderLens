import Foundation
import Testing
@testable import RunBoard

struct FolderScanServiceTests {
    @Test func shallowScanReturnsOnlyDirectChildren() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("root".utf8).write(to: root.appendingPathComponent("root.txt"))
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("nested.txt"))

        let context = FolderScanContext(
            folderURL: root,
            isDeepScan: false,
            settings: .default
        )
        let result = try await FolderScanService().scan(context: context) { _ in }

        #expect(result.directChildren.map(\.name).sorted() == ["Nested", "root.txt"])
        #expect(result.analysisItems.map(\.name).sorted() == ["Nested", "root.txt"])
        #expect(result.warnings.isEmpty)
    }

    @Test func deepScanIncludesNestedFilesAndReportsFinalProgress() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("nested.txt"))

        let recorder = ProgressRecorder()
        let context = FolderScanContext(
            folderURL: root,
            isDeepScan: true,
            settings: .default
        )
        let result = try await FolderScanService().scan(context: context) { progress in
            await recorder.append(progress)
        }

        let progressValues = await recorder.values
        #expect(result.analysisItems.contains { $0.name == "nested.txt" })
        #expect(progressValues.last?.processedItemCount == result.analysisItems.count)
    }

    @Test func hiddenFilesFollowScanSettings() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("hidden".utf8).write(to: root.appendingPathComponent(".secret"))
        try Data("visible".utf8).write(to: root.appendingPathComponent("visible.txt"))

        let skipped = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: false, settings: .default)
        ) { _ in }
        let includedSettings = ScanSettings(
            largeFileThresholdMB: 100,
            oldFileAgeYears: 1,
            includeHiddenFiles: true
        )
        let included = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: false, settings: includedSettings)
        ) { _ in }

        #expect(!skipped.directChildren.contains { $0.name == ".secret" })
        #expect(included.directChildren.contains { $0.name == ".secret" })
    }

    private func makeTemporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderLensTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

private actor ProgressRecorder {
    private(set) var values: [FolderScanProgress] = []

    func append(_ progress: FolderScanProgress) {
        values.append(progress)
    }
}
