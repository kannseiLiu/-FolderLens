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
            Text("LabShelf")
                .font(.largeTitle)
                .bold()

            Text("Browse local scientific experiment folders.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Divider()

            Text("Select a folder, then click a file to preview figures, logs, configs, and result tables.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    WelcomeView()
}
