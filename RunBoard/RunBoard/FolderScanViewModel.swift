import Combine
import Foundation

@MainActor
final class FolderScanViewModel: ObservableObject {
    @Published private(set) var files: [FileItem] = []
    @Published private(set) var summary: FolderSummary?
    @Published private(set) var status: FolderScanStatus = .idle
    @Published private(set) var progress: FolderScanProgress?
    @Published private(set) var warnings: [FolderScanWarning] = []

    private let scanner: any FolderScanning
    private var scanTask: Task<Void, Never>?
    private var activeScanID = UUID()
    private var lastCompletedContext: FolderScanContext?

    init(scanner: any FolderScanning = FolderScanService()) {
        self.scanner = scanner
    }

    func start(context: FolderScanContext) {
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID

        let canPreserveCompletedResult = lastCompletedContext == context && summary != nil
        if !canPreserveCompletedResult {
            files = []
            summary = nil
            warnings = []
        }

        progress = .init(processedItemCount: 0)
        status = .scanning

        scanTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await scanner.scan(context: context) { [weak self] progress in
                    await self?.publish(progress: progress, scanID: scanID)
                }

                guard scanID == activeScanID else { return }

                files = result.directChildren
                summary = FolderAnalyzer.makeSummary(
                    for: context.folderURL,
                    files: result.analysisItems,
                    isDeepScan: context.isDeepScan,
                    settings: context.settings
                )
                warnings = result.warnings
                progress = .init(processedItemCount: result.analysisItems.count)
                status = .completed
                lastCompletedContext = context
                scanTask = nil
            } catch is CancellationError {
                guard scanID == activeScanID else { return }

                status = .cancelled
                progress = nil
                scanTask = nil
            } catch {
                guard scanID == activeScanID else { return }

                status = .failed(error.localizedDescription)
                progress = nil
                scanTask = nil
            }
        }
    }

    func cancel() {
        guard status == .scanning else { return }

        activeScanID = UUID()
        scanTask?.cancel()
        scanTask = nil
        status = .cancelled
        progress = nil
    }

    private func publish(progress newProgress: FolderScanProgress, scanID: UUID) {
        guard scanID == activeScanID, status == .scanning else { return }
        progress = newProgress
    }
}
