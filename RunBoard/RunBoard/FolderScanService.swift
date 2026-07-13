import Foundation

struct FolderScanService: FolderScanning {
    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        try await Task.detached(priority: .userInitiated) {
            try await scanSynchronously(context: context, onProgress: onProgress)
        }.value
    }

    private func scanSynchronously(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        let manager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = context.settings.includeHiddenFiles
            ? []
            : [.skipsHiddenFiles]
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        var warnings: [FolderScanWarning] = []

        let directURLs: [URL]
        do {
            directURLs = try manager.contentsOfDirectory(
                at: context.folderURL,
                includingPropertiesForKeys: Array(keys),
                options: options
            )
        } catch {
            throw FolderScanError.rootUnavailable(
                path: context.folderURL.path,
                reason: error.localizedDescription
            )
        }

        let directChildren = directURLs.compactMap { url -> FileItem? in
            do {
                return try makeFileItem(from: url, keys: keys)
            } catch {
                warnings.append(.init(path: url.path, message: error.localizedDescription))
                return nil
            }
        }
        .sorted(by: fileSort)

        guard context.isDeepScan else {
            try Task.checkCancellation()
            await onProgress(.init(processedItemCount: directChildren.count))
            return FolderScanResult(
                directChildren: directChildren,
                analysisItems: directChildren,
                warnings: warnings
            )
        }

        var deepOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !context.settings.includeHiddenFiles {
            deepOptions.insert(.skipsHiddenFiles)
        }

        guard let enumerator = manager.enumerator(
            at: context.folderURL,
            includingPropertiesForKeys: Array(keys),
            options: deepOptions,
            errorHandler: { url, error in
                warnings.append(.init(path: url.path, message: error.localizedDescription))
                return true
            }
        ) else {
            throw FolderScanError.rootUnavailable(
                path: context.folderURL.path,
                reason: "Directory enumeration is unavailable."
            )
        }

        var analysisItems: [FileItem] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                analysisItems.append(makeFileItem(url: url, values: values))
            } catch {
                warnings.append(.init(path: url.path, message: error.localizedDescription))
            }

            if analysisItems.count.isMultiple(of: 100) {
                await onProgress(.init(processedItemCount: analysisItems.count))
            }
        }

        try Task.checkCancellation()
        await onProgress(.init(processedItemCount: analysisItems.count))
        return FolderScanResult(
            directChildren: directChildren,
            analysisItems: analysisItems,
            warnings: warnings
        )
    }

    private func makeFileItem(from url: URL, keys: Set<URLResourceKey>) throws -> FileItem {
        let values = try url.resourceValues(forKeys: keys)
        return makeFileItem(url: url, values: values)
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
