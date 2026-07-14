import Combine
import Foundation

@MainActor
final class FolderScanViewModel: ObservableObject {
    @Published private(set) var files: [FileItem] = []
    @Published private(set) var summary: FolderSummary?
    @Published private(set) var status: FolderScanStatus = .idle
    @Published private(set) var progress: FolderScanProgress?
    @Published private(set) var verificationProgress: DuplicateVerificationProgress?
    @Published private(set) var verificationIssues: [DuplicateVerificationIssue] = []
    @Published private(set) var warnings: [FolderScanWarning] = []

    private let scanner: any FolderScanning
    private let verifier: any DuplicateVerifying
    private var scanTask: Task<Void, Never>?
    private var activeScanID = UUID()
    private var lastCompletedContext: FolderScanContext?

    init(
        scanner: any FolderScanning = FolderScanService(),
        verifier: any DuplicateVerifying = DuplicateVerifier()
    ) {
        self.scanner = scanner
        self.verifier = verifier
    }

    func start(context: FolderScanContext) {
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID

        let canPreserveCompletedResult = lastCompletedContext == context && summary != nil
        if !canPreserveCompletedResult {
            files = []
            summary = nil
            verificationIssues = []
            warnings = []
        }

        progress = .init(processedItemCount: 0)
        verificationProgress = nil
        status = .scanning

        scanTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await scanner.scan(context: context) { [weak self] progress in
                    await self?.publish(progress: progress, scanID: scanID)
                }

                guard scanID == activeScanID, status == .scanning else { return }

                status = .verifyingDuplicates
                verificationProgress = .init(completedFileCount: 0, totalFileCount: 0)
                let verification = try await verifier.verify(files: result.analysisItems) { [weak self] progress in
                    await self?.publish(verificationProgress: progress, scanID: scanID)
                }

                guard scanID == activeScanID, status == .verifyingDuplicates else { return }

                files = result.directChildren
                summary = FolderAnalyzer.makeSummary(
                    for: context.folderURL,
                    files: result.analysisItems,
                    isDeepScan: context.isDeepScan,
                    verification: verification,
                    settings: context.settings
                )
                warnings = result.warnings
                verificationIssues = verification.issues
                progress = .init(processedItemCount: result.analysisItems.count)
                status = .completed
                lastCompletedContext = context
                scanTask = nil
            } catch is CancellationError {
                guard scanID == activeScanID, status == .scanning || status == .verifyingDuplicates else { return }

                status = .cancelled
                progress = nil
                verificationProgress = nil
                scanTask = nil
            } catch {
                guard scanID == activeScanID, status == .scanning || status == .verifyingDuplicates else { return }

                status = .failed(error.localizedDescription)
                progress = nil
                verificationProgress = nil
                scanTask = nil
            }
        }
    }

    func cancel() {
        guard status == .scanning || status == .verifyingDuplicates else { return }

        activeScanID = UUID()
        scanTask?.cancel()
        scanTask = nil
        status = .cancelled
        progress = nil
        verificationProgress = nil
    }

    private func publish(progress newProgress: FolderScanProgress, scanID: UUID) {
        guard scanID == activeScanID, status == .scanning else { return }
        progress = newProgress
    }

    private func publish(verificationProgress newProgress: DuplicateVerificationProgress, scanID: UUID) {
        guard scanID == activeScanID, status == .verifyingDuplicates else { return }
        verificationProgress = newProgress
    }
}
