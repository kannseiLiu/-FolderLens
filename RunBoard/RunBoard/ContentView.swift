import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selectedFolderURL: URL?
    @State private var files: [FileItem] = []
    @State private var selectedFile: FileItem?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                Button("Select Experiment Folder") {
                    selectFolder()
                }
                .padding(.top)

                if let selectedFolderURL {
                    Text(selectedFolderURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal)
                }

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
                    }
                    .padding(.vertical, 4)
                    .tag(file)
                }
            }
            .navigationTitle("LabShelf")
        } detail: {
            if let selectedFile {
                FilePreviewView(file: selectedFile)
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
            selectedFolderURL = url
            selectedFile = nil
            loadFiles(from: url)
        }
    }

    private func loadFiles(from folderURL: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            files = urls.map { url in
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])

                return FileItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: resourceValues?.isDirectory ?? false
                )
            }
            .sorted { first, second in
                if first.isDirectory != second.isDirectory {
                    return first.isDirectory && !second.isDirectory
                }
                return first.name.lowercased() < second.name.lowercased()
            }
        } catch {
            print("Failed to load files: \(error)")
            files = []
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
}

#Preview {
    ContentView()
}
