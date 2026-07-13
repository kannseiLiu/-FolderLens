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

    @Test func analyzerFindsPotentialDuplicateFilesByNameAndSize() async throws {
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

        #expect(summary.duplicateGroups.count == 1)
        #expect(summary.duplicateGroups[0].displayName == "photo.png")
        #expect(summary.duplicateGroups[0].files.count == 2)
        #expect(summary.duplicateGroups[0].recoverableSize == 5 * 1024 * 1024)
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

    @Test func summaryEstimatesReviewableAndRecoverableSpace() async throws {
        let duplicateA = file("/tmp/Workspace/A/data.csv", size: 10 * 1024 * 1024)
        let duplicateB = file("/tmp/Workspace/B/data.csv", size: 10 * 1024 * 1024)
        let cacheFile = file("/tmp/Workspace/build.cache", size: 3 * 1024 * 1024)
        let largeFile = file("/tmp/Workspace/video.mov", size: 180 * 1024 * 1024)

        let summary = FolderSummary(
            folderURL: URL(fileURLWithPath: "/tmp/Workspace"),
            totalCount: 4,
            folderCount: 0,
            imageCount: 0,
            csvCount: 2,
            jsonCount: 0,
            textCount: 0,
            logCount: 0,
            pdfCount: 0,
            archiveCount: 0,
            videoCount: 1,
            codeCount: 0,
            otherCount: 1,
            totalSize: 203 * 1024 * 1024,
            largestFiles: [largeFile],
            recentFiles: [],
            largeFiles: [largeFile],
            oldFiles: [],
            temporaryFiles: [cacheFile],
            isDeepScan: true,
            duplicateGroups: [
                DuplicateFileGroup(displayName: "data.csv", files: [duplicateA, duplicateB])
            ]
        )

        #expect(summary.reviewableSize == 193 * 1024 * 1024)
        #expect(summary.recoverableSize == 13 * 1024 * 1024)
        #expect(summary.actionPlan.map(\.title).contains("Inspect 1 potential duplicate group"))
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
