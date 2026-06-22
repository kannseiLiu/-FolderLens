//
//  WelcomeView.swift
//  RunBoard
//
//  Created by sheng on 2026/06/20.
//
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FolderLens")
                .font(.system(size: 38, weight: .bold, design: .rounded))

            Text("Inspect, preview, and summarize local folders.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Divider()

            Text("Select a folder to see file type statistics, large files, recent files, previews, and exportable Markdown reports.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    WelcomeView()
}
