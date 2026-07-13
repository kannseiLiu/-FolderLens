import Foundation
import Testing
@testable import RunBoard

@MainActor
struct FolderScanViewModelTests {
    @Test func completedScanPublishesFilesSummaryAndWarnings() async throws {
        let root = URL(fileURLWithPath: "/tmp/FolderLens-A")
        let file = makeFile(root.appendingPathComponent("notes.md"), size: 12)
        let warning = FolderScanWarning(path: "/tmp/denied", message: "Denied")
        let scanner = ImmediateScanner(
            result: FolderScanResult(
                directChildren: [file],
                analysisItems: [file],
                warnings: [warning]
            )
        )
        let model = FolderScanViewModel(scanner: scanner)

        model.start(context: .init(folderURL: root, isDeepScan: false, settings: .default))
        await waitUntilSettled(model)

        #expect(model.status == .completed)
        #expect(model.files.map(\.name) == ["notes.md"])
        #expect(model.summary?.folderURL == root)
        #expect(model.warnings == [warning])
    }

    @Test func cancellingScanPublishesCancelledAndIgnoresLateCompletion() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Cancel")

        model.start(context: .init(folderURL: root, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.cancel()
        await scanner.completeRequest(
            at: 0,
            with: result(named: "late.txt", root: root)
        )
        await Task.yield()

        #expect(model.status == .cancelled)
        #expect(model.files.isEmpty)
        #expect(model.summary == nil)
    }

    @Test func newerScanWinsWhenOlderScanCompletesLast() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let firstRoot = URL(fileURLWithPath: "/tmp/FolderLens-First")
        let secondRoot = URL(fileURLWithPath: "/tmp/FolderLens-Second")

        model.start(context: .init(folderURL: firstRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.start(context: .init(folderURL: secondRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(2)

        await scanner.completeRequest(at: 1, with: result(named: "new.txt", root: secondRoot))
        await waitUntilSettled(model)
        await scanner.completeRequest(at: 0, with: result(named: "old.txt", root: firstRoot))
        await Task.yield()

        #expect(model.status == .completed)
        #expect(model.files.map(\.name) == ["new.txt"])
        #expect(model.summary?.folderURL == secondRoot)
    }

    @Test func cancelledRescanKeepsCompletedResultForSameContext() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Preserve")
        let context = FolderScanContext(folderURL: root, isDeepScan: true, settings: .default)

        model.start(context: context)
        await scanner.waitForRequestCount(1)
        await scanner.completeRequest(at: 0, with: result(named: "kept.txt", root: root))
        await waitUntilSettled(model)

        model.start(context: context)
        await scanner.waitForRequestCount(2)
        model.cancel()

        #expect(model.status == .cancelled)
        #expect(model.files.map(\.name) == ["kept.txt"])
        #expect(model.summary?.folderURL == root)
    }

    @Test func contextChangeClearsPreviousCompletedResultWhileNewScanRuns() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let firstRoot = URL(fileURLWithPath: "/tmp/FolderLens-Clear-First")
        let secondRoot = URL(fileURLWithPath: "/tmp/FolderLens-Clear-Second")

        model.start(context: .init(folderURL: firstRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        await scanner.completeRequest(at: 0, with: result(named: "previous.txt", root: firstRoot))
        await waitUntilSettled(model)

        model.start(context: .init(folderURL: secondRoot, isDeepScan: true, settings: .default))

        #expect(model.status == .scanning)
        #expect(model.files.isEmpty)
        #expect(model.summary == nil)
        #expect(model.warnings.isEmpty)
    }

    @Test func cancelledScanIgnoresLateProgressFromScannerThatDoesNotCooperate() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Stale-Progress")

        model.start(context: .init(folderURL: root, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.cancel()
        await scanner.publishProgress(.init(processedItemCount: 99), forRequestAt: 0)
        await Task.yield()

        #expect(model.status == .cancelled)
        #expect(model.progress == nil)
    }

    private func makeFile(_ url: URL, size: Int64) -> FileItem {
        FileItem(url: url, name: url.lastPathComponent, isDirectory: false, size: size, modifiedDate: Date())
    }

    private func waitUntilSettled(_ model: FolderScanViewModel) async {
        while model.status == .scanning {
            await Task.yield()
        }
    }

    private func result(named name: String, root: URL) -> FolderScanResult {
        let file = makeFile(root.appendingPathComponent(name), size: 10)
        return FolderScanResult(directChildren: [file], analysisItems: [file], warnings: [])
    }
}

private struct ImmediateScanner: FolderScanning {
    let result: FolderScanResult

    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        await onProgress(.init(processedItemCount: result.analysisItems.count))
        return result
    }
}

private actor ControlledScanner: FolderScanning {
    private struct Request {
        let onProgress: FolderScanProgressHandler
        var continuation: CheckedContinuation<FolderScanResult, Error>?
    }

    private var requests: [Request] = []

    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(.init(onProgress: onProgress, continuation: continuation))
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func completeRequest(at index: Int, with result: FolderScanResult) {
        requests[index].continuation?.resume(returning: result)
        requests[index].continuation = nil
    }

    func publishProgress(_ progress: FolderScanProgress, forRequestAt index: Int) async {
        await requests[index].onProgress(progress)
    }
}
