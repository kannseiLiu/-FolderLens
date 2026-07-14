//
//  RunBoardTests.swift
//  RunBoardTests
//
//  Created by sheng on 2026/06/18.
//

import Testing
import Foundation
@testable import RunBoard

struct RunBoardTests {

    @Test @MainActor func verificationStatusRemainsCancellableAndDisablesReportExport() async throws {
        #expect(ScanStatusView.isCancellable(.verifyingDuplicates))
        #expect(ContentView.isScanInProgress(.verifyingDuplicates))
        #expect(!ContentView.isScanInProgress(.completed))
    }

    @Test func healthyFolderGetsHighScoreAndLowRisk() async throws {
        let summary = FolderSummary(
            folderURL: URL(fileURLWithPath: "/tmp/Project"),
            totalCount: 8,
            folderCount: 2,
            imageCount: 2,
            csvCount: 0,
            jsonCount: 0,
            textCount: 1,
            logCount: 0,
            pdfCount: 1,
            archiveCount: 0,
            videoCount: 0,
            codeCount: 2,
            otherCount: 0,
            totalSize: 12_000_000,
            largestFiles: [],
            recentFiles: [],
            largeFiles: [],
            oldFiles: [],
            temporaryFiles: [],
            isDeepScan: true
        )

        #expect(summary.healthScore == 100)
        #expect(summary.healthLevel == .excellent)
        #expect(summary.actionPlan.first?.title == "Folder looks healthy")
    }

