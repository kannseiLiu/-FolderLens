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
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            if file.isDirectory {
                folderPreview
            } else if file.isImage {
                imagePreview
            } else if file.isTextLike {
                textPreview
            } else {
                unsupportedPreview
            }

            Spacer()
        }
        .padding(32)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.name)
                .font(.largeTitle)
                .bold()

            Text(file.url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var folderPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Folder", systemImage: "folder")
                .font(.title2)

            Text("Folder navigation will be added next.")
                .foregroundStyle(.secondary)
        }
    }

    private var imagePreview: some View {
        Group {
            if let nsImage = NSImage(contentsOf: file.url) {
                ScrollView {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text("Could not load image.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var textPreview: some View {
        Group {
            if let text = try? String(contentsOf: file.url, encoding: .utf8) {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                Text("Could not read text file.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unsupportedPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unsupported file type", systemImage: "doc")
                .font(.title2)

            Text("Preview is currently available for PNG, JPG, TXT, Markdown, JSON, CSV, and LOG files.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    FilePreviewView(
        file: FileItem(
            url: URL(fileURLWithPath: "/tmp/example.txt"),
            name: "example.txt",
            isDirectory: false
        )
    )
}
