import Foundation

struct FolderAnalyzer {
    static func makeSummary(
        for folderURL: URL,
        files: [FileItem],
        isDeepScan: Bool,
        settings: ScanSettings = .default,
        duplicateVerification: DuplicateVerificationResult = .empty
    ) -> FolderSummary {
        let folderCount = files.filter { $0.isDirectory }.count
        let imageCount = files.filter { $0.isImage }.count
        let csvCount = files.filter { $0.fileExtension == "csv" }.count
        let jsonCount = files.filter { $0.fileExtension == "json" }.count
        let textCount = files.filter { ["txt", "md"].contains($0.fileExtension) }.count
        let logCount = files.filter { $0.fileExtension == "log" }.count
        let pdfCount = files.filter { $0.fileExtension == "pdf" }.count

        let archiveCount = files.filter {
            ["zip", "tar", "gz", "rar", "7z"].contains($0.fileExtension)
        }.count

        let videoCount = files.filter {
            ["mp4", "mov", "avi", "mkv"].contains($0.fileExtension)
        }.count

        let codeCount = files.filter {
            ["swift", "py", "js", "ts", "html", "css", "java", "cpp", "c", "h", "rs", "go", "sh"].contains($0.fileExtension)
        }.count

        let knownCount = folderCount
            + imageCount
            + csvCount
            + jsonCount
            + textCount
            + logCount
            + pdfCount
            + archiveCount
            + videoCount
            + codeCount

        let otherCount = max(files.count - knownCount, 0)

        let totalSize = files
            .filter { !$0.isDirectory }
            .map(\.size)
            .reduce(0, +)

        let largestFiles = files
            .filter { !$0.isDirectory }
            .sorted { $0.size > $1.size }
            .prefix(10)
            .map { $0 }

        let recentFiles = files
            .filter { !$0.isDirectory && $0.modifiedDate != nil }
            .sorted {
                ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast)
            }
            .prefix(10)
            .map { $0 }

        let largeFiles = files
            .filter { !$0.isDirectory && $0.size >= settings.largeFileThresholdBytes }
            .sorted { $0.size > $1.size }
            .prefix(10)
            .map { $0 }

        let oldFiles = files
            .filter { file in
                guard !file.isDirectory, let modifiedDate = file.modifiedDate else {
                    return false
                }

                return modifiedDate < settings.oldFileCutoffDate
            }
            .sorted {
                ($0.modifiedDate ?? .distantPast) < ($1.modifiedDate ?? .distantPast)
            }
            .prefix(10)
            .map { $0 }

        let temporaryFiles = files
            .filter { !$0.isDirectory && isTemporaryCandidate($0) }
            .prefix(10)
            .map { $0 }

        return FolderSummary(
            folderURL: folderURL,
            totalCount: files.count,
            folderCount: folderCount,
            imageCount: imageCount,
            csvCount: csvCount,
            jsonCount: jsonCount,
            textCount: textCount,
            logCount: logCount,
            pdfCount: pdfCount,
            archiveCount: archiveCount,
            videoCount: videoCount,
            codeCount: codeCount,
            otherCount: otherCount,
            totalSize: totalSize,
            largestFiles: largestFiles,
            recentFiles: recentFiles,
            largeFiles: largeFiles,
            oldFiles: oldFiles,
            temporaryFiles: temporaryFiles,
            isDeepScan: isDeepScan,
            largestFolders: makeLargestFolders(root: folderURL, files: files),
            duplicateGroups: duplicateVerification.groups,
            verificationIssues: duplicateVerification.issues,
            settings: settings
        )
    }

    private static func makeLargestFolders(root: URL, files: [FileItem]) -> [FolderHotspot] {
        let rootPath = root.standardizedFileURL.path
        var sizesByPath: [String: Int64] = [:]
        var countsByPath: [String: Int] = [:]
        var urlsByPath: [String: URL] = [:]

        for file in files where !file.isDirectory && file.size > 0 {
            var folderURL = file.url.deletingLastPathComponent().standardizedFileURL

            while folderURL.path != rootPath && folderURL.path.hasPrefix(rootPath) {
                let path = folderURL.path
                sizesByPath[path, default: 0] += file.size
                countsByPath[path, default: 0] += 1
                urlsByPath[path] = folderURL
                folderURL.deleteLastPathComponent()
            }
        }

        return sizesByPath.map { path, totalSize in
            let url = urlsByPath[path] ?? URL(fileURLWithPath: path)
            return FolderHotspot(
                url: url,
                name: url.lastPathComponent,
                totalSize: totalSize,
                fileCount: countsByPath[path, default: 0]
            )
        }
        .sorted {
            if $0.totalSize == $1.totalSize {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return $0.totalSize > $1.totalSize
        }
        .prefix(8)
        .map { $0 }
    }

    private static func isTemporaryCandidate(_ file: FileItem) -> Bool {
        let name = file.name.lowercased()
        let ext = file.fileExtension

        let temporaryExtensions = [
            "tmp", "temp", "cache", "bak", "old", "swp", "part", "download"
        ]

        let temporaryNames = [
            ".ds_store",
            "thumbs.db",
            "desktop.ini"
        ]

        if temporaryExtensions.contains(ext) {
            return true
        }

        if temporaryNames.contains(name) {
            return true
        }

        if name.contains("cache") || name.contains("backup") || name.contains("temp") {
            return true
        }

        return false
    }
}
