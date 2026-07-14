import CryptoKit
import Foundation

struct DuplicateVerifier: DuplicateVerifying {
    typealias ChunkObserver = @Sendable (URL, Int) async -> Void

    private let chunkSize: Int
    private let chunkObserver: ChunkObserver

    init(
        chunkSize: Int = 1_048_576,
        chunkObserver: @escaping ChunkObserver = { _, _ in }
    ) {
        self.chunkSize = chunkSize
        self.chunkObserver = chunkObserver
    }

    func verify(
        files: [FileItem],
        onProgress: @escaping DuplicateVerificationProgressHandler
    ) async throws -> DuplicateVerificationResult {
        let sizeCandidates = Dictionary(
            grouping: files.filter { !$0.isDirectory && !$0.isSymbolicLink && $0.size > 0 },
            by: \.size
        )
        .values
        .filter { $0.count > 1 }
        .flatMap { $0 }

        let candidates = coalescingFileSystemAliases(in: sizeCandidates)
        .sorted { $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path }

        await onProgress(.init(completedFileCount: 0, totalFileCount: candidates.count))
        guard !candidates.isEmpty else {
            return .empty
        }

        var verified: [(file: FileItem, digest: String)] = []
        var issues: [DuplicateVerificationIssue] = []

        for (index, file) in candidates.enumerated() {
            do {
                try Task.checkCancellation()
                verified.append((file, try await hash(file)))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                issues.append(.init(url: file.url, message: error.localizedDescription))
            }

            await onProgress(.init(completedFileCount: index + 1, totalFileCount: candidates.count))
            try Task.checkCancellation()
        }

        let groups = Dictionary(grouping: verified, by: { $0.file.size })
            .values
            .flatMap { sizeGroup in
                Dictionary(grouping: sizeGroup, by: \.digest)
                    .compactMap { digest, digestGroup in
                        guard digestGroup.count > 1 else {
                            return nil
                        }
                        return DuplicateFileGroup(
                            digest: digest,
                            files: digestGroup.map(\.file).sorted(by: fileSort)
                        )
                    }
            }
            .sorted(by: groupSort)

        return DuplicateVerificationResult(
            groups: groups,
            issues: issues.sorted { $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path }
        )
    }

    private func hash(_ file: FileItem) async throws -> String {
        let before = try metadata(for: file.url)
        guard before.size == file.size else {
            throw VerificationError.fileChanged
        }
        if let modifiedDate = file.modifiedDate, before.modifiedDate != modifiedDate {
            throw VerificationError.fileChanged
        }

        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }

        var hasher = SHA256()
        var chunkIndex = 0

        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
            await chunkObserver(file.url, chunkIndex)
            chunkIndex += 1
            try Task.checkCancellation()
        }

        guard try metadata(for: file.url) == before else {
            throw VerificationError.fileChanged
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func coalescingFileSystemAliases(in files: [FileItem]) -> [FileItem] {
        var seenIdentities: Set<String> = []
        var result: [FileItem] = []

        for file in files {
            if let identity = file.fileSystemIdentity {
                guard seenIdentities.insert(identity).inserted else {
                    continue
                }
            }
            result.append(file)
        }

        return result
    }

    private func metadata(for url: URL) throws -> FileMetadata {
        var resourceURL = url
        resourceURL.removeAllCachedResourceValues()
        let values = try resourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize else {
            throw VerificationError.metadataUnavailable
        }
        return FileMetadata(size: Int64(size), modifiedDate: values.contentModificationDate)
    }

    private func fileSort(_ first: FileItem, _ second: FileItem) -> Bool {
        first.url.standardizedFileURL.path < second.url.standardizedFileURL.path
    }

    private func groupSort(_ first: DuplicateFileGroup, _ second: DuplicateFileGroup) -> Bool {
        if first.recoverableSize != second.recoverableSize {
            return first.recoverableSize > second.recoverableSize
        }
        return first.digest < second.digest
    }
}

private struct FileMetadata: Equatable {
    let size: Int64
    let modifiedDate: Date?
}

private enum VerificationError: LocalizedError {
    case fileChanged
    case metadataUnavailable

    var errorDescription: String? {
        switch self {
        case .fileChanged:
            return "File changed during verification."
        case .metadataUnavailable:
            return "File metadata is unavailable."
        }
    }
}
