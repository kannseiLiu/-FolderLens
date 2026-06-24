import SwiftUI
import AppKit

struct ContentView: View {
    @State private var rootFolderURL: URL?
    @State private var currentFolderURL: URL?
    @State private var folderHistory: [URL] = []

    @State private var files: [FileItem] = []
    @State private var selectedFile: FileItem?
    @State private var currentFolderSummary: FolderSummary?
    @State private var searchText: String = ""
    @State private var isDeepScanEnabled: Bool = false
    
    private var filteredFiles: [FileItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return files
        }

        return files.filter { file in
            file.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selectedFile {
                FilePreviewView(file: selectedFile)
            } else if let currentFolderSummary {
                FolderSummaryView(
                    summary: currentFolderSummary,
                    onSelectFile: { file in
                        selectedFile = file
                    }
                )
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
    }

    private var sidebar: some View {
        VStack(spacing: 14) {
            sidebarHeader

            selectFolderButton

            currentFolderCard

            searchField

            toolbarRow

            Divider()

            fileList
        }
        .navigationTitle("")
    }

    private var sidebarHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("FolderLens")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("Local folder inspector")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    private var selectFolderButton: some View {
        Button {
            selectFolder()
        } label: {
            Label("Select Folder", systemImage: "folder.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var currentFolderCard: some View {
        if let currentFolderURL {
            VStack(alignment: .leading, spacing: 6) {
                Text("Current Folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(currentFolderURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)

                Text(currentFolderURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        }
    }

    private var searchField: some View {
        TextField("Search files...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
    }

    private var toolbarRow: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(folderHistory.isEmpty)

                Button {
                    exportMarkdownSummary()
                } label: {
                    Label("Report", systemImage: "square.and.arrow.down")
                }
                .disabled(currentFolderURL == nil || currentFolderSummary == nil)

                Spacer()

                Text("\(filteredFiles.count) / \(files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $isDeepScanEnabled) {
                Label("Deep Scan", systemImage: "scope")
            }
            .toggleStyle(.switch)
            .onChange(of: isDeepScanEnabled) { _ in
                if let currentFolderURL {
                    selectedFile = nil
                    loadFiles(from: currentFolderURL)
                }
            }
        }
        .padding(.horizontal)
    }

    private var fileList: some View {
        List(filteredFiles, selection: $selectedFile) { file in
            HStack(spacing: 10) {
                Image(systemName: iconName(for: file))
                    .font(.system(size: 16))
                    .foregroundStyle(file.isDirectory ? .blue : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(file.typeDescription)

                        if !file.isDirectory {
                            Text("·")
                            Text(file.formattedSize)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .tag(file)
            .onTapGesture {
                handleSelection(file)
            }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            rootFolderURL = url
            currentFolderURL = url
            folderHistory = []
            selectedFile = nil
            searchText = ""
            loadFiles(from: url)
        }
    }

    private func handleSelection(_ file: FileItem) {
        if file.isDirectory {
            openFolder(file.url)
        } else {
            selectedFile = file
        }
    }

    private func openFolder(_ folderURL: URL) {
        if let currentFolderURL {
            folderHistory.append(currentFolderURL)
        }

        currentFolderURL = folderURL
        selectedFile = nil
        searchText = ""
        loadFiles(from: folderURL)
    }

    private func goBack() {
        guard let previousFolder = folderHistory.popLast() else {
            return
        }

        currentFolderURL = previousFolder
        selectedFile = nil
        searchText = ""
        loadFiles(from: previousFolder)
    }

    private func loadFiles(from folderURL: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let loadedFiles = urls.map { url in
                makeFileItem(from: url)
            }

            files = loadedFiles.sorted { first, second in
                if first.isDirectory != second.isDirectory {
                    return first.isDirectory && !second.isDirectory
                }

                return first.name.lowercased() < second.name.lowercased()
            }

            let summaryFiles: [FileItem]

            if isDeepScanEnabled {
                summaryFiles = scanFilesRecursively(from: folderURL)
            } else {
                summaryFiles = loadedFiles
            }

            currentFolderSummary = makeSummary(for: folderURL, files: summaryFiles)

        } catch {
            print("Failed to load files: \(error)")
            files = []
            currentFolderSummary = nil
        }
    }
    
    private func makeFileItem(from url: URL) -> FileItem {
        let resourceValues = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        )

        let isDirectory = resourceValues?.isDirectory ?? false
        let fileSize = Int64(resourceValues?.fileSize ?? 0)
        let modifiedDate = resourceValues?.contentModificationDate

        return FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            size: fileSize,
            modifiedDate: modifiedDate
        )
    }
    
    private func scanFilesRecursively(from folderURL: URL) -> [FileItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var result: [FileItem] = []

        for case let url as URL in enumerator {
            let item = makeFileItem(from: url)
            result.append(item)
        }

        return result
    }
    private func makeSummary(for folderURL: URL, files: [FileItem]) -> FolderSummary {
        let folderCount = files.filter { $0.isDirectory }.count
        let imageCount = files.filter { $0.isImage }.count
        let csvCount = files.filter { $0.fileExtension == "csv" }.count
        let jsonCount = files.filter { $0.fileExtension == "json" }.count
        let textCount = files.filter { ["txt", "md"].contains($0.fileExtension) }.count
        let logCount = files.filter { $0.fileExtension == "log" }.count
        let pdfCount = files.filter { $0.fileExtension == "pdf" }.count

        let archiveCount = files.filter {
            ["zip", "tar", "gz", "rar", "7z"].contains($0.fileExtension)
        }.count

        let videoCount = files.filter {
            ["mp4", "mov", "avi", "mkv"].contains($0.fileExtension)
        }.count

        let codeCount = files.filter {
            ["swift", "py", "js", "ts", "html", "css", "java", "cpp", "c", "h", "rs", "go", "sh"].contains($0.fileExtension)
        }.count

        let knownCount = folderCount
            + imageCount
            + csvCount
            + jsonCount
            + textCount
            + logCount
            + pdfCount
            + archiveCount
            + videoCount
            + codeCount

        let otherCount = max(files.count - knownCount, 0)

        let totalSize = files
            .filter { !$0.isDirectory }
            .map { $0.size }
            .reduce(0, +)

        let largestFiles = files
            .filter { !$0.isDirectory }
            .sorted { $0.size > $1.size }
            .prefix(10)
            .map { $0 }

        let recentFiles = files
            .filter { !$0.isDirectory && $0.modifiedDate != nil }
            .sorted {
                ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast)
            }
            .prefix(10)
            .map { $0 }

        return FolderSummary(
            folderURL: folderURL,
            totalCount: files.count,
            folderCount: folderCount,
            imageCount: imageCount,
            csvCount: csvCount,
            jsonCount: jsonCount,
            textCount: textCount,
            logCount: logCount,
            pdfCount: pdfCount,
            archiveCount: archiveCount,
            videoCount: videoCount,
            codeCount: codeCount,
            otherCount: otherCount,
            totalSize: totalSize,
            largestFiles: largestFiles,
            recentFiles: recentFiles,
            isDeepScan: isDeepScanEnabled
        )
    }

    private func exportMarkdownSummary() {
        guard let summary = currentFolderSummary else {
            return
        }

        let markdown = makeMarkdownReport(summary: summary, files: files)

        let savePanel = NSSavePanel()
        savePanel.title = "Export FolderLens Report"
        savePanel.nameFieldStringValue = "\(summary.folderName)_folderlens_report.md"
        savePanel.allowedFileTypes = ["md"]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to export Markdown report: \(error)")
            }
        }
    }

    private func makeMarkdownReport(summary: FolderSummary, files: [FileItem]) -> String {
        let generatedAt = formattedCurrentDate()

        let sortedFiles = files.sorted { first, second in
            if first.isDirectory != second.isDirectory {
                return first.isDirectory && !second.isDirectory
            }
            return first.name.lowercased() < second.name.lowercased()
        }

        let largestRows = summary.largestFiles.map { file in
            "| \(escapeMarkdownTable(file.name)) | \(escapeMarkdownTable(file.formattedSize)) | \(escapeMarkdownTable(file.formattedModifiedDate)) |"
        }
        .joined(separator: "\n")

        let recentRows = summary.recentFiles.map { file in
            "| \(escapeMarkdownTable(file.name)) | \(escapeMarkdownTable(file.formattedModifiedDate)) | \(escapeMarkdownTable(file.formattedSize)) |"
        }
        .joined(separator: "\n")

        let allFileRows = sortedFiles.map { file in
            let sizeText = file.isDirectory ? "-" : file.formattedSize
            return "| \(escapeMarkdownTable(file.name)) | \(escapeMarkdownTable(file.typeDescription)) | \(escapeMarkdownTable(sizeText)) | \(escapeMarkdownTable(file.formattedModifiedDate)) |"
        }
        .joined(separator: "\n")

        return """
        # FolderLens Report

        Generated at: \(generatedAt)

        Path: `\(summary.folderURL.path)`

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

    private func formattedCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private func escapeMarkdownTable(_ text: String) -> String {
        text
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func iconName(for file: FileItem) -> String {
        if file.isDirectory {
            return "folder"
        }

        if file.isImage {
            return "photo"
        }

        if file.isTextLike {
            return "doc.text"
        }

        switch file.fileExtension {
        case "pdf":
            return "doc.richtext"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "zip", "tar", "gz", "rar", "7z":
            return "archivebox"
        default:
            return "doc"
        }
    }
}

#Preview {
    ContentView()
}
