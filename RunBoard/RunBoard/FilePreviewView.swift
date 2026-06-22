//
//  FilePreviewView.swift
//  RunBoard
//
//  Created by sheng on 2026/06/20.
//
import SwiftUI
import AppKit

struct FilePreviewView: View {
    let file: FileItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if file.isDirectory {
                    folderPreview
                } else if file.isImage {
                    imagePreview
                } else if file.isTextLike {
                    textPreview
                } else {
                    unsupportedPreview
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: headerIcon)
                .font(.system(size: 34))
                .foregroundStyle(file.isDirectory ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(file.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Text(file.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Badge(text: file.typeDescription)

                    if !file.isDirectory {
                        Badge(text: file.formattedSize)
                    }

                    Badge(text: file.formattedModifiedDate)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
    }

    private var folderPreview: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Folder", systemImage: "folder")
                    .font(.title2)
                    .bold()

                Text("Open this folder from the sidebar to inspect its contents.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var imagePreview: some View {
        CardView {
            if let nsImage = NSImage(contentsOf: file.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("Could not load image.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var textPreview: some View {
        CardView {
            if let text = try? String(contentsOf: file.url, encoding: .utf8) {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("Could not read text file.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unsupportedPreview: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Preview unavailable", systemImage: "doc")
                    .font(.title2)
                    .bold()

                Text("FolderLens currently supports previewing images and text-like files.")
                    .foregroundStyle(.secondary)

                Text("Supported: PNG, JPG, HEIC, WEBP, GIF, TXT, Markdown, JSON, CSV, LOG, Swift, Python, JavaScript, HTML, CSS, and LaTeX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headerIcon: String {
        if file.isDirectory {
            return "folder.fill"
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

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial)
            .clipShape(Capsule())
    }
}

#Preview {
    FilePreviewView(
        file: FileItem(
            url: URL(fileURLWithPath: "/tmp/example.txt"),
            name: "example.txt",
            isDirectory: false,
            size: 1024,
            modifiedDate: Date()
        )
    )
}
