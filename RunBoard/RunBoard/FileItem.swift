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
        ["png", "jpg", "jpeg"].contains(fileExtension)
    }

    var isTextLike: Bool {
        ["txt", "md", "json", "csv", "log"].contains(fileExtension)
    }
}
