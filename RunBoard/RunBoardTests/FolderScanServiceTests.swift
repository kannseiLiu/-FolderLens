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

    @Test func cancellingCallerCancelsDetachedScan() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<101 {
            try Data().write(to: root.appendingPathComponent("file-\(index).txt"))
        }

        let gate = ProgressGate()
        let scanTask = Task {
            try await FolderScanService().scan(
                context: FolderScanContext(folderURL: root, isDeepScan: true, settings: .default)
            ) { progress in
                await gate.pause(at: progress)
            }
        }

        await gate.waitUntilPaused()
        scanTask.cancel()
        await gate.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await scanTask.value
        }
    }

    @Test func deepScanDoesNotTraverseSymbolicLinkDescendants() async throws {
        let parent = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = parent.appendingPathComponent("Root", isDirectory: true)
        let target = parent.appendingPathComponent("LinkTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("linked".utf8).write(to: target.appendingPathComponent("linked-child.txt"))

        let link = root.appendingPathComponent("LinkedFolder")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: true, settings: .default)
        ) { _ in }

        #expect(result.analysisItems.contains { $0.url.path == link.path })
        #expect(!result.analysisItems.contains { $0.url.path.hasPrefix("\(link.path)/") })
    }

    @Test func deepScanDoesNotTraversePackageDescendants() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let package = root.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        let packageChild = package.appendingPathComponent("inside-package.txt")
        try Data("package".utf8).write(to: packageChild)

        let result = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: true, settings: .default)
        ) { _ in }

        #expect(result.analysisItems.contains { $0.url.path == package.path })
        #expect(!result.analysisItems.contains { $0.url.path == packageChild.path })
    }

    @Test func deepScanHiddenFilesFollowScanSettings() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let hiddenDirectory = root.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: false)
        let hiddenFile = hiddenDirectory.appendingPathComponent("hidden.txt")
        try Data("hidden".utf8).write(to: hiddenFile)

        let skipped = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: true, settings: .default)
        ) { _ in }
        let includedSettings = ScanSettings(
            largeFileThresholdMB: 100,
            oldFileAgeYears: 1,
            includeHiddenFiles: true
        )
        let included = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: true, settings: includedSettings)
        ) { _ in }

        #expect(!skipped.analysisItems.contains { $0.url.path == hiddenDirectory.path })
        #expect(!skipped.analysisItems.contains { $0.url.path == hiddenFile.path })
        #expect(included.analysisItems.contains { $0.url.path == hiddenDirectory.path })
        #expect(included.analysisItems.contains { $0.url.path == hiddenFile.path })
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

private actor ProgressGate {
    private var hasPaused = false
    private var pauseWaiter: CheckedContinuation<Void, Never>?
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    func pause(at progress: FolderScanProgress) async {
        guard progress.processedItemCount == 100 else {
            return
        }

        hasPaused = true
        pauseWaiter?.resume()
        pauseWaiter = nil

        await withCheckedContinuation { continuation in
            resumeWaiter = continuation
        }
    }

    func waitUntilPaused() async {
        guard !hasPaused else {
            return
        }

        await withCheckedContinuation { continuation in
            pauseWaiter = continuation
        }
    }

    func resume() {
        resumeWaiter?.resume()
        resumeWaiter = nil
    }
}
