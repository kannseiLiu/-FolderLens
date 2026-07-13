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

struct FolderHotspot: Identifiable, Equatable {
    let url: URL
    let name: String
    let totalSize: Int64
    let fileCount: Int

    var id: String {
        url.path
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

struct DuplicateFileGroup: Identifiable, Equatable {
    let displayName: String
    let files: [FileItem]

    var id: String {
        "\(displayName.lowercased())-\(files.first?.size ?? 0)"
    }

    var fileSize: Int64 {
        files.first?.size ?? 0
    }

    var totalSize: Int64 {
        files.map(\.size).reduce(0, +)
    }

    var recoverableSize: Int64 {
        max(totalSize - fileSize, 0)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedRecoverableSize: String {
        ByteCountFormatter.string(fromByteCount: recoverableSize, countStyle: .file)
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
    let largestFolders: [FolderHotspot]
    let duplicateGroups: [DuplicateFileGroup]

    init(
        folderURL: URL,
        totalCount: Int,
        folderCount: Int,
        imageCount: Int,
        csvCount: Int,
        jsonCount: Int,
        textCount: Int,
        logCount: Int,
        pdfCount: Int,
        archiveCount: Int,
        videoCount: Int,
        codeCount: Int,
        otherCount: Int,
        totalSize: Int64,
        largestFiles: [FileItem],
        recentFiles: [FileItem],
        largeFiles: [FileItem],
        oldFiles: [FileItem],
        temporaryFiles: [FileItem],
        isDeepScan: Bool,
        largestFolders: [FolderHotspot] = [],
        duplicateGroups: [DuplicateFileGroup] = []
    ) {
        self.folderURL = folderURL
        self.totalCount = totalCount
        self.folderCount = folderCount
        self.imageCount = imageCount
        self.csvCount = csvCount
        self.jsonCount = jsonCount
        self.textCount = textCount
        self.logCount = logCount
        self.pdfCount = pdfCount
        self.archiveCount = archiveCount
        self.videoCount = videoCount
        self.codeCount = codeCount
        self.otherCount = otherCount
        self.totalSize = totalSize
        self.largestFiles = largestFiles
        self.recentFiles = recentFiles
        self.largeFiles = largeFiles
        self.oldFiles = oldFiles
        self.temporaryFiles = temporaryFiles
        self.isDeepScan = isDeepScan
        self.largestFolders = largestFolders
        self.duplicateGroups = duplicateGroups
    }

    var folderName: String {
        folderURL.lastPathComponent
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var cleanupCandidateCount: Int {
        largeFiles.count + oldFiles.count + temporaryFiles.count
    }

    var reviewableSize: Int64 {
        var seenPaths: Set<String> = []
        var total: Int64 = 0

        for file in largeFiles + oldFiles + temporaryFiles {
            if seenPaths.insert(file.url.path).inserted {
                total += file.size
            }
        }

        return total + duplicateGroups.map(\.recoverableSize).reduce(0, +)
    }

    var recoverableSize: Int64 {
        let temporarySize = temporaryFiles.map(\.size).reduce(0, +)
        let duplicateSize = duplicateGroups.map(\.recoverableSize).reduce(0, +)
        return temporarySize + duplicateSize
    }

    var formattedReviewableSize: String {
        ByteCountFormatter.string(fromByteCount: reviewableSize, countStyle: .file)
    }

    var formattedRecoverableSize: String {
        ByteCountFormatter.string(fromByteCount: recoverableSize, countStyle: .file)
    }

    var healthScore: Int {
        let largeFilePenalty = min(largeFiles.count * 12, 28)
        let oldFilePenalty = min(oldFiles.count * 10, 24)
        let temporaryFilePenalty = min(temporaryFiles.count * 8, 20)
        let duplicatePenalty = min(duplicateGroups.count * 8, 16)
        let unknownTypePenalty = min(Int((Double(otherCount) / Double(max(totalCount, 1)) * 16).rounded()), 16)
        let shallowScanPenalty = isDeepScan ? 0 : 4

        return max(0, 100 - largeFilePenalty - oldFilePenalty - temporaryFilePenalty - duplicatePenalty - unknownTypePenalty - shallowScanPenalty)
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

        if !duplicateGroups.isEmpty {
            actions.append(
                FolderActionItem(
                    title: "Inspect \(duplicateGroups.count) potential duplicate \(duplicateGroups.count == 1 ? "group" : "groups")",
                    detail: "Files with the same name and size may be redundant copies.",
                    systemImage: "doc.on.doc"
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
