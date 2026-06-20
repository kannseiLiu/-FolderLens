import SwiftUI

struct ContentView: View {
    @State private var selectedFolderURL: URL?
    @State private var files: [FileItem] = []

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

                List(files) { file in
                    HStack {
                        Image(systemName: file.isDirectory ? "folder" : "doc")
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
                }
            }
            .navigationTitle("LabShelf")
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                Text("LabShelf")
                    .font(.largeTitle)
                    .bold()

                Text("Browse local scientific experiment folders.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Select a folder from the sidebar to inspect experiment results, figures, logs, and configs.")
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(32)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Experiment Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolderURL = url
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
                let isDirectory = resourceValues?.isDirectory ?? false

                return FileItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: isDirectory
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
}

#Preview {
    ContentView()
}
