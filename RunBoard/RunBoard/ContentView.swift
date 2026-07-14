import SwiftUI
import AppKit

enum FileFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case images = "Images"
    case pdfs = "PDFs"
    case videos = "Videos"
    case archives = "Archives"
    case code = "Code"
    case text = "Text"
    case large = "Large files"

    var id: String {
        rawValue
    }
}

struct ContentView: View {
    @AppStorage("largeFileThresholdMB") private var largeFileThresholdMB: Int = ScanSettings.default.largeFileThresholdMB
    @AppStorage("oldFileAgeYears") private var oldFileAgeYears: Int = ScanSettings.default.oldFileAgeYears
    @AppStorage("includeHiddenFiles") private var includeHiddenFiles: Bool = ScanSettings.default.includeHiddenFiles
    @StateObject private var scanModel = FolderScanViewModel()

    @State private var rootFolderURL: URL?
    @State private var currentFolderURL: URL?
    @State private var folderHistory: [URL] = []

    @State private var selectedFile: FileItem?
    @State private var searchText: String = ""
    @State private var isDeepScanEnabled: Bool = false
    @State private var selectedFilter: FileFilter = .all

    private var files: [FileItem] { scanModel.files }
    private var currentFolderSummary: FolderSummary? { scanModel.summary }

    static func isScanInProgress(_ status: FolderScanStatus) -> Bool {
        status == .scanning || status == .verifyingDuplicates
    }

    private var scanSettings: ScanSettings {
        ScanSettings(
            largeFileThresholdMB: largeFileThresholdMB,
            oldFileAgeYears: oldFileAgeYears,
            includeHiddenFiles: includeHiddenFiles
        )
    }

    private var filteredFiles: [FileItem] {
        let searchedFiles: [FileItem]

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchedFiles = files
        } else {
            searchedFiles = files.filter { file in
                file.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch selectedFilter {
        case .all:
            return searchedFiles

        case .images:
            return searchedFiles.filter { $0.isImage }

        case .pdfs:
            return searchedFiles.filter { $0.fileExtension == "pdf" }

        case .videos:
            return searchedFiles.filter {
                ["mp4", "mov", "avi", "mkv"].contains($0.fileExtension)
            }

        case .archives:
            return searchedFiles.filter {
                ["zip", "tar", "gz", "rar", "7z"].contains($0.fileExtension)
            }

        case .code:
            return searchedFiles.filter {
                ["swift", "py", "js", "ts", "html", "css", "java", "cpp", "c", "h", "rs", "go", "sh"].contains($0.fileExtension)
            }

        case .text:
            return searchedFiles.filter {
                ["txt", "md", "json", "csv", "log", "tex"].contains($0.fileExtension)
            }

        case .large:
            return searchedFiles.filter {
                !$0.isDirectory && $0.size >= scanSettings.largeFileThresholdBytes
            }
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
            searchAndFilterSection
            scanSettingsSection
            toolbarRow

            ScanStatusView(
                status: scanModel.status,
                progress: scanModel.progress,
                verificationProgress: scanModel.verificationProgress,
                warningCount: scanModel.warnings.count,
                onCancel: scanModel.cancel
            )
            .padding(.horizontal)

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
        .accessibilityIdentifier("select-folder-button")
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

    private var searchAndFilterSection: some View {
        VStack(spacing: 8) {
            TextField("Search files...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("Filter", selection: $selectedFilter) {
                ForEach(FileFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal)
    }

    private var scanSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scan Settings", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(includeHiddenFiles ? "Hidden included" : "Hidden skipped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Stepper("Large: \(largeFileThresholdMB) MB", value: $largeFileThresholdMB, in: 10...2048, step: 10)
                .onChange(of: largeFileThresholdMB) { _ in
                    reloadCurrentFolder()
                }

            Stepper("Old: \(oldFileAgeYears) \(oldFileAgeYears == 1 ? "year" : "years")", value: $oldFileAgeYears, in: 1...10)
                .onChange(of: oldFileAgeYears) { _ in
                    reloadCurrentFolder()
                }

            Toggle(isOn: $includeHiddenFiles) {
                Label("Include Hidden Files", systemImage: includeHiddenFiles ? "eye" : "eye.slash")
            }
            .toggleStyle(.switch)
            .onChange(of: includeHiddenFiles) { _ in
                reloadCurrentFolder()
            }
        }
        .font(.caption)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .disabled(
                    currentFolderURL == nil
                        || currentFolderSummary == nil
                        || Self.isScanInProgress(scanModel.status)
                )

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
                reloadCurrentFolder()
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
            selectedFilter = .all
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
        selectedFilter = .all
        loadFiles(from: folderURL)
    }

    private func goBack() {
        guard let previousFolder = folderHistory.popLast() else {
            return
        }

        currentFolderURL = previousFolder
        selectedFile = nil
        searchText = ""
        selectedFilter = .all
        loadFiles(from: previousFolder)
    }

    private func reloadCurrentFolder() {
        guard let currentFolderURL else {
            return
        }

        selectedFile = nil
        loadFiles(from: currentFolderURL)
    }

    private func loadFiles(from folderURL: URL) {
        scanModel.start(
            context: FolderScanContext(
                folderURL: folderURL,
                isDeepScan: isDeepScanEnabled,
                settings: scanSettings
            )
        )
    }

    private func exportMarkdownSummary() {
        guard let summary = currentFolderSummary else {
            return
        }

        let markdown = FolderReportBuilder().makeMarkdown(summary: summary, files: files)

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
