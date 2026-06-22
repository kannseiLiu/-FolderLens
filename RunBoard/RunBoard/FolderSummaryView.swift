import SwiftUI

struct FolderSummaryView: View {
    let summary: FolderSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                quickStatsGrid

                largestFilesCard
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var largestFilesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Largest Files", systemImage: "chart.bar.doc.horizontal")
                        .font(.title2)
                        .bold()

                    Spacer()

                    Text("Top \(summary.largestFiles.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if summary.largestFiles.isEmpty {
                    Text("No files found.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(summary.largestFiles.enumerated()), id: \.element.id) { index, file in
                            LargeFileRow(index: index + 1, file: file)

                            if index != summary.largestFiles.count - 1 {
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

struct LargeFileRow: View {
    let index: Int
    let file: FileItem

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

                Text(file.formattedModifiedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(file.formattedSize)
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
        )
    )
}

