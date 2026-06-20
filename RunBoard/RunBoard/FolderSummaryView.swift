//
//  FolderSummaryView.swift
//  RunBoard
//
//  Created by sheng on 2026/06/20.
//
import SwiftUI

struct FolderSummaryView: View {
    let summary: FolderSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(summary.folderName)
                .font(.largeTitle)
                .bold()

            Text(summary.folderURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                SummaryRow(label: "Total items", value: summary.totalCount, icon: "tray.full")
                SummaryRow(label: "Folders", value: summary.folderCount, icon: "folder")
                SummaryRow(label: "Images", value: summary.imageCount, icon: "photo")
                SummaryRow(label: "CSV files", value: summary.csvCount, icon: "tablecells")
                SummaryRow(label: "JSON files", value: summary.jsonCount, icon: "curlybraces")
                SummaryRow(label: "Text / Markdown files", value: summary.textCount, icon: "doc.text")
                SummaryRow(label: "Log files", value: summary.logCount, icon: "terminal")
                SummaryRow(label: "Other files", value: summary.otherCount, icon: "doc")
            }

            Spacer()
        }
        .padding(32)
    }
}

struct SummaryRow: View {
    let label: String
    let value: Int
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)

            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            Text("\(value)")
                .bold()
        }
        .font(.title3)
    }
}

#Preview {
    FolderSummaryView(
        summary: FolderSummary(
            folderURL: URL(fileURLWithPath: "/Users/example/results/run_001"),
            totalCount: 12,
            folderCount: 2,
            imageCount: 3,
            csvCount: 2,
            jsonCount: 1,
            textCount: 1,
            logCount: 1,
            otherCount: 2
        )
    )
}
