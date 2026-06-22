import SwiftUI

struct FolderSummaryView: View {
    let summary: FolderSummary
    let onSelectFile: (FileItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                quickStatsGrid
                fileTypeBreakdownCard
                largestFilesCard
                recentFilesCard
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 34))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.folderName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text(summary.folderURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private var quickStatsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 180), spacing: 16)
            ],
            spacing: 16
        ) {
            StatCard(title: "Total Size", value: summary.formattedTotalSize, icon: "internaldrive")
            StatCard(title: "Items", value: "\(summary.totalCount)", icon: "tray.full")
            StatCard(title: "Folders", value: "\(summary.folderCount)", icon: "folder")
            StatCard(title: "Images", value: "\(summary.imageCount)", icon: "photo")
            StatCard(title: "PDFs", value: "\(summary.pdfCount)", icon: "doc.richtext")
            StatCard(title: "Code", value: "\(summary.codeCount)", icon: "chevron.left.forwardslash.chevron.right")
            StatCard(title: "Videos", value: "\(summary.videoCount)", icon: "film")
            StatCard(title: "Archives", value: "\(summary.archiveCount)", icon: "archivebox")
        }
    }

    private var fileTypeBreakdownCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                Label("File Type Breakdown", systemImage: "chart.pie")
                    .font(.title2)
                    .bold()

                VStack(spacing: 12) {
                    FileTypeRow(label: "Images", count: summary.imageCount, total: summary.totalCount, icon: "photo")
                    FileTypeRow(label: "PDFs", count: summary.pdfCount, total: summary.totalCount, icon: "doc.richtext")
                    FileTypeRow(label: "Code", count: summary.codeCount, total: summary.totalCount, icon: "chevron.left.forwardslash.chevron.right")
                    FileTypeRow(label: "CSV", count: summary.csvCount, total: summary.totalCount, icon: "tablecells")
                    FileTypeRow(label: "JSON", count: summary.jsonCount, total: summary.totalCount, icon: "curlybraces")
                    FileTypeRow(label: "Text", count: summary.textCount, total: summary.totalCount, icon: "doc.text")
                    FileTypeRow(label: "Logs", count: summary.logCount, total: summary.totalCount, icon: "terminal")
                    FileTypeRow(label: "Videos", count: summary.videoCount, total: summary.totalCount, icon: "film")
                    FileTypeRow(label: "Archives", count: summary.archiveCount, total: summary.totalCount, icon: "archivebox")
                    FileTypeRow(label: "Other", count: summary.otherCount, total: summary.totalCount, icon: "doc")
                }
            }
        }
    }

    private var largestFilesCard: some View {
        FileRankingCard(
            title: "Largest Files",
            icon: "chart.bar.doc.horizontal",
            files: summary.largestFiles,
            trailingText: { file in
                file.formattedSize
            },
            subtitleText: { file in
                file.formattedModifiedDate
            },
            onSelectFile: onSelectFile
        )
    }

    private var recentFilesCard: some View {
        FileRankingCard(
            title: "Recently Modified",
            icon: "clock.arrow.circlepath",
            files: summary.recentFiles,
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

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Spacer()
                }

                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

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
                .foregroundStyle(.secondary)

            Text(label)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    Capsule()
                        .fill(.blue.opacity(0.75))
                        .frame(width: max(4, geometry.size.width * fraction))
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.headline)
                .frame(width: 40, alignment: .trailing)

            Text(percentageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .font(.subheadline)
    }
}

struct FileRankingCard: View {
    let title: String
    let icon: String
    let files: [FileItem]
    let trailingText: (FileItem) -> String
    let subtitleText: (FileItem) -> String
    let onSelectFile: (FileItem) -> Void

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.title2)
                        .bold()

                    Spacer()

                    Text("Top \(files.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if files.isEmpty {
                    Text("No files found.")
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(trailingText)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 10)
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
        default:
            return "doc"
        }
    }
}

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
            recentFiles: []
        ),
        onSelectFile: { _ in }
    )
}
