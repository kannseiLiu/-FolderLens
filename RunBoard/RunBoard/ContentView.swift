//
//  ContentView.swift
//  RunBoard
//
//  Created by sheng on 2026/06/18.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing:12) {
            Text("RunBoard")
                .font(.largeTitle)
                .bold()
            
            Text("A macOS dashboard for tracking scientific ML experiments.")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text("App is running.")
                .padding(.top,8)
        }
        .frame(width:600,height:400)
        .padding()
    }
}


#Preview {
    ContentView()
}
