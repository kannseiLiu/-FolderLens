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
    let otherCount: Int

    var folderName: String {
        folderURL.lastPathComponent
    }
}
