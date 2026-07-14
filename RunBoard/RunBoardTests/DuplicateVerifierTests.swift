import Foundation
import Testing
@testable import RunBoard

struct DuplicateVerifierTests {
    @Test func differentNamesWithIdenticalContentsAreVerified() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try write("same payload", to: root.appendingPathComponent("report.txt"))
        let second = try write("same payload", to: root.appendingPathComponent("copy.bin"))
        let progress = VerificationProgressRecorder()

        let result = try await DuplicateVerifier().verify(
            files: [item(first), item(second)],
            onProgress: { value in
                await progress.append(value)
            }
        )
        let values = await progress.values

        #expect(result.groups.count == 1)
        #expect(result.groups[0].files.map(\.name) == ["copy.bin", "report.txt"])
        #expect(result.groups[0].digest.count == 64)
        #expect(values.first == .init(completedFileCount: 0, totalFileCount: 2))
        #expect(values.map(\.completedFileCount) == values.map(\.completedFileCount).sorted())
        #expect(values.last == .init(completedFileCount: 2, totalFileCount: 2))
    }

    @Test func equalSizesWithDifferentContentsAreNotDuplicates() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try write("abc", to: root.appendingPathComponent("first.txt"))
        let second = try write("xyz", to: root.appendingPathComponent("second.txt"))

        let result = try await DuplicateVerifier().verify(
            files: [item(first), item(second)],
            onProgress: { _ in }
        )

        #expect(result.groups.isEmpty)
        #expect(result.issues.isEmpty)
    }

    @Test func directoriesZeroByteFilesAndUniqueSizesAreNotOpened() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let empty = try write("", to: root.appendingPathComponent("empty.txt"))
        let unique = try write("unique", to: root.appendingPathComponent("unique.txt"))
        let openedURLs = OpenedURLRecorder()
        let progress = VerificationProgressRecorder()

        let result = try await DuplicateVerifier(chunkObserver: { url, _ in
            await openedURLs.append(url)
        }).verify(
            files: [item(directory), item(empty), item(unique)],
            onProgress: { value in
                await progress.append(value)
            }
        )

        #expect(result == .empty)
        #expect(await openedURLs.values.isEmpty)
        #expect(await progress.values == [.init(completedFileCount: 0, totalFileCount: 0)])
    }

    @Test func disappearingCandidateBecomesIssueAndValidGroupStillCompletes() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try write("stable", to: root.appendingPathComponent("stable-one.txt"))
        let second = try write("stable", to: root.appendingPathComponent("stable-two.bin"))
        let missing = try write("missing", to: root.appendingPathComponent("missing-one.txt"))
        let missingPeer = try write("missing", to: root.appendingPathComponent("missing-two.bin"))
        let files = [item(first), item(second), item(missing), item(missingPeer)]
        try FileManager.default.removeItem(at: missing)

        let result = try await DuplicateVerifier().verify(files: files, onProgress: { _ in })

        #expect(result.groups.count == 1)
        #expect(result.groups[0].files.map(\.name) == ["stable-one.txt", "stable-two.bin"])
        #expect(result.issues.map(\.url) == [missing])
    }

    @Test func fileChangedBetweenChunksIsExcludedAndReported() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let changed = try write("same payload", to: root.appendingPathComponent("changed.bin"))
        let stable = try write("same payload", to: root.appendingPathComponent("stable.bin"))
        let gate = ChunkGate()
        let verifier = DuplicateVerifier(chunkSize: 4, chunkObserver: { url, index in
            guard url == changed, index == 0 else {
                return
            }
            await gate.pause()
        })
        let verification = Task {
            try await verifier.verify(files: [item(changed), item(stable)], onProgress: { _ in })
        }

        await gate.waitUntilPaused()
        try Data("changed payload is longer".utf8).write(to: changed)
        await gate.release()
        let result = try await verification.value

        #expect(result.groups.isEmpty)
        #expect(result.issues.map(\.url) == [changed])
    }

    @Test func replacedPathWithSameSizeAndMTimeIsExcludedAndReported() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let stable = try write("same payload", to: root.appendingPathComponent("stable.bin"))
        let replaced = try write("same payload", to: root.appendingPathComponent("z-replaced.bin"))
        let replacementSource = try write("same payload", to: root.appendingPathComponent("replacement-source.bin"))
        let originalModifiedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: replaced.path)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: stable.path)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: replacementSource.path)
        let files = [item(replaced), item(stable)]
        let gate = ChunkGate()
        let verifier = DuplicateVerifier(chunkSize: 4, chunkObserver: { url, index in
            guard url == stable, index == 0 else {
                return
            }
            await gate.pause()
        })
        let verification = Task {
            try await verifier.verify(files: files, onProgress: { _ in })
        }

        await gate.waitUntilPaused()
        try FileManager.default.removeItem(at: replaced)
        try FileManager.default.linkItem(at: replacementSource, to: replaced)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: replaced.path)
        await gate.release()
        let result = try await verification.value

        #expect(result.groups.isEmpty)
        #expect(result.issues.map(\.url) == [replaced])
    }

    @Test func pathReplacedAfterOpeningIsExcludedAndReported() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let changed = try write("same payload", to: root.appendingPathComponent("changed.bin"))
        let stable = try write("same payload", to: root.appendingPathComponent("stable.bin"))
        let replacementSource = try write("same payload", to: root.appendingPathComponent("replacement-source.bin"))
        let originalModifiedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: changed.path)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: stable.path)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: replacementSource.path)
        let files = [item(changed), item(stable)]
        let gate = ChunkGate()
        let verifier = DuplicateVerifier(chunkSize: 4, chunkObserver: { url, index in
            guard url == changed, index == 0 else {
                return
            }
            await gate.pause()
        })
        let verification = Task {
            try await verifier.verify(files: files, onProgress: { _ in })
        }

        await gate.waitUntilPaused()
        try FileManager.default.removeItem(at: changed)
        try FileManager.default.linkItem(at: replacementSource, to: changed)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedDate], ofItemAtPath: changed.path)
        await gate.release()
        let result = try await verification.value

        #expect(result.groups.isEmpty)
        #expect(result.issues.map(\.url) == [changed])
    }

    @Test func cancellationBetweenChunksThrowsCancellationError() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try write("same payload", to: root.appendingPathComponent("first.bin"))
        let second = try write("same payload", to: root.appendingPathComponent("second.bin"))
        let gate = ChunkGate()
        let verifier = DuplicateVerifier(chunkSize: 4, chunkObserver: { url, index in
            guard url == first, index == 0 else {
                return
            }
            await gate.pause()
        })
        let verification = Task {
            try await verifier.verify(files: [item(first), item(second)], onProgress: { _ in })
        }

        await gate.waitUntilPaused()
        verification.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            _ = try await verification.value
        }
    }

    @Test func threeCopiesRecoverTwoFileSizes() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try write("payload", to: root.appendingPathComponent("one.bin"))
        let second = try write("payload", to: root.appendingPathComponent("two.bin"))
        let third = try write("payload", to: root.appendingPathComponent("three.bin"))

        let result = try await DuplicateVerifier().verify(
            files: [item(first), item(second), item(third)],
            onProgress: { _ in }
        )

        #expect(result.groups.count == 1)
        #expect(result.groups[0].recoverableSize == 14)
    }

    @Test func hardLinksToSameFileDoNotCreateRecoverableCopies() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try write("shared payload", to: root.appendingPathComponent("original.bin"))
        let hardLink = root.appendingPathComponent("hard-link.bin")
        try FileManager.default.linkItem(at: original, to: hardLink)
        let independentCopy = try write("shared payload", to: root.appendingPathComponent("copy.bin"))

        let result = try await DuplicateVerifier().verify(
            files: [item(original), item(hardLink), item(independentCopy)],
            onProgress: { _ in }
        )

        #expect(result.groups.count == 1)
        #expect(result.groups[0].files.map(\.name) == ["copy.bin", "original.bin"])
        #expect(result.groups[0].recoverableSize == 14)
    }

    @Test func hardLinkOnlyCandidatesAreNotOpened() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try write("shared payload", to: root.appendingPathComponent("original.bin"))
        let hardLink = root.appendingPathComponent("hard-link.bin")
        try FileManager.default.linkItem(at: original, to: hardLink)
        let openedURLs = OpenedURLRecorder()

        let result = try await DuplicateVerifier(chunkObserver: { url, _ in
            await openedURLs.append(url)
        }).verify(
            files: [item(original), item(hardLink)],
            onProgress: { _ in }
        )

        #expect(result == .empty)
        #expect(await openedURLs.values.isEmpty)
    }

    @Test func filesWithoutStableIdentityAreNotTrustedAsDuplicates() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try write("same payload", to: root.appendingPathComponent("first.bin"))
        let second = try write("same payload", to: root.appendingPathComponent("second.bin"))

        let result = try await DuplicateVerifier().verify(
            files: [
                item(first, fileSystemIdentity: .some(nil)),
                item(second, fileSystemIdentity: .some(nil))
            ],
            onProgress: { _ in }
        )

        #expect(result == .empty)
    }

    @Test func symbolicLinksAreExcludedFromVerificationCandidates() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try write("same payload", to: root.appendingPathComponent("original.bin"))
        let independentCopy = try write("same payload", to: root.appendingPathComponent("copy.bin"))
        let symlink = root.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)

        let result = try await DuplicateVerifier().verify(
            files: [item(original), item(independentCopy), item(symlink)],
            onProgress: { _ in }
        )

        #expect(result.groups.count == 1)
        #expect(result.groups[0].files.map(\.name) == ["copy.bin", "original.bin"])
        #expect(result.groups[0].recoverableSize == 12)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderLensDuplicateVerifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func write(_ contents: String, to url: URL) throws -> URL {
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func item(
        _ url: URL,
        fileSystemIdentity: FileSystemIdentity?? = nil
    ) -> FileItem {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let identity: FileSystemIdentity?
        switch fileSystemIdentity {
        case .some(let override):
            identity = override
        case .none:
            identity = try? FileSystemIdentity(fileURL: url)
        }
        return FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: values?.isDirectory ?? false,
            isRegularFile: values?.isRegularFile,
            isSymbolicLink: values?.isSymbolicLink ?? false,
            size: Int64(values?.fileSize ?? 0),
            modifiedDate: values?.contentModificationDate,
            fileSystemIdentity: identity
        )
    }
}

private actor OpenedURLRecorder {
    private(set) var values: [URL] = []

    func append(_ url: URL) {
        values.append(url)
    }
}

private actor VerificationProgressRecorder {
    private(set) var values: [DuplicateVerificationProgress] = []

    func append(_ value: DuplicateVerificationProgress) {
        values.append(value)
    }
}

private actor ChunkGate {
    private var hasPaused = false
    private var pauseWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        hasPaused = true
        pauseWaiter?.resume()
        pauseWaiter = nil

        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
    }

    func waitUntilPaused() async {
        guard !hasPaused else {
            return
        }

        await withCheckedContinuation { continuation in
            pauseWaiter = continuation
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
