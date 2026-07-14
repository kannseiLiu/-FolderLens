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
