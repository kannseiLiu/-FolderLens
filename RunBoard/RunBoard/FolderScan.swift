import Foundation

struct FolderScanContext: Equatable {
    let folderURL: URL
    let isDeepScan: Bool
    let settings: ScanSettings
}

struct FolderScanProgress: Equatable {
    let processedItemCount: Int
}

struct FolderScanWarning: Equatable, Identifiable {
    let path: String
    let message: String

    var id: String { "\(path)|\(message)" }
}

struct FolderScanResult {
    let directChildren: [FileItem]
    let analysisItems: [FileItem]
    let warnings: [FolderScanWarning]
}

enum FolderScanStatus: Equatable {
    case idle
    case scanning
    case completed
    case cancelled
    case failed(String)
}

enum FolderScanError: LocalizedError {
    case rootUnavailable(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .rootUnavailable(path, reason):
            return "Could not scan \(path): \(reason)"
        }
    }
}

typealias FolderScanProgressHandler = @Sendable (FolderScanProgress) async -> Void

protocol FolderScanning {
    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult
}
