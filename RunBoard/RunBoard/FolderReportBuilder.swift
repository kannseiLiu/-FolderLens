import Foundation

struct FolderReportBuilder {
    func makeMarkdown(
        summary: FolderSummary,
        files: [FileItem],
        generatedAt: Date = Date()
    ) -> String {
        let sortedFiles = files.sorted { first, second in
            if first.isDirectory != second.isDirectory {
                return first.isDirectory && !second.isDirectory
            }
            return first.name.lowercased() < second.name.lowercased()
        }

        let largestRows = summary.largestFiles.map { file in
            "| \(escapeMarkdownTableText(file.name)) | \(escapeMarkdownTableText(file.formattedSize)) | \(escapeMarkdownTableText(file.formattedModifiedDate)) |"
        }
        .joined(separator: "\n")

        let recentRows = summary.recentFiles.map { file in
            "| \(escapeMarkdownTableText(file.name)) | \(escapeMarkdownTableText(file.formattedModifiedDate)) | \(escapeMarkdownTableText(file.formattedSize)) |"
        }
        .joined(separator: "\n")

        let largeCleanupRows = summary.largeFiles.map { file in
            "| \(escapeMarkdownTableText(file.name)) | \(escapeMarkdownTableText(file.formattedSize)) | \(escapeMarkdownTableText(file.formattedModifiedDate)) |"
        }
        .joined(separator: "\n")

        let oldCleanupRows = summary.oldFiles.map { file in
            "| \(escapeMarkdownTableText(file.name)) | \(escapeMarkdownTableText(file.formattedModifiedDate)) | \(escapeMarkdownTableText(file.formattedSize)) |"
        }
        .joined(separator: "\n")

        let temporaryCleanupRows = summary.temporaryFiles.map { file in
            "| \(escapeMarkdownTableText(file.name)) | \(escapeMarkdownTableText(file.formattedSize)) | \(escapeMarkdownTableText(file.formattedModifiedDate)) |"
        }
        .joined(separator: "\n")

        let actionPlanRows = summary.actionPlan.map { action in
            "| \(escapeMarkdownTableText(action.title)) | \(escapeMarkdownTableText(action.detail)) |"
        }
        .joined(separator: "\n")

        let folderHotspotRows = summary.largestFolders.map { folder in
            "| \(escapeMarkdownTableText(folder.name)) | \(escapeMarkdownTableText(folder.formattedSize)) | \(folder.fileCount) | \(formatPathCode(folder.url.path)) |"
        }
        .joined(separator: "\n")

        let duplicateRows = summary.duplicateGroups.map { group in
            let paths = group.files
                .map { formatPathCode($0.url.path) }
                .joined(separator: "<br>")

            return "| \(escapeMarkdownTableText(group.displayName)) | \(group.files.count) | \(escapeMarkdownTableText(group.formattedFileSize)) | \(escapeMarkdownTableText(group.formattedRecoverableSize)) | SHA-256 verified | \(paths) |"
        }
        .joined(separator: "\n")

        let verificationIssueRows = summary.verificationIssues.map { issue in
            "| \(formatPathCode(issue.url.path)) | \(escapeMarkdownTableText(issue.message)) |"
        }
        .joined(separator: "\n")

        let allFileRows = sortedFiles.map { file in
            let sizeText = file.isDirectory ? "-" : file.formattedSize
            return "| \(escapeMarkdownTableText(file.name)) | \(escapeMarkdownTableText(file.typeDescription)) | \(escapeMarkdownTableText(sizeText)) | \(escapeMarkdownTableText(file.formattedModifiedDate)) |"
        }
        .joined(separator: "\n")

        return """
        # FolderLens Report

        Generated at: \(formattedDate(generatedAt))

        Path: \(formatPathCode(summary.folderURL.path))

        Scan mode: \(summary.isDeepScan ? "Deep Scan" : "Current folder only")

        ## Folder Health

        | Metric | Value |
        |---|---:|
        | Health score | \(summary.healthScore) / 100 |
        | Status | \(summary.healthSummary) |
        | Cleanup candidates | \(summary.cleanupCandidateCount) |
        | Review size | \(summary.formattedReviewableSize) |
        | Recoverable estimate | \(summary.formattedRecoverableSize) |

        ## Scan Settings

        | Setting | Value |
        |---|---:|
        | Large file threshold | \(summary.settings.largeFileThresholdMB) MB |
        | Old file threshold | \(summary.settings.oldFileAgeYears) \(summary.settings.oldFileAgeYears == 1 ? "year" : "years") |
        | Hidden files | \(summary.settings.includeHiddenFiles ? "Included" : "Skipped") |

        ## Action Plan

        | Step | Why it matters |
        |---|---|
        \(actionPlanRows)

        ## Overview

        | Metric | Value |
        |---|---:|
        | Total size | \(summary.formattedTotalSize) |
        | Total items | \(summary.totalCount) |
        | Folders | \(summary.folderCount) |
        | Images | \(summary.imageCount) |
        | PDFs | \(summary.pdfCount) |
        | CSV files | \(summary.csvCount) |
        | JSON files | \(summary.jsonCount) |
        | Text / Markdown files | \(summary.textCount) |
        | Log files | \(summary.logCount) |
        | Code files | \(summary.codeCount) |
        | Videos | \(summary.videoCount) |
        | Archives | \(summary.archiveCount) |
        | Other files | \(summary.otherCount) |

        ## Folder Size Hotspots

        | Folder | Size | Files | Path |
        |---|---:|---:|---|
        \(folderHotspotRows.isEmpty ? "| No folder hotspots found | - | - | - |" : folderHotspotRows)

        ## Verified Duplicates

        | Name | Copies | Size each | Recoverable | Confidence | Paths |
        |---|---:|---:|---:|---|---|
        \(duplicateRows.isEmpty ? "| No verified duplicates found | - | - | - | - | - |" : duplicateRows)

        ## Verification Issues

        | Path | Reason |
        |---|---|
        \(verificationIssueRows.isEmpty ? "| No verification issues | - |" : verificationIssueRows)

        ## Cleanup Suggestions

        FolderLens only provides safe suggestions and never deletes files automatically.

        ### Large files over \(summary.settings.largeFileThresholdMB) MB

        | Name | Size | Modified |
        |---|---:|---|
        \(largeCleanupRows.isEmpty ? "| No candidates | - | - |" : largeCleanupRows)

        ### Old files not modified for \(summary.settings.oldFileAgeYears) \(summary.settings.oldFileAgeYears == 1 ? "year" : "years")

        | Name | Modified | Size |
        |---|---|---:|
        \(oldCleanupRows.isEmpty ? "| No candidates | - | - |" : oldCleanupRows)

        ### Temporary / cache-like files

        | Name | Size | Modified |
        |---|---:|---|
        \(temporaryCleanupRows.isEmpty ? "| No candidates | - | - |" : temporaryCleanupRows)

        ## Largest Files

        | Name | Size | Modified |
        |---|---:|---|
        \(largestRows.isEmpty ? "| No files found | - | - |" : largestRows)

        ## Recently Modified Files

        | Name | Modified | Size |
        |---|---|---:|
        \(recentRows.isEmpty ? "| No files found | - | - |" : recentRows)

        ## Full File List

        | Name | Type | Size | Modified |
        |---|---|---:|---|
        \(allFileRows.isEmpty ? "| No files found | - | - | - |" : allFileRows)

        ---

        Generated by FolderLens.
        """
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    private func escapeMarkdownTableText(_ text: String) -> String {
        encodeVisibleSpecialCharacters(text)
    }

    private func formatPathCode(_ path: String) -> String {
        "<code>\(encodeVisibleSpecialCharacters(path))</code>"
    }

    private func encodeVisibleSpecialCharacters(_ text: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(text.utf8.count)

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 38:
                encoded += "&amp;"
            case 60:
                encoded += "&lt;"
            case 62:
                encoded += "&gt;"
            case 92:
                encoded += "&#92;"
            case 96:
                encoded += "&#96;"
            case 124:
                encoded += "&#124;"
            case 13:
                encoded += "&#x240D;"
            case 10:
                encoded += "&#x240A;"
            default:
                encoded.append(contentsOf: String(scalar))
            }
        }

        return encoded
    }
}
