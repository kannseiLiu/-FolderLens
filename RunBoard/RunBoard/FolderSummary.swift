//
//  FolderSummary.swift
//  RunBoard
//
//  Created by sheng on 2026/06/20.
//
import Foundation

struct FolderSummary {
    let folderURL: URL
    let totalCount: Int
    let folderCount: Int
    let imageCount: Int
    let csvCount: Int
    let jsonCount: Int
    let textCount: Int
    let logCount: Int
    let pdfCount: Int
    let archiveCount: Int
    let videoCount: Int
    let codeCount: Int
    let otherCount: Int
    let totalSize: Int64
    let largestFiles: [FileItem]
    let recentFiles: [FileItem]

    var folderName: String {
        folderURL.lastPathComponent
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
