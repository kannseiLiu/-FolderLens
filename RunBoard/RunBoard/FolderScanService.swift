import Foundation

struct FolderScanService: FolderScanning {
    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        let worker = Task.detached(priority: .userInitiated) {
            try await scanSynchronously(context: context, onProgress: onProgress)
        }

        let result = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return result
    }

    private func scanSynchronously(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        var warnings: [FolderScanWarning] = []

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !context.settings.includeHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }
        if !context.isDeepScan {
            options.insert(.skipsSubdirectoryDescendants)
        }

        let rootURL = context.folderURL.standardizedFileURL
        var rootError: Error?
        guard let enumerator = manager.enumerator(
            at: context.folderURL,
            includingPropertiesForKeys: Array(keys),
            options: options,
            errorHandler: { url, error in
                if url.standardizedFileURL == rootURL {
                    rootError = error
                    return false
                }
                warnings.append(.init(path: url.path, message: error.localizedDescription))
                return true
            }
        ) else {
            throw FolderScanError.rootUnavailable(
                path: context.folderURL.path,
                reason: "Directory enumeration is unavailable."
            )
        }

        var directChildren: [FileItem] = []
        var analysisItems: [FileItem] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                let item = makeFileItem(url: url, values: values)
                analysisItems.append(item)
                if url.deletingLastPathComponent().standardizedFileURL == rootURL {
                    directChildren.append(item)
                }
            } catch {
                warnings.append(.init(path: url.path, message: error.localizedDescription))
            }

            if analysisItems.count.isMultiple(of: 100) {
                await onProgress(.init(processedItemCount: analysisItems.count))
            }
        }

        if let rootError {
            throw FolderScanError.rootUnavailable(
                path: context.folderURL.path,
                reason: rootError.localizedDescription
            )
        }
        try Task.checkCancellation()
        let sortedDirectChildren = directChildren.sorted(by: fileSort)
        let resultAnalysisItems = context.isDeepScan ? analysisItems : sortedDirectChildren
        await onProgress(.init(processedItemCount: resultAnalysisItems.count))
        return FolderScanResult(
            directChildren: sortedDirectChildren,
            analysisItems: resultAnalysisItems,
            warnings: warnings
        )
    }

    private func makeFileItem(url: URL, values: URLResourceValues) -> FileItem {
        FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: values.isDirectory ?? false,
            size: Int64(values.fileSize ?? 0),
            modifiedDate: values.contentModificationDate
        )
    }

    private func fileSort(_ first: FileItem, _ second: FileItem) -> Bool {
        if first.isDirectory != second.isDirectory {
            return first.isDirectory && !second.isDirectory
        }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }
}
