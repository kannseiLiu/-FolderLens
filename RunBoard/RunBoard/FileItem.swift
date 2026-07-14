//
//  FileItem.swift
//  RunBoard
//
//  Created by sheng on 2026/06/20.
//
import Foundation
import Darwin

struct FileSystemIdentity: Hashable, Sendable, CustomStringConvertible {
    let systemNumber: UInt64
    let fileNumber: UInt64

    init(systemNumber: UInt64, fileNumber: UInt64) {
        self.systemNumber = systemNumber
        self.fileNumber = fileNumber
    }

    init(fileURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let identity = Self(attributes: attributes) else {
            throw FileSystemIdentityError.unavailable
        }
        self = identity
    }

    init(fileStatus: stat) {
        self.systemNumber = UInt64(fileStatus.st_dev)
        self.fileNumber = UInt64(fileStatus.st_ino)
    }

    private init?(attributes: [FileAttributeKey: Any]) {
        guard let systemNumber = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            return nil
        }

        self.systemNumber = systemNumber
        self.fileNumber = fileNumber
    }

    var description: String {
        "\(systemNumber):\(fileNumber)"
    }
}

private enum FileSystemIdentityError: Error {
    case unavailable
}

struct FileItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isRegularFile: Bool
    let isSymbolicLink: Bool
    let size: Int64
    let modifiedDate: Date?
    let fileSystemIdentity: FileSystemIdentity?

    init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isRegularFile: Bool? = nil,
        isSymbolicLink: Bool = false,
        size: Int64,
        modifiedDate: Date?,
        fileSystemIdentity: FileSystemIdentity? = nil
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isRegularFile = isRegularFile ?? false
        self.isSymbolicLink = isSymbolicLink
        self.size = size
        self.modifiedDate = modifiedDate
        self.fileSystemIdentity = fileSystemIdentity
    }

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
