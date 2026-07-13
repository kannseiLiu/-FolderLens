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

}
