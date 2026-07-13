import SwiftUI

struct FolderSummaryView: View {
    let summary: FolderSummary
    let onSelectFile: (FileItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                headerSection

                healthOverviewCard

                quickStatsGrid

                cleanupSuggestionsCard

                folderHotspotsCard

                duplicateFilesCard

                fileTypeBreakdownCard

                largestFilesCard

                recentFilesCard
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        CardView {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.blue.opacity(0.14))
                        .frame(width: 64, height: 64)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.folderName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(2)

                    Text(summary.folderURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        StatusBadge(
                            text: summary.isDeepScan ? "Deep Scan" : "Current Folder",
                            systemImage: summary.isDeepScan ? "scope" : "folder",
                            isHighlighted: summary.isDeepScan
                        )

                        StatusBadge(
                            text: "\(summary.totalCount) items",
                            systemImage: "tray.full",
                            isHighlighted: false
                        )

                        StatusBadge(
                            text: summary.formattedTotalSize,
                            systemImage: "internaldrive",
                            isHighlighted: false
                        )

                        StatusBadge(
                            text: summary.settings.includeHiddenFiles ? "Hidden included" : "Hidden skipped",
                            systemImage: summary.settings.includeHiddenFiles ? "eye" : "eye.slash",
                            isHighlighted: summary.settings.includeHiddenFiles
                        )
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
        }
    }

    // MARK: - Quick Stats

