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

    @Test func completedMetadataScanAutomaticallyStartsVerification() async throws {
        let scanner = ControlledScanner()
        let verifier = ControlledVerifier()
        let model = FolderScanViewModel(scanner: scanner, verifier: verifier)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Verification-Starts")
        let file = makeFile(root.appendingPathComponent("candidate.txt"), size: 10)

        model.start(context: .init(folderURL: root, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        await scanner.completeRequest(
            at: 0,
            with: .init(directChildren: [file], analysisItems: [file], warnings: [])
        )
        await verifier.waitForRequestCount(1)

        #expect(model.status == .verifyingDuplicates)
        #expect(model.files.isEmpty)
        #expect(model.summary == nil)
        #expect(model.verificationProgress == .init(completedFileCount: 0, totalFileCount: 0))

        await verifier.publishProgress(.init(completedFileCount: 0, totalFileCount: 1), forRequestAt: 0)

        #expect(model.verificationProgress == .init(completedFileCount: 0, totalFileCount: 1))

        await verifier.completeRequest(at: 0, with: .empty)
        await waitUntilSettled(model)
    }

    @Test func completedVerificationPublishesVerifiedSummaryAndIssues() async throws {
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Verification-Completes")
        let file = makeFile(root.appendingPathComponent("report.txt"), size: 10)
        let issue = DuplicateVerificationIssue(url: file.url, message: "Unreadable")
        let scanner = ImmediateScanner(
            result: .init(directChildren: [file], analysisItems: [file], warnings: [])
        )
        let verifier = ImmediateVerifier(
            result: .init(groups: [], issues: [issue]),
            totalFileCount: 1
        )
        let model = FolderScanViewModel(scanner: scanner, verifier: verifier)

        model.start(context: .init(folderURL: root, isDeepScan: false, settings: .default))
        await waitUntilSettled(model)

        #expect(model.status == .completed)
        #expect(model.files.map(\.name) == ["report.txt"])
        #expect(model.summary?.folderURL == root)
        #expect(model.verificationIssues == [issue])
        #expect(model.verificationProgress == .init(completedFileCount: 1, totalFileCount: 1))
    }

    @Test func noCandidatesStillCompletesThroughVerifier() async throws {
        let scanner = ImmediateScanner(
            result: .init(directChildren: [], analysisItems: [], warnings: [])
        )
        let verifier = ControlledVerifier()
        let model = FolderScanViewModel(scanner: scanner, verifier: verifier)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-No-Candidates")

        model.start(context: .init(folderURL: root, isDeepScan: false, settings: .default))
        await verifier.waitForRequestCount(1)

        #expect(await verifier.files(forRequestAt: 0).isEmpty)
        #expect(model.status == .verifyingDuplicates)

        await verifier.completeRequest(at: 0, with: .empty)
        await waitUntilSettled(model)

        #expect(model.status == .completed)
        #expect(model.verificationProgress == .init(completedFileCount: 0, totalFileCount: 0))
    }

    @Test func cancellingVerificationPublishesCancelledAndIgnoresLateCompletion() async throws {
        let scanner = ImmediateScanner(
            result: result(named: "late.txt", root: URL(fileURLWithPath: "/tmp/FolderLens-Cancel-Verification"))
        )
        let verifier = ControlledVerifier()
        let model = FolderScanViewModel(scanner: scanner, verifier: verifier)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Cancel-Verification")

        model.start(context: .init(folderURL: root, isDeepScan: true, settings: .default))
        await verifier.waitForRequestCount(1)
        model.cancel()
        await verifier.completeRequest(at: 0, with: .empty)
        await Task.yield()

        #expect(model.status == .cancelled)
        #expect(model.files.isEmpty)
        #expect(model.summary == nil)
        #expect(model.verificationProgress == nil)
    }

    @Test func supersededVerificationCannotReplaceNewerScan() async throws {
        let scanner = ControlledScanner()
        let verifier = ControlledVerifier()
        let model = FolderScanViewModel(scanner: scanner, verifier: verifier)
        let firstRoot = URL(fileURLWithPath: "/tmp/FolderLens-First-Verification")
        let secondRoot = URL(fileURLWithPath: "/tmp/FolderLens-Second-Verification")

        model.start(context: .init(folderURL: firstRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        await scanner.completeRequest(at: 0, with: result(named: "old.txt", root: firstRoot))
        await verifier.waitForRequestCount(1)

        model.start(context: .init(folderURL: secondRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(2)
        await scanner.completeRequest(at: 1, with: result(named: "new.txt", root: secondRoot))
        await verifier.waitForRequestCount(2)
        await verifier.completeRequest(at: 1, with: .empty)
        await waitUntilSettled(model)
        await verifier.completeRequest(at: 0, with: .empty)
        await Task.yield()

        #expect(model.status == .completed)
        #expect(model.files.map(\.name) == ["new.txt"])
        #expect(model.summary?.folderURL == secondRoot)
    }

    @Test func cancelledVerificationIgnoresLateProgressAndFailure() async throws {
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Cancel-Verification-Progress")
        let scanner = ImmediateScanner(result: result(named: "late.txt", root: root))
        let verifier = ControlledVerifier()
        let model = FolderScanViewModel(scanner: scanner, verifier: verifier)

        model.start(context: .init(folderURL: root, isDeepScan: true, settings: .default))
        await verifier.waitForRequestCount(1)
        model.cancel()
        await verifier.publishProgress(.init(completedFileCount: 1, totalFileCount: 1), forRequestAt: 0)
        await verifier.failRequest(at: 0)
        await Task.yield()

        #expect(model.status == .cancelled)
        #expect(model.verificationProgress == nil)
    }

    @Test func sameContextCancelledVerificationPreservesPreviousCompletedSummary() async throws {
        let scanner = ControlledScanner()
        let verifier = ControlledVerifier()
        let model = FolderScanViewModel(scanner: scanner, verifier: verifier)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Preserve-Verification")
        let context = FolderScanContext(folderURL: root, isDeepScan: true, settings: .default)
        let issue = DuplicateVerificationIssue(url: root.appendingPathComponent("kept.txt"), message: "Unreadable")

        model.start(context: context)
        await scanner.waitForRequestCount(1)
        await scanner.completeRequest(at: 0, with: result(named: "kept.txt", root: root))
        await verifier.waitForRequestCount(1)
        await verifier.completeRequest(at: 0, with: .init(groups: [], issues: [issue]))
        await waitUntilSettled(model)

        model.start(context: context)
        await scanner.waitForRequestCount(2)
        await scanner.completeRequest(at: 1, with: result(named: "replacement.txt", root: root))
        await verifier.waitForRequestCount(2)
        model.cancel()
        await verifier.completeRequest(at: 1, with: .empty)
        await Task.yield()

        #expect(model.status == .cancelled)
        #expect(model.files.map(\.name) == ["kept.txt"])
        #expect(model.summary?.folderURL == root)
        #expect(model.verificationIssues == [issue])
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

    @Test func cancelledScanStaysCancelledWhenScannerFailsLate() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Cancel-Failure")

        model.start(context: .init(folderURL: root, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.cancel()
        await scanner.failRequest(at: 0)
        await Task.yield()

        #expect(model.status == .cancelled)
        #expect(model.progress == nil)
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

    @Test func newerCompletedScanStaysCompletedWhenOlderScanFailsLate() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let firstRoot = URL(fileURLWithPath: "/tmp/FolderLens-First-Failure")
        let secondRoot = URL(fileURLWithPath: "/tmp/FolderLens-Second-Failure")

        model.start(context: .init(folderURL: firstRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.start(context: .init(folderURL: secondRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(2)

        await scanner.completeRequest(at: 1, with: result(named: "new.txt", root: secondRoot))
        await waitUntilSettled(model)
        await scanner.failRequest(at: 0)
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
        let warning = FolderScanWarning(path: "/tmp/FolderLens-Preserve/denied", message: "Denied")

        model.start(context: context)
        await scanner.waitForRequestCount(1)
        await scanner.completeRequest(
            at: 0,
            with: result(named: "kept.txt", root: root, warnings: [warning])
        )
        await waitUntilSettled(model)

        model.start(context: context)
        await scanner.waitForRequestCount(2)
        model.cancel()

        #expect(model.status == .cancelled)
        #expect(model.files.map(\.name) == ["kept.txt"])
        #expect(model.summary?.folderURL == root)
        #expect(model.warnings == [warning])
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

    @Test func supersededScanIgnoresLateProgressWithoutReplacingActiveScanState() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let firstRoot = URL(fileURLWithPath: "/tmp/FolderLens-First-Progress")
        let secondRoot = URL(fileURLWithPath: "/tmp/FolderLens-Second-Progress")

        model.start(context: .init(folderURL: firstRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.start(context: .init(folderURL: secondRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(2)
        await scanner.publishProgress(.init(processedItemCount: 2), forRequestAt: 1)
        await scanner.publishProgress(.init(processedItemCount: 99), forRequestAt: 0)
        await Task.yield()

        #expect(model.status == .scanning)
        #expect(model.progress == .init(processedItemCount: 2))

        await scanner.completeRequest(at: 1, with: result(named: "active.txt", root: secondRoot))
        await scanner.completeRequest(at: 0, with: result(named: "stale.txt", root: firstRoot))
        await waitUntilSettled(model)
    }

    private func makeFile(_ url: URL, size: Int64) -> FileItem {
        FileItem(url: url, name: url.lastPathComponent, isDirectory: false, size: size, modifiedDate: Date())
    }

    private func waitUntilSettled(_ model: FolderScanViewModel) async {
        while model.status == .scanning || model.status == .verifyingDuplicates {
            await Task.yield()
        }
    }

    private func result(
        named name: String,
        root: URL,
        warnings: [FolderScanWarning] = []
    ) -> FolderScanResult {
        let file = makeFile(root.appendingPathComponent(name), size: 10)
        return FolderScanResult(directChildren: [file], analysisItems: [file], warnings: warnings)
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

private struct ImmediateVerifier: DuplicateVerifying {
    let result: DuplicateVerificationResult
    let totalFileCount: Int

    func verify(
        files: [FileItem],
        onProgress: @escaping DuplicateVerificationProgressHandler
    ) async throws -> DuplicateVerificationResult {
        await onProgress(.init(completedFileCount: 0, totalFileCount: totalFileCount))
        await onProgress(.init(completedFileCount: totalFileCount, totalFileCount: totalFileCount))
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

    func failRequest(at index: Int) {
        requests[index].continuation?.resume(throwing: ControlledScannerError.expected)
        requests[index].continuation = nil
    }

    func publishProgress(_ progress: FolderScanProgress, forRequestAt index: Int) async {
        await requests[index].onProgress(progress)
    }
}

private actor ControlledVerifier: DuplicateVerifying {
    private struct Request {
        let files: [FileItem]
        let onProgress: DuplicateVerificationProgressHandler
        var continuation: CheckedContinuation<DuplicateVerificationResult, Error>?
    }

    private var requests: [Request] = []

    func verify(
        files: [FileItem],
        onProgress: @escaping DuplicateVerificationProgressHandler
    ) async throws -> DuplicateVerificationResult {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(.init(files: files, onProgress: onProgress, continuation: continuation))
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func files(forRequestAt index: Int) -> [FileItem] {
        requests[index].files
    }

    func completeRequest(at index: Int, with result: DuplicateVerificationResult) {
        requests[index].continuation?.resume(returning: result)
        requests[index].continuation = nil
    }

    func failRequest(at index: Int) {
        requests[index].continuation?.resume(throwing: ControlledScannerError.expected)
        requests[index].continuation = nil
    }

    func publishProgress(_ progress: DuplicateVerificationProgress, forRequestAt index: Int) async {
        await requests[index].onProgress(progress)
    }
}

private enum ControlledScannerError: Error {
    case expected
}
