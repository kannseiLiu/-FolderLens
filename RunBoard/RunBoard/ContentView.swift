import SwiftUI
import AppKit

struct ContentView: View {
    @State private var rootFolderURL: URL?
    @State private var currentFolderURL: URL?
    @State private var folderHistory: [URL] = []

    @State private var files: [FileItem] = []
    @State private var selectedFile: FileItem?
    @State private var currentFolderSummary: FolderSummary?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                Button("Select Experiment Folder") {
                    selectFolder()
                }
                .padding(.top)

                if let currentFolderURL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(currentFolderURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal)
                }

                HStack {
                    Button {
                        goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(folderHistory.isEmpty)

                    Spacer()

                    Text("\(files.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                List(files, selection: $selectedFile) { file in
                    HStack {
                        Image(systemName: iconName(for: file))
                            .foregroundStyle(file.isDirectory ? .blue : .secondary)

                        VStack(alignment: .leading) {
                            Text(file.name)
                                .font(.headline)

                            Text(file.typeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if file.isDirectory {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(file)
                    .onTapGesture {
                        handleSelection(file)
                    }
                }
            }
            .navigationTitle("LabShelf")
        } detail: {
            if let selectedFile {
                FilePreviewView(file: selectedFile)
            } else if let currentFolderSummary {
                FolderSummaryView(summary: currentFolderSummary)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Experiment Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            rootFolderURL = url
            currentFolderURL = url
            folderHistory = []
            selectedFile = nil
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
        loadFiles(from: folderURL)
    }

    private func goBack() {
        guard let previousFolder = folderHistory.popLast() else {
            return
        }

        currentFolderURL = previousFolder
        selectedFile = nil
        loadFiles(from: previousFolder)
    }

    private func loadFiles(from folderURL: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let loadedFiles = urls.map { url in
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])

                return FileItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: resourceValues?.isDirectory ?? false
                )
            }

            files = loadedFiles.sorted { first, second in
                if first.isDirectory != second.isDirectory {
                    return first.isDirectory && !second.isDirectory
                }
                return first.name.lowercased() < second.name.lowercased()
            }

            currentFolderSummary = makeSummary(for: folderURL, files: loadedFiles)

        } catch {
            print("Failed to load files: \(error)")
            files = []
            currentFolderSummary = nil
        }
    }

    private func iconName(for file: FileItem) -> String {
        if file.isDirectory {
            return "folder"
        }

        switch file.fileExtension {
        case "png", "jpg", "jpeg":
            return "photo"
        case "txt", "md", "json", "csv", "log":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private func makeSummary(for folderURL: URL, files: [FileItem]) -> FolderSummary {
        let folderCount = files.filter { $0.isDirectory }.count
        let imageCount = files.filter { $0.isImage }.count
        let csvCount = files.filter { $0.fileExtension == "csv" }.count
        let jsonCount = files.filter { $0.fileExtension == "json" }.count
        let textCount = files.filter {
            ["txt", "md"].contains($0.fileExtension)
        }.count
        let logCount = files.filter { $0.fileExtension == "log" }.count

        let knownCount = folderCount + imageCount + csvCount + jsonCount + textCount + logCount
        let otherCount = max(files.count - knownCount, 0)

        return FolderSummary(
            folderURL: folderURL,
            totalCount: files.count,
            folderCount: folderCount,
            imageCount: imageCount,
            csvCount: csvCount,
            jsonCount: jsonCount,
            textCount: textCount,
            logCount: logCount,
            otherCount: otherCount
        )
    }
}

#Preview {
    ContentView()
}