    private var healthOverviewCard: some View {
        CardView {
            HStack(alignment: .top, spacing: 24) {
                HealthScoreView(
                    score: summary.healthScore,
                    level: summary.healthLevel,
                    tint: healthTint
                )
                .frame(width: 190)

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "Action Plan",
                        subtitle: "Prioritized next steps based on disk impact and review risk",
                        icon: "checklist"
                    )

                    VStack(spacing: 10) {
                        ForEach(summary.actionPlan) { action in
                            ActionPlanRow(action: action, tint: healthTint)
                        }
                    }
                }
            }
        }
    }

    private var healthTint: Color {
        switch summary.healthLevel {
        case .excellent:
            return .green
        case .good:
            return .blue
        case .needsReview:
            return .orange
        case .critical:
            return .red
        }
    }

    private var quickStatsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 180), spacing: 16)
            ],
            spacing: 16
        ) {
            StatCard(
                title: "Total Size",
                value: summary.formattedTotalSize,
                icon: "internaldrive",
                tint: .blue
            )

            StatCard(
                title: "Items",
                value: "\(summary.totalCount)",
                icon: "tray.full",
                tint: .purple
            )

            StatCard(
                title: "Folders",
                value: "\(summary.folderCount)",
                icon: "folder",
                tint: .blue
            )

            StatCard(
                title: "Images",
                value: "\(summary.imageCount)",
                icon: "photo",
                tint: .pink
            )

            StatCard(
                title: "PDFs",
                value: "\(summary.pdfCount)",
                icon: "doc.richtext",
                tint: .red
            )

            StatCard(
                title: "Code",
                value: "\(summary.codeCount)",
                icon: "chevron.left.forwardslash.chevron.right",
                tint: .green
            )

            StatCard(
                title: "Videos",
                value: "\(summary.videoCount)",
                icon: "film",
                tint: .orange
            )

            StatCard(
                title: "Archives",
                value: "\(summary.archiveCount)",
                icon: "archivebox",
                tint: .brown
            )

            StatCard(
                title: "Review Size",
                value: summary.formattedReviewableSize,
                icon: "magnifyingglass.circle",
                tint: .orange
            )

            StatCard(
                title: "Recoverable",
                value: summary.formattedRecoverableSize,
                icon: "arrow.down.circle",
                tint: .green
            )
        }
    }

    // MARK: - File Type Breakdown
    private var cleanupSuggestionsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeader(
                        title: "Cleanup Suggestions",
                        subtitle: "Safe suggestions only. FolderLens never deletes files automatically.",
                        icon: "sparkles"
                    )

                    Spacer()

                    StatusBadge(
                        text: "\(summary.cleanupCandidateCount) candidates",
                        systemImage: "exclamationmark.triangle",
                        isHighlighted: summary.cleanupCandidateCount > 0
                    )
                }

                if summary.cleanupCandidateCount == 0 {
                    EmptyRankingView(text: "No obvious cleanup candidates found.")
                } else {
                    VStack(spacing: 16) {
                        CleanupGroup(
                            title: "Large files over \(summary.settings.largeFileThresholdMB) MB",
                            icon: "externaldrive.badge.exclamationmark",
                            files: summary.largeFiles,
                            trailingText: { $0.formattedSize },
                            subtitleText: { $0.formattedModifiedDate },
                            onSelectFile: onSelectFile
                        )

                        CleanupGroup(
                            title: "Old files not modified for \(summary.settings.oldFileAgeYears) \(summary.settings.oldFileAgeYears == 1 ? "year" : "years")",
                            icon: "clock.badge.exclamationmark",
                            files: summary.oldFiles,
                            trailingText: { $0.formattedModifiedDate },
                            subtitleText: { $0.formattedSize },
                            onSelectFile: onSelectFile
                        )

                        CleanupGroup(
                            title: "Temporary / cache-like files",
                            icon: "trash",
                            files: summary.temporaryFiles,
                            trailingText: { $0.formattedSize },
                            subtitleText: { $0.formattedModifiedDate },
                            onSelectFile: onSelectFile
                        )
                    }
                }
            }
        }
    }
    private var fileTypeBreakdownCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    title: "File Type Breakdown",
                    subtitle: "Distribution by detected file type",
                    icon: "chart.pie"
                )

                VStack(spacing: 14) {
                    FileTypeRow(
                        label: "Images",
                        count: summary.imageCount,
                        total: summary.totalCount,
                        icon: "photo",
                        tint: .pink
                    )

                    FileTypeRow(
                        label: "PDFs",
                        count: summary.pdfCount,
                        total: summary.totalCount,
                        icon: "doc.richtext",
                        tint: .red
                    )

                    FileTypeRow(
                        label: "Code",
                        count: summary.codeCount,
                        total: summary.totalCount,
                        icon: "chevron.left.forwardslash.chevron.right",
                        tint: .green
                    )

                    FileTypeRow(
                        label: "CSV",
                        count: summary.csvCount,
                        total: summary.totalCount,
                        icon: "tablecells",
                        tint: .teal
                    )

                    FileTypeRow(
                        label: "JSON",
                        count: summary.jsonCount,
                        total: summary.totalCount,
                        icon: "curlybraces",
                        tint: .indigo
                    )

                    FileTypeRow(
                        label: "Text",
                        count: summary.textCount,
                        total: summary.totalCount,
                        icon: "doc.text",
                        tint: .cyan
                    )

                    FileTypeRow(
                        label: "Logs",
                        count: summary.logCount,
                        total: summary.totalCount,
                        icon: "terminal",
                        tint: .gray
                    )

                    FileTypeRow(
                        label: "Videos",
                        count: summary.videoCount,
                        total: summary.totalCount,
                        icon: "film",
                        tint: .orange
                    )

                    FileTypeRow(
                        label: "Archives",
                        count: summary.archiveCount,
                        total: summary.totalCount,
                        icon: "archivebox",
                        tint: .brown
                    )

                    FileTypeRow(
                        label: "Other",
                        count: summary.otherCount,
                        total: summary.totalCount,
                        icon: "doc",
                        tint: .secondary
                    )
                }
            }
        }
    }

    private var folderHotspotsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Folder Size Hotspots",
                    subtitle: summary.isDeepScan
                        ? "Subfolders ranked by total nested file size"
                        : "Turn on Deep Scan to rank nested folder sizes",
                    icon: "folder.badge.gearshape"
                )

                if summary.largestFolders.isEmpty {
                    EmptyRankingView(text: summary.isDeepScan ? "No nested folder hotspots found." : "Deep Scan is required for folder hotspots.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(summary.largestFolders.enumerated()), id: \.element.id) { index, folder in
                            FolderHotspotRow(index: index + 1, folder: folder)

                            if index != summary.largestFolders.count - 1 {
                                Divider()
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
    }

    private var duplicateFilesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Potential Duplicates",
                    subtitle: "Files with matching names and sizes. Review before deleting anything.",
                    icon: "doc.on.doc"
                )

                if summary.duplicateGroups.isEmpty {
                    EmptyRankingView(text: "No potential duplicate groups found.")
                } else {
                    VStack(spacing: 14) {
                        ForEach(summary.duplicateGroups) { group in
                            DuplicateGroupRow(group: group)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Largest Files

    private var largestFilesCard: some View {
        FileRankingCard(
            title: "Largest Files",
            subtitle: summary.isDeepScan
                ? "Largest files found across all subfolders"
                : "Largest files in the current folder",
            icon: "chart.bar.doc.horizontal",
            files: summary.largestFiles,
            emptyText: "No files found.",
            trailingText: { file in
                file.formattedSize
            },
            subtitleText: { file in
                file.formattedModifiedDate
            },
            onSelectFile: onSelectFile
        )
    }

    // MARK: - Recent Files

    private var recentFilesCard: some View {
        FileRankingCard(
            title: "Recently Modified",
            subtitle: summary.isDeepScan
                ? "Recently modified files across all subfolders"
                : "Recently modified files in the current folder",
            icon: "clock.arrow.circlepath",
            files: summary.recentFiles,
            emptyText: "No recently modified files found.",
            trailingText: { file in
                file.formattedModifiedDate
            },
            subtitleText: { file in
                file.formattedSize
            },
            onSelectFile: onSelectFile
        )
    }
}

struct HealthScoreView: View {
    let score: Int
    let level: FolderHealthLevel
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: level.systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)

                Text("Health Score")
                    .font(.headline)
            }

            Text("\(score)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)

            ProgressView(value: Double(score), total: 100)
                .tint(tint)

            Text(level.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActionPlanRow: View {
    let action: FolderActionItem
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)

                Image(systemName: action.systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.headline)

                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CleanupGroup: View {
    let title: String
    let icon: String
    let files: [FileItem]
    let trailingText: (FileItem) -> String
    let subtitleText: (FileItem) -> String
    let onSelectFile: (FileItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)

                Spacer()

                Text("\(files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if files.isEmpty {
                Text("No candidates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        Button {
                            onSelectFile(file)
                        } label: {
                            FileRankingRow(
                                index: index + 1,
                                file: file,
                                trailingText: trailingText(file),
                                subtitleText: subtitleText(file)
                            )
                        }
                        .buttonStyle(.plain)

                        if index != files.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
// MARK: - Reusable Components

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2)
                    .bold()

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct StatusBadge: View {
    let text: String
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHighlighted ? .blue.opacity(0.14) : .secondary.opacity(0.10))
            .foregroundStyle(isHighlighted ? .blue : .secondary)
            .clipShape(Capsule())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .frame(width: 38, height: 38)

                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(tint)
                    }

                    Spacer()
                }

                Text(value)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FileTypeRow: View {
    let label: String
    let count: Int
    let total: Int
    let icon: String
    let tint: Color

    private var fraction: Double {
        guard total > 0 else {
            return 0
        }

        return Double(count) / Double(total)
    }

    private var percentageText: String {
        guard total > 0 else {
            return "0%"
        }

        return "\(Int((fraction * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(tint)

            Text(label)
                .font(.subheadline)
                .frame(width: 82, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    Capsule()
                        .fill(tint.opacity(0.75))
                        .frame(width: max(count == 0 ? 0 : 4, geometry.size.width * fraction))
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.headline)
                .frame(width: 42, alignment: .trailing)

            Text(percentageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct FileRankingCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let files: [FileItem]
    let emptyText: String
    let trailingText: (FileItem) -> String
    let subtitleText: (FileItem) -> String
    let onSelectFile: (FileItem) -> Void

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeader(
                        title: title,
                        subtitle: subtitle,
                        icon: icon
                    )

                    Spacer()

                    Text("Top \(files.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if files.isEmpty {
                    EmptyRankingView(text: emptyText)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            Button {
                                onSelectFile(file)
                            } label: {
                                FileRankingRow(
                                    index: index + 1,
                                    file: file,
                                    trailingText: trailingText(file),
                                    subtitleText: subtitleText(file)
                                )
                            }
                            .buttonStyle(.plain)

                            if index != files.count - 1 {
                                Divider()
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct FolderHotspotRow: View {
    let index: Int
    let folder: FolderHotspot

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Image(systemName: "folder.fill")
                .frame(width: 24)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(folder.fileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(folder.formattedSize)
                .font(.headline)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateFileGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 24)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Text("\(group.files.count) copies · \(group.formattedFileSize) each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(group.formattedRecoverableSize)
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(group.files.prefix(3)) { file in
                    Text(file.url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .padding(.leading, 36)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyRankingView: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .foregroundStyle(.secondary)

            Text(text)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 12)
    }
}

struct FileRankingRow: View {
    let index: Int
    let file: FileItem
    let trailingText: String
    let subtitleText: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Image(systemName: iconName)
                .frame(width: 24)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(trailingText)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        if file.isImage {
            return "photo"
        }

        switch file.fileExtension {
        case "pdf":
            return "doc.richtext"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "zip", "tar", "gz", "rar", "7z":
            return "archivebox"
        case "csv":
            return "tablecells"
        case "json":
            return "curlybraces"
        case "swift", "py", "js", "ts", "html", "css", "java", "cpp", "c", "h", "rs", "go", "sh":
            return "chevron.left.forwardslash.chevron.right"
        case "txt", "md", "log", "tex":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private var iconColor: Color {
        if file.isImage {
            return .pink
        }

        switch file.fileExtension {
        case "pdf":
            return .red
        case "mp4", "mov", "avi", "mkv":
            return .orange
        case "zip", "tar", "gz", "rar", "7z":
            return .brown
        case "csv":
            return .teal
        case "json":
            return .indigo
        case "swift", "py", "js", "ts", "html", "css", "java", "cpp", "c", "h", "rs", "go", "sh":
            return .green
        case "txt", "md", "log", "tex":
            return .cyan
        default:
            return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    FolderSummaryView(
        summary: FolderSummary(
            folderURL: URL(fileURLWithPath: "/Users/example/Downloads"),
            totalCount: 120,
            folderCount: 8,
            imageCount: 32,
            csvCount: 4,
            jsonCount: 3,
            textCount: 6,
            logCount: 2,
            pdfCount: 15,
            archiveCount: 7,
            videoCount: 5,
            codeCount: 10,
            otherCount: 28,
            totalSize: 4_800_000_000,
            largestFiles: [],
            recentFiles: [],
            largeFiles: [],
            oldFiles: [],
            temporaryFiles: [],
            isDeepScan: true
        ),
        onSelectFile: { _ in }
    )
}
