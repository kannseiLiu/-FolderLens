import CryptoKit
import Darwin
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
        let uniqueRegularFiles = coalescingFileSystemAliases(
            in: files.filter {
                !$0.isDirectory
                    && $0.isRegularFile
                    && !$0.isSymbolicLink
                    && $0.size > 0
                    && $0.fileSystemIdentity != nil
            }
        )

        let candidates = Dictionary(
            grouping: uniqueRegularFiles,
            by: \.size
        )
        .values
        .filter { $0.count > 1 }
        .flatMap { $0 }
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
        guard let expectedIdentity = file.fileSystemIdentity else {
            throw VerificationError.metadataUnavailable
        }
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }

        let before = try metadata(for: handle)
        guard before.matchesScannedFile(file, expectedIdentity: expectedIdentity) else {
            throw VerificationError.fileChanged
        }

        var hasher = SHA256()
        var chunkIndex = 0

        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
            await chunkObserver(file.url, chunkIndex)
            chunkIndex += 1
            try Task.checkCancellation()
        }

        guard try metadata(for: handle) == before else {
            throw VerificationError.fileChanged
        }
        guard try pathMetadata(for: file.url) == before else {
            throw VerificationError.fileChanged
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func coalescingFileSystemAliases(in files: [FileItem]) -> [FileItem] {
        var seenIdentities: Set<FileSystemIdentity> = []
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

    private func metadata(for handle: FileHandle) throws -> FileMetadata {
        var fileStatus = stat()
        guard fstat(handle.fileDescriptor, &fileStatus) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return try FileMetadata(fileStatus: fileStatus)
    }

    private func pathMetadata(for url: URL) throws -> FileMetadata {
        var fileStatus = stat()
        guard lstat(url.path, &fileStatus) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return try FileMetadata(fileStatus: fileStatus)
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
    private static let modificationDateTolerance: TimeInterval = 0.001

    let size: Int64
    let modifiedDate: Date?
    let fileSystemIdentity: FileSystemIdentity

    init(fileStatus: stat) throws {
        guard (fileStatus.st_mode & S_IFMT) == S_IFREG else {
            throw VerificationError.fileChanged
        }
        self.size = Int64(fileStatus.st_size)
        self.modifiedDate = Date(
            timeIntervalSince1970: TimeInterval(fileStatus.st_mtimespec.tv_sec)
                + TimeInterval(fileStatus.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        self.fileSystemIdentity = FileSystemIdentity(fileStatus: fileStatus)
    }

    func matchesScannedFile(_ file: FileItem, expectedIdentity: FileSystemIdentity) -> Bool {
        guard size == file.size, fileSystemIdentity == expectedIdentity else {
            return false
        }
        guard let scannedModifiedDate = file.modifiedDate, let modifiedDate else {
            return true
        }
        return abs(modifiedDate.timeIntervalSince(scannedModifiedDate)) <= Self.modificationDateTolerance
    }
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
