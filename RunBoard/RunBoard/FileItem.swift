//
//  FileItem.swift
//  RunBoard
//
//  Created by sheng on 2026/06/20.
//
import Foundation

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date?

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var typeDescription: String {
        if isDirectory {
            return "Folder"
        }

        if fileExtension.isEmpty {
            return "File"
        }

        return fileExtension.uppercased() + " file"
    }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(fileExtension)
    }

    var isTextLike: Bool {
        [
            "txt", "md", "json", "csv", "log",
            "swift", "py", "js", "ts", "html", "css", "tex",
            "java", "cpp", "c", "h", "rs", "go", "sh"
        ].contains(fileExtension)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedModifiedDate: String {
        guard let modifiedDate else {
            return "Unknown"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
}
