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
        #expect(markdown.contains("<code>/tmp/Workspace/unreadable&#124;file.bin</code>"))
        #expect(markdown.contains("Permission denied"))
        #expect(markdown.contains("<code>/tmp/Workspace/changed.bin</code>"))
        #expect(markdown.contains("File changed&#x240A;while hashing"))
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

    @Test func reportEncodesPathsAndIssueMessagesWithoutBreakingMarkdownStructure() {
        let rootPath = "/tmp/root&<folder>\\slash`tick|pipe\rcarriage\nline"
        let firstPath = "/tmp/verified-a&<file>\\slash`tick|pipe\rcarriage\nline.bin"
        let secondPath = "/tmp/verified-b&<file>\\slash`tick|pipe\rcarriage\nline.bin"
        let issuePath = "/tmp/issue&<file>\\slash`tick|pipe\rcarriage\nline.bin"
        let issueMessage = "Read & <denied> \\slash `tick |pipe\rcarriage\nline"
        let duplicateFiles = [
            file(firstPath, size: 1_024),
            file(secondPath, size: 1_024)
        ]
        let summary = makeSummary(
            rootURL: URL(fileURLWithPath: rootPath),
            files: duplicateFiles,
            duplicateGroups: [
                DuplicateFileGroup(
                    digest: String(repeating: "b", count: 64),
                    files: duplicateFiles
                )
            ],
            verificationIssues: [
                DuplicateVerificationIssue(
                    url: URL(fileURLWithPath: issuePath),
                    message: issueMessage
                )
            ]
        )

        let markdown = FolderReportBuilder().makeMarkdown(
            summary: summary,
            files: duplicateFiles,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let lines = markdown.components(separatedBy: "\n")

        #expect(lines.contains("Path: <code>/tmp/root&amp;&lt;folder&gt;&#92;slash&#96;tick&#124;pipe&#x240D;carriage&#x240A;line</code>"))
        #expect(markdown.contains("<code>/tmp/verified-a&amp;&lt;file&gt;&#92;slash&#96;tick&#124;pipe&#x240D;carriage&#x240A;line.bin</code>"))
        #expect(markdown.contains("<code>/tmp/verified-b&amp;&lt;file&gt;&#92;slash&#96;tick&#124;pipe&#x240D;carriage&#x240A;line.bin</code>"))
        #expect(lines.contains("| <code>/tmp/issue&amp;&lt;file&gt;&#92;slash&#96;tick&#124;pipe&#x240D;carriage&#x240A;line.bin</code> | Read &amp; &lt;denied&gt; &#92;slash &#96;tick &#124;pipe&#x240D;carriage&#x240A;line |"))
        #expect(!markdown.contains(rootPath))
        #expect(!markdown.contains(firstPath))
        #expect(!markdown.contains(secondPath))
        #expect(!markdown.contains(issuePath))
        #expect(!markdown.contains(issueMessage))
    }

    @Test func reportUsesDeterministicUTCTimestamp() {
        let summary = makeSummary(files: [])

        let markdown = FolderReportBuilder().makeMarkdown(
            summary: summary,
            files: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let generatedAtLine = markdown.components(separatedBy: "\n")
            .first { $0.hasPrefix("Generated at:") }

        #expect(generatedAtLine == "Generated at: 1970-01-01T00:00:00Z")
    }

    @Test func reportOmitsVerificationIssuesSectionWhenThereAreNoIssues() {
        let summary = makeSummary(files: [])

        let markdown = FolderReportBuilder().makeMarkdown(
            summary: summary,
            files: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(!markdown.contains("## Verification Issues"))
        #expect(!markdown.contains("| No verification issues | - |"))
    }

    private func makeSummary(
        rootURL: URL = URL(fileURLWithPath: "/tmp/Workspace"),
        files: [FileItem],
        duplicateGroups: [DuplicateFileGroup] = [],
        verificationIssues: [DuplicateVerificationIssue] = [],
        temporaryFiles: [FileItem] = []
    ) -> FolderSummary {
        FolderSummary(
            folderURL: rootURL,
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
            isSymbolicLink: false,
            size: size,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileSystemIdentity: path
        )
    }
}
