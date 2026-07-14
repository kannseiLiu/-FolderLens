import Foundation
import Testing
@testable import RunBoard

struct FolderReportBuilderTests {
    @Test func reportUsesVerifiedDuplicateTerminologyAndIncludesEveryPath() {
        let duplicateFiles = [
            file("/tmp/Workspace/A/original.bin", size: 1_048_576),
            file("/tmp/Workspace/B/copy.bin", size: 1_048_576),
            file("/tmp/Workspace/C/renamed.bin", size: 1_048_576),
            file("/tmp/Workspace/D/archive.bin", size: 1_048_576)
        ]
        let summary = makeSummary(
            files: duplicateFiles,
            duplicateGroups: [
                DuplicateFileGroup(
                    digest: String(repeating: "a", count: 64),
                    files: duplicateFiles
                )
            ],
            temporaryFiles: [duplicateFiles[0]]
        )

        let markdown = FolderReportBuilder().makeMarkdown(
            summary: summary,
            files: duplicateFiles,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(markdown.contains("## Verified Duplicates"))
        #expect(markdown.contains("SHA-256 verified"))
        #expect(markdown.contains("| Confidence |"))
        #expect(!markdown.contains("Potential Duplicates"))
        for file in duplicateFiles {
            #expect(markdown.contains(file.url.path))
        }
        #expect(markdown.contains("| Recoverable estimate | \(summary.formattedRecoverableSize) |"))
    }

    @Test func reportIncludesEveryVerificationIssueAndPreservesExistingSections() {
        let issues = [
            DuplicateVerificationIssue(
                url: URL(fileURLWithPath: "/tmp/Workspace/unreadable|file.bin"),
                message: "Permission denied"
            ),
            DuplicateVerificationIssue(
                url: URL(fileURLWithPath: "/tmp/Workspace/changed.bin"),
                message: "File changed\nwhile hashing"
            )
        ]
        let summary = makeSummary(files: [], verificationIssues: issues)

        let markdown = FolderReportBuilder().makeMarkdown(
            summary: summary,
            files: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(markdown.contains("## Verification Issues"))
        #expect(markdown.contains("| No verified duplicates found | - | - | - | - | - |"))
        #expect(markdown.contains("/tmp/Workspace/unreadable\\|file.bin"))
        #expect(markdown.contains("Permission denied"))
        #expect(markdown.contains("/tmp/Workspace/changed.bin"))
        #expect(markdown.contains("File changed while hashing"))
        #expect(markdown.contains("## Folder Health"))
        #expect(markdown.contains("## Scan Settings"))
        #expect(markdown.contains("## Action Plan"))
        #expect(markdown.contains("## Overview"))
        #expect(markdown.contains("## Folder Size Hotspots"))
        #expect(markdown.contains("## Cleanup Suggestions"))
        #expect(markdown.contains("## Largest Files"))
        #expect(markdown.contains("## Recently Modified Files"))
        #expect(markdown.contains("## Full File List"))
    }

    private func makeSummary(
        files: [FileItem],
        duplicateGroups: [DuplicateFileGroup] = [],
        verificationIssues: [DuplicateVerificationIssue] = [],
        temporaryFiles: [FileItem] = []
    ) -> FolderSummary {
        FolderSummary(
            folderURL: URL(fileURLWithPath: "/tmp/Workspace"),
            totalCount: files.count,
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
            otherCount: files.count,
            totalSize: files.map(\.size).reduce(0, +),
            largestFiles: files,
            recentFiles: files,
            largeFiles: [],
            oldFiles: [],
            temporaryFiles: temporaryFiles,
            isDeepScan: true,
            duplicateGroups: duplicateGroups,
            verificationIssues: verificationIssues
        )
    }

    private func file(_ path: String, size: Int64) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            isDirectory: false,
            size: size,
            modifiedDate: Date(timeIntervalSince1970: 0)
        )
    }
}