    @Test func cleanupCandidatesLowerScoreAndCreatePrioritizedActions() async throws {
        let largeFile = FileItem(
            url: URL(fileURLWithPath: "/tmp/video.mov"),
            name: "video.mov",
            isDirectory: false,
            size: 650 * 1024 * 1024,
            modifiedDate: Date()
        )

        let oldFile = FileItem(
            url: URL(fileURLWithPath: "/tmp/archive.zip"),
            name: "archive.zip",
            isDirectory: false,
            size: 80 * 1024 * 1024,
            modifiedDate: Calendar.current.date(byAdding: .year, value: -2, to: Date())
        )

        let cacheFile = FileItem(
            url: URL(fileURLWithPath: "/tmp/build.cache"),
            name: "build.cache",
            isDirectory: false,
            size: 12 * 1024 * 1024,
            modifiedDate: Date()
        )

        let summary = FolderSummary(
            folderURL: URL(fileURLWithPath: "/tmp/Messy"),
            totalCount: 30,
            folderCount: 4,
            imageCount: 1,
            csvCount: 0,
            jsonCount: 0,
            textCount: 1,
            logCount: 0,
            pdfCount: 0,
            archiveCount: 1,
            videoCount: 1,
            codeCount: 2,
            otherCount: 20,
            totalSize: 900 * 1024 * 1024,
            largestFiles: [largeFile, oldFile, cacheFile],
            recentFiles: [],
            largeFiles: [largeFile],
            oldFiles: [oldFile],
            temporaryFiles: [cacheFile],
            isDeepScan: true
        )

        #expect(summary.healthScore == 59)
        #expect(summary.healthLevel == .needsReview)
        #expect(summary.healthSummary == "Needs review")
        #expect(summary.actionPlan.map(\.title) == [
            "Review 1 large file",
            "Archive or remove 1 old file",
            "Check 1 temporary file",
            "Review 20 uncategorized items"
        ])
    }

    @Test func analyzerRanksLargestFoldersFromDeepScanFiles() async throws {
        let root = URL(fileURLWithPath: "/tmp/Workspace")
        let files = [
            folder("/tmp/Workspace/Design"),
            folder("/tmp/Workspace/Design/Exports"),
            folder("/tmp/Workspace/Code"),
            file("/tmp/Workspace/Design/Exports/movie.mov", size: 300 * 1024 * 1024),
            file("/tmp/Workspace/Design/mockup.png", size: 40 * 1024 * 1024),
            file("/tmp/Workspace/Code/main.swift", size: 2 * 1024 * 1024)
        ]

        let summary = FolderAnalyzer.makeSummary(for: root, files: files, isDeepScan: true)

        #expect(summary.largestFolders.map(\.name) == ["Design", "Exports", "Code"])
        #expect(summary.largestFolders[0].totalSize == 340 * 1024 * 1024)
        #expect(summary.largestFolders[0].fileCount == 2)
        #expect(summary.largestFolders[1].totalSize == 300 * 1024 * 1024)
    }

    @Test func analyzerNeverInfersDuplicatesWithoutVerification() async throws {
        let root = URL(fileURLWithPath: "/tmp/Workspace")
        let files = [
            folder("/tmp/Workspace/A"),
            folder("/tmp/Workspace/B"),
            file("/tmp/Workspace/A/photo.png", size: 5 * 1024 * 1024),
            file("/tmp/Workspace/B/photo.png", size: 5 * 1024 * 1024),
            file("/tmp/Workspace/B/photo.png", size: 7 * 1024 * 1024),
            file("/tmp/Workspace/B/notes.md", size: 4_096)
        ]

        let summary = FolderAnalyzer.makeSummary(for: root, files: files, isDeepScan: true)

        #expect(summary.duplicateGroups.isEmpty)
        #expect(summary.recoverableSize == 0)
    }

    @Test func analyzerUsesVerifiedGroupsWithDifferentNames() async throws {
        let root = URL(fileURLWithPath: "/tmp/Workspace")
        let first = file("/tmp/Workspace/A/photo.png", size: 5 * 1024 * 1024)
        let second = file("/tmp/Workspace/B/renamed.png", size: 5 * 1024 * 1024)
        let verification = DuplicateVerificationResult(
            groups: [.init(digest: String(repeating: "a", count: 64), files: [first, second])],
            issues: []
        )

        let summary = FolderAnalyzer.makeSummary(
            for: root,
            files: [first, second],
            isDeepScan: true,
            duplicateVerification: verification
        )

        #expect(summary.duplicateGroups.map(\.digest) == [String(repeating: "a", count: 64)])
        #expect(summary.recoverableSize == 5 * 1024 * 1024)
        #expect(summary.actionPlan.contains {
            $0.title == "Inspect 1 verified duplicate group"
                && $0.detail == "The contents matched by SHA-256."
        })
    }

    @Test func analyzerNormalizesDuplicateGroupMembersAndRejectsInvalidGroups() async throws {
        let root = URL(fileURLWithPath: "/tmp/Workspace")
        let first = file("/tmp/Workspace/A/data.bin", size: 10 * 1024 * 1024)
        let duplicatePath = file("/tmp/Workspace/A/./data.bin", size: 10 * 1024 * 1024)
        let second = file("/tmp/Workspace/B/copy.bin", size: 10 * 1024 * 1024)
        let zeroA = file("/tmp/Workspace/zero-a.bin", size: 0)
        let zeroB = file("/tmp/Workspace/zero-b.bin", size: 0)
        let single = file("/tmp/Workspace/single.bin", size: 10 * 1024 * 1024)
        let mismatched = file("/tmp/Workspace/mismatched.bin", size: 20 * 1024 * 1024)

        let baseline = FolderAnalyzer.makeSummary(
            for: root,
            files: [first, second, zeroA, zeroB, single, mismatched],
            isDeepScan: true
        )
        let summary = FolderAnalyzer.makeSummary(
            for: root,
            files: [first, second, zeroA, zeroB, single, mismatched],
            isDeepScan: true,
            duplicateVerification: .init(
                groups: [
                    .init(digest: String(repeating: "d", count: 64), files: [first, duplicatePath, second]),
                    .init(digest: String(repeating: "e", count: 64), files: [zeroA, zeroB]),
                    .init(digest: String(repeating: "f", count: 64), files: [single]),
                    .init(digest: String(repeating: "g", count: 64), files: [first, mismatched])
                ],
                issues: []
            )
        )

        #expect(summary.duplicateGroups.map(\.digest) == [String(repeating: "d", count: 64)])
        #expect(summary.duplicateGroups[0].files.map { $0.url.standardizedFileURL.path } == [
            first.url.standardizedFileURL.path,
            second.url.standardizedFileURL.path
        ])
        #expect(summary.healthScore == baseline.healthScore - 8)
        #expect(summary.actionPlan.contains { $0.title == "Inspect 1 verified duplicate group" })
        #expect(summary.reviewableSize == 20 * 1024 * 1024)
        #expect(summary.recoverableSize == 10 * 1024 * 1024)
    }

    @Test func analyzerClaimsDuplicatePathsAcrossGroupsInStableOrder() async throws {
        let root = URL(fileURLWithPath: "/tmp/Workspace")
        let shared = file("/tmp/Workspace/shared.bin", size: 10 * 1024 * 1024)
        let sharedAlternatePath = file("/tmp/Workspace/./shared.bin", size: 10 * 1024 * 1024)
        let firstOnly = file("/tmp/Workspace/first-only.bin", size: 10 * 1024 * 1024)
        let secondOnly = file("/tmp/Workspace/second-only.bin", size: 10 * 1024 * 1024)
        let laterA = file("/tmp/Workspace/later-a.bin", size: 5 * 1024 * 1024)
        let laterB = file("/tmp/Workspace/later-b.bin", size: 5 * 1024 * 1024)

        let baseline = FolderAnalyzer.makeSummary(
            for: root,
            files: [shared, firstOnly, secondOnly, laterA, laterB],
            isDeepScan: true
        )
        let summary = FolderAnalyzer.makeSummary(
            for: root,
            files: [shared, firstOnly, secondOnly, laterA, laterB],
            isDeepScan: true,
            duplicateVerification: .init(
                groups: [
                    .init(digest: String(repeating: "h", count: 64), files: [shared, firstOnly]),
                    .init(digest: String(repeating: "i", count: 64), files: [sharedAlternatePath, secondOnly]),
                    .init(digest: String(repeating: "j", count: 64), files: [laterA, laterB])
                ],
                issues: []
            )
        )

        #expect(summary.duplicateGroups.map(\.digest) == [
            String(repeating: "h", count: 64),
            String(repeating: "j", count: 64)
        ])
        #expect(summary.duplicateGroups[0].files.map { $0.url.standardizedFileURL.path } == [
            shared.url.standardizedFileURL.path,
            firstOnly.url.standardizedFileURL.path
        ])
        #expect(summary.healthScore == baseline.healthScore - 16)
        #expect(summary.actionPlan.contains { $0.title == "Inspect 2 verified duplicate groups" })
        #expect(summary.reviewableSize == 30 * 1024 * 1024)
        #expect(summary.recoverableSize == 15 * 1024 * 1024)
        #expect(summary.recoverableSize <= summary.reviewableSize)
    }

    @Test func summaryMergesOverlappingGroupsWithSameDigest() async throws {
        let first = file("/tmp/Workspace/A.bin", size: 10 * 1024 * 1024)
        let duplicateFirst = file("/tmp/Workspace/./A.bin", size: 10 * 1024 * 1024)
        let second = file("/tmp/Workspace/B.bin", size: 10 * 1024 * 1024)
        let third = file("/tmp/Workspace/C.bin", size: 10 * 1024 * 1024)
        let digest = String(repeating: "k", count: 64)

        let summary = makeSummary(
            totalCount: 4,
            totalSize: 30 * 1024 * 1024,
            duplicateGroups: [
                .init(digest: digest, files: [first, second]),
                .init(digest: digest, files: [duplicateFirst, third])
            ]
        )

        #expect(summary.duplicateGroups.map(\.digest) == [digest])
        #expect(summary.duplicateGroups[0].files.map { $0.url.standardizedFileURL.path } == [
            first.url.standardizedFileURL.path,
            second.url.standardizedFileURL.path,
            third.url.standardizedFileURL.path
        ])
        #expect(summary.reviewableSize == 30 * 1024 * 1024)
        #expect(summary.recoverableSize == 20 * 1024 * 1024)
    }

    @Test func summaryNormalizesDirectDuplicateGroupInput() async throws {
        let first = file("/tmp/Workspace/A.bin", size: 10 * 1024 * 1024)
        let second = file("/tmp/Workspace/B.bin", size: 10 * 1024 * 1024)
        let third = file("/tmp/Workspace/C.bin", size: 10 * 1024 * 1024)
        let fourth = file("/tmp/Workspace/D.bin", size: 10 * 1024 * 1024)
        let crossDigestDuplicate = file("/tmp/Workspace/./A.bin", size: 10 * 1024 * 1024)
        let crossDigestOnly = file("/tmp/Workspace/X.bin", size: 10 * 1024 * 1024)
        let validOtherA = file("/tmp/Workspace/E.bin", size: 5 * 1024 * 1024)
        let validOtherB = file("/tmp/Workspace/F.bin", size: 5 * 1024 * 1024)
        let zero = file("/tmp/Workspace/zero.bin", size: 0)
        let single = file("/tmp/Workspace/single.bin", size: 10 * 1024 * 1024)
        let mismatched = file("/tmp/Workspace/mismatched.bin", size: 20 * 1024 * 1024)
        let firstDigest = String(repeating: "l", count: 64)
        let secondDigest = String(repeating: "m", count: 64)

        let summary = makeSummary(
            totalCount: 10,
            totalSize: 50 * 1024 * 1024,
            duplicateGroups: [
                .init(digest: firstDigest, files: [first, second]),
                .init(digest: firstDigest, files: [third, fourth]),
                .init(digest: secondDigest, files: [crossDigestDuplicate, crossDigestOnly]),
                .init(digest: String(repeating: "n", count: 64), files: [zero, zero]),
                .init(digest: String(repeating: "o", count: 64), files: [single]),
                .init(digest: String(repeating: "p", count: 64), files: [first, mismatched]),
                .init(digest: String(repeating: "q", count: 64), files: [validOtherA, validOtherB])
            ]
        )

        #expect(summary.duplicateGroups.map(\.digest) == [firstDigest, String(repeating: "q", count: 64)])
        #expect(summary.duplicateGroups[0].files.map { $0.url.standardizedFileURL.path } == [
            first.url.standardizedFileURL.path,
            second.url.standardizedFileURL.path,
            third.url.standardizedFileURL.path,
            fourth.url.standardizedFileURL.path
        ])
        #expect(summary.healthScore == 84)
        #expect(summary.actionPlan.contains { $0.title == "Inspect 2 verified duplicate groups" })
        #expect(summary.reviewableSize == 50 * 1024 * 1024)
        #expect(summary.recoverableSize == 35 * 1024 * 1024)
        #expect(summary.recoverableSize <= summary.reviewableSize)
    }

    @Test func summaryCountsOnlyVerifiedExtraCopiesAsRecoverable() async throws {
        let copies = [
            file("/tmp/Workspace/A/first.bin", size: 10 * 1024 * 1024),
            file("/tmp/Workspace/B/second.bin", size: 10 * 1024 * 1024),
            file("/tmp/Workspace/C/third.bin", size: 10 * 1024 * 1024)
        ]

        let summary = makeSummary(
            totalCount: copies.count,
            totalSize: 30 * 1024 * 1024,
            duplicateGroups: [.init(digest: String(repeating: "b", count: 64), files: copies)]
        )

        #expect(summary.recoverableSize == 20 * 1024 * 1024)
    }

    @Test func verificationIssuesDoNotReduceHealthScore() async throws {
        let root = URL(fileURLWithPath: "/tmp/Workspace")
        let unreadableFile = file("/tmp/Workspace/unreadable.bin", size: 1_024)
        let issue = DuplicateVerificationIssue(url: unreadableFile.url, message: "Unreadable")

        let baseline = FolderAnalyzer.makeSummary(
            for: root,
            files: [unreadableFile],
            isDeepScan: true
        )
        let summaryWithIssue = FolderAnalyzer.makeSummary(
            for: root,
            files: [unreadableFile],
            isDeepScan: true,
            duplicateVerification: .init(groups: [], issues: [issue])
        )

        #expect(summaryWithIssue.verificationIssues == [issue])
        #expect(summaryWithIssue.healthScore == baseline.healthScore)
        #expect(summaryWithIssue.recoverableSize == baseline.recoverableSize)
    }

    @Test func analyzerUsesCustomCleanupThresholds() async throws {
        let root = URL(fileURLWithPath: "/tmp/Workspace")
        let twoYearOldDate = Calendar.current.date(byAdding: .year, value: -2, to: Date())
        let files = [
            file("/tmp/Workspace/export.mov", size: 60 * 1024 * 1024),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/Workspace/notes.md"),
                name: "notes.md",
                isDirectory: false,
                size: 64_000,
                modifiedDate: twoYearOldDate
            )
        ]

        let settings = ScanSettings(
            largeFileThresholdMB: 50,
            oldFileAgeYears: 1,
            includeHiddenFiles: true
        )

        let summary = FolderAnalyzer.makeSummary(
            for: root,
            files: files,
            isDeepScan: true,
            settings: settings
        )

        #expect(summary.largeFiles.map(\.name) == ["export.mov"])
        #expect(summary.oldFiles.map(\.name) == ["notes.md"])
        #expect(summary.settings == settings)
    }

    @Test func summaryUnionsOverlappingCleanupPathsAndCountsDuplicateExtrasPrecisely() async throws {
        let temporaryDuplicate = file("/tmp/Workspace/cache.tmp", size: 10 * 1024 * 1024)
        let alternateTemporaryDuplicate = file("/tmp/Workspace/./cache.tmp", size: 10 * 1024 * 1024)
        let duplicateB = file("/tmp/Workspace/B/data-copy.bin", size: 10 * 1024 * 1024)
        let duplicateC = file("/tmp/Workspace/C/archive.bin", size: 10 * 1024 * 1024)
        let temporaryOnly = file("/tmp/Workspace/build.cache", size: 3 * 1024 * 1024)
        let largeOnly = file("/tmp/Workspace/video.mov", size: 50 * 1024 * 1024)

        let summary = makeSummary(
            totalCount: 5,
            totalSize: 83 * 1024 * 1024,
            largeFiles: [alternateTemporaryDuplicate, largeOnly],
            oldFiles: [duplicateB],
            temporaryFiles: [temporaryDuplicate, temporaryOnly],
            duplicateGroups: [
                .init(
                    digest: String(repeating: "c", count: 64),
                    files: [temporaryDuplicate, duplicateB, duplicateC]
                )
            ]
        )

        #expect(summary.reviewableSize == 83 * 1024 * 1024)
        #expect(summary.recoverableSize == 23 * 1024 * 1024)
    }

    private func makeSummary(
        totalCount: Int,
        totalSize: Int64,
        largeFiles: [FileItem] = [],
        oldFiles: [FileItem] = [],
        temporaryFiles: [FileItem] = [],
        duplicateGroups: [DuplicateFileGroup] = []
    ) -> FolderSummary {
        FolderSummary(
            folderURL: URL(fileURLWithPath: "/tmp/Workspace"),
            totalCount: totalCount,
            folderCount: 0,
            imageCount: 0,
            csvCount: 0,
            jsonCount: 0,
            textCount: 0,
            logCount: 0,
            pdfCount: 0,
            archiveCount: 0,
            videoCount: 0,
            codeCount: 0,
            otherCount: 0,
            totalSize: totalSize,
            largestFiles: largeFiles,
            recentFiles: [],
            largeFiles: largeFiles,
            oldFiles: oldFiles,
            temporaryFiles: temporaryFiles,
            isDeepScan: true,
            duplicateGroups: duplicateGroups
        )
    }

    private func folder(_ path: String) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            isDirectory: true,
            size: 0,
            modifiedDate: Date()
        )
    }

    private func file(_ path: String, size: Int64) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            isDirectory: false,
            size: size,
            modifiedDate: Date()
        )
    }

}
