import Foundation

struct DuplicateVerificationProgress: Equatable, Sendable {
    let completedFileCount: Int
    let totalFileCount: Int
}

struct DuplicateVerificationIssue: Identifiable, Equatable, Sendable {
    let url: URL
    let message: String

    var id: String {
        "\(url.standardizedFileURL.path)|\(message)"
    }
}

struct DuplicateFileGroup: Identifiable, Equatable, Sendable {
    let digest: String
    let files: [FileItem]

    init(digest: String, files: [FileItem]) {
        self.digest = digest
        self.files = files
    }

    var id: String {
        digest
    }

    var displayName: String {
        files.first?.name ?? "Identical files"
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

struct DuplicateVerificationResult: Equatable, Sendable {
    let groups: [DuplicateFileGroup]
    let issues: [DuplicateVerificationIssue]

    static let empty = DuplicateVerificationResult(groups: [], issues: [])
}

typealias DuplicateVerificationProgressHandler =
    @Sendable (DuplicateVerificationProgress) async -> Void

protocol DuplicateVerifying: Sendable {
    func verify(
        files: [FileItem],
        onProgress: @escaping DuplicateVerificationProgressHandler
    ) async throws -> DuplicateVerificationResult
}
