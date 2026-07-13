import Foundation

enum FolderHealthLevel: Equatable {
    case excellent
    case good
    case needsReview
    case critical

    var title: String {
        switch self {
        case .excellent:
            return "Excellent"
        case .good:
            return "Good"
        case .needsReview:
            return "Needs review"
        case .critical:
            return "Critical"
        }
    }

    var systemImage: String {
        switch self {
        case .excellent:
            return "checkmark.seal.fill"
        case .good:
            return "checkmark.circle.fill"
        case .needsReview:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        }
    }
}

struct FolderActionItem: Identifiable, Equatable {
    let title: String
    let detail: String
    let systemImage: String

    var id: String {
        title
    }
}

struct FolderSummary {
    let folderURL: URL
    let totalCount: Int
    let folderCount: Int
    let imageCount: Int
    let csvCount: Int
    let jsonCount: Int
    let textCount: Int
    let logCount: Int
    let pdfCount: Int
    let archiveCount: Int
    let videoCount: Int
    let codeCount: Int
    let otherCount: Int
    let totalSize: Int64
    let largestFiles: [FileItem]
    let recentFiles: [FileItem]
    let largeFiles: [FileItem]
    let oldFiles: [FileItem]
    let temporaryFiles: [FileItem]
    let isDeepScan: Bool

    var folderName: String {
        folderURL.lastPathComponent
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var cleanupCandidateCount: Int {
        largeFiles.count + oldFiles.count + temporaryFiles.count
    }

    var healthScore: Int {
        let largeFilePenalty = min(largeFiles.count * 12, 28)
        let oldFilePenalty = min(oldFiles.count * 10, 24)
        let temporaryFilePenalty = min(temporaryFiles.count * 8, 20)
        let unknownTypePenalty = min(Int((Double(otherCount) / Double(max(totalCount, 1)) * 16).rounded()), 16)
        let shallowScanPenalty = isDeepScan ? 0 : 4

        return max(0, 100 - largeFilePenalty - oldFilePenalty - temporaryFilePenalty - unknownTypePenalty - shallowScanPenalty)
    }

    var healthLevel: FolderHealthLevel {
        switch healthScore {
        case 85...100:
            return .excellent
        case 70..<85:
            return .good
        case 45..<70:
            return .needsReview
        default:
            return .critical
        }
    }

    var healthSummary: String {
        healthLevel.title
    }

    var actionPlan: [FolderActionItem] {
        var actions: [FolderActionItem] = []

        if !largeFiles.isEmpty {
            actions.append(
                FolderActionItem(
                    title: "Review \(largeFiles.count) \(largeFiles.count == 1 ? "large file" : "large files")",
                    detail: "Start with files over 100 MB to quickly reclaim disk space.",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
            )
        }

        if !oldFiles.isEmpty {
            actions.append(
                FolderActionItem(
                    title: "Archive or remove \(oldFiles.count) \(oldFiles.count == 1 ? "old file" : "old files")",
                    detail: "These files have not changed for more than one year.",
                    systemImage: "clock.badge.exclamationmark"
                )
            )
        }

        if !temporaryFiles.isEmpty {
            actions.append(
                FolderActionItem(
                    title: "Check \(temporaryFiles.count) \(temporaryFiles.count == 1 ? "temporary file" : "temporary files")",
                    detail: "Cache, backup, and temporary files are often safe to clean after review.",
                    systemImage: "trash"
                )
            )
        }

        if otherCount > 0 {
            actions.append(
                FolderActionItem(
                    title: "Review \(otherCount) uncategorized \(otherCount == 1 ? "item" : "items")",
                    detail: "Unknown file types may hide project outputs, binaries, or generated artifacts.",
                    systemImage: "questionmark.folder"
                )
            )
        }

        if actions.isEmpty {
            actions.append(
                FolderActionItem(
                    title: "Folder looks healthy",
                    detail: "No large, old, or temporary cleanup candidates were found.",
                    systemImage: "checkmark.seal"
                )
            )
        }

        return actions
    }
}
